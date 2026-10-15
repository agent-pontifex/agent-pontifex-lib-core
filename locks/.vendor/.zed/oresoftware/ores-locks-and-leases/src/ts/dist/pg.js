/**
 * The inner layer: Postgres advisory locks over a node-postgres-shaped
 * client. Nothing here imports `pg`; the structural types below are what
 * `pg.Pool` / `pg.PoolClient` already satisfy, so a service passes its
 * existing pool and no second driver is pulled in.
 */
import { LockError, cleanupFailure, tagStep } from "./errors.js";
import { advisoryKey } from "./key.js";
import { acquireLease, runWork, settle, settled, } from "./lease.js";
function firstBool(rows) {
    const row = rows[0];
    if (!row)
        return false;
    const value = Object.values(row)[0];
    return value === true || value === "t";
}
async function tryLock(client, key, sql, step) {
    let acquired;
    try {
        acquired = firstBool((await client.query(sql, [advisoryKey(key).toString()])).rows);
    }
    catch (cause) {
        throw LockError.database(key, step, cause);
    }
    if (!acquired)
        throw LockError.contention(key, step);
}
async function exec(client, key, sql, step, values) {
    try {
        await client.query(sql, values);
    }
    catch (cause) {
        throw LockError.database(key, step, cause);
    }
}
/**
 * Run `work` under a fiducia lease and/or a transaction-scoped advisory lock
 * (`pg_advisory_xact_lock`).
 *
 * - `layers.fiducia` needs `lease`; `layers.pgAdvisory` needs `pool`. A
 *   missing one is `invalid_plan` before anything is acquired.
 * - `!wait` uses the non-blocking form of every acquisition and fails fast
 *   with `contention`.
 * - The transaction is committed after `work` resolves and rolled back when
 *   it rejects; the lease is released in both cases; the client is always
 *   returned to the pool.
 * - If `work` and commit succeeded but the lease had already lapsed, the
 *   result is `lost_lease`.
 */
export async function withXactLock(key, layers, wait, opts, lease, pool, work) {
    if (layers.fiducia && !lease)
        throw LockError.invalidPlan(key, "layers.fiducia is enabled but no lease authority was supplied");
    if (layers.pgAdvisory && !pool)
        throw LockError.invalidPlan(key, "layers.pgAdvisory is enabled but no pool was supplied");
    const theLease = layers.fiducia ? lease : undefined;
    const grant = theLease ? await acquireLease(key, wait, opts, theLease) : undefined;
    const inner = await settled(layers.pgAdvisory && pool
        ? runXact(key, wait, pool, grant, work)
        : runWork(key, { key, grant, client: undefined }, work));
    if (!theLease || !grant) {
        if (!inner.ok)
            throw inner.error;
        return inner.value;
    }
    return settle(key, theLease, grant, inner);
}
async function runXact(key, wait, pool, grant, work) {
    let client;
    try {
        client = await pool.connect();
    }
    catch (cause) {
        throw LockError.database(key, "pg.begin", cause);
    }
    let failed = false;
    try {
        await exec(client, key, "BEGIN", "pg.begin");
        try {
            if (wait)
                await exec(client, key, "SELECT pg_advisory_xact_lock($1)", "pg.advisory_xact_lock", [advisoryKey(key).toString()]);
            else
                await tryLock(client, key, "SELECT pg_try_advisory_xact_lock($1)", "pg.try_advisory_xact_lock");
            const value = await runWork(key, { key, grant, client }, work);
            await exec(client, key, "COMMIT", "pg.commit");
            return value;
        }
        catch (err) {
            failed = true;
            try {
                await client.query("ROLLBACK");
            }
            catch {
                // The original failure is the one worth reporting.
            }
            throw err;
        }
    }
    finally {
        client.release(failed);
    }
}
/**
 * Run `work` under a fiducia lease and/or a *session*-scoped advisory lock
 * (`pg_advisory_lock` / `pg_advisory_unlock`). No transaction is opened.
 * The lock is taken on a connection checked out of the pool for the whole
 * guarded section, so lock, work and unlock reach the same Postgres session;
 * `work` receives that client and should run its statements through it.
 *
 * An unlock that reports the session did not hold the lock is `database` at
 * `pg.advisory_unlock` and wins over a successful `work`.
 */
export async function withSessionLock(key, layers, wait, opts, lease, pool, work) {
    if (layers.fiducia && !lease)
        throw LockError.invalidPlan(key, "layers.fiducia is enabled but no lease authority was supplied");
    if (layers.pgAdvisory && !pool)
        throw LockError.invalidPlan(key, "layers.pgAdvisory is enabled with session scope but no pool was supplied");
    const theLease = layers.fiducia ? lease : undefined;
    const grant = theLease ? await acquireLease(key, wait, opts, theLease) : undefined;
    const inner = await settled(layers.pgAdvisory && pool
        ? runSession(key, wait, pool, grant, work)
        : runWork(key, { key, grant, client: undefined }, work));
    if (!theLease || !grant) {
        if (!inner.ok)
            throw inner.error;
        return inner.value;
    }
    return settle(key, theLease, grant, inner);
}
async function runSession(key, wait, pool, grant, work) {
    let client;
    try {
        client = await pool.connect();
    }
    catch (cause) {
        throw LockError.database(key, "pg.advisory_lock", cause);
    }
    let poisoned = false;
    try {
        if (wait)
            await exec(client, key, "SELECT pg_advisory_lock($1)", "pg.advisory_lock", [advisoryKey(key).toString()]);
        else
            await tryLock(client, key, "SELECT pg_try_advisory_lock($1)", "pg.try_advisory_lock");
        const inner = await settled(runWork(key, { key, grant, client }, work));
        const unlocked = await settled(client.query("SELECT pg_advisory_unlock($1)", [advisoryKey(key).toString()]));
        if (!unlocked.ok) {
            poisoned = true;
            const cleanup = LockError.database(key, "pg.advisory_unlock", unlocked.error);
            if (!inner.ok)
                throw cleanupFailure(key, cleanup, inner.error);
            throw cleanup;
        }
        if (!firstBool(unlocked.value.rows)) {
            poisoned = true;
            const cleanup = new LockError("database", key, `pg_advisory_unlock reported the session did not hold \`${key}\``, { step: "pg.advisory_unlock" });
            if (!inner.ok)
                throw cleanupFailure(key, cleanup, inner.error);
            throw cleanup;
        }
        if (!inner.ok)
            throw inner.error;
        return inner.value;
    }
    catch (err) {
        throw tagStep(err, "pg.advisory_lock");
    }
    finally {
        // A session that failed to unlock must not go back into the pool.
        client.release(poisoned);
    }
}
