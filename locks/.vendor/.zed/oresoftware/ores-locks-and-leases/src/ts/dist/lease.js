/**
 * The outer layer: a fenced, TTL-bounded lease from a lease authority.
 * `Lease` is the seam between this package and fiducia-cloud (or any
 * authority with the same three verbs). `fiducia.ts` ships the adapter over
 * the node HTTP protocol; tests use in-memory fakes.
 */
import { LockError, cleanupFailure, tagStep } from "./errors.js";
/** Mirrors the official fiducia clients: 60s lease, 30s wait budget, 250ms poll. */
export const DEFAULT_ACQUIRE_OPTIONS = { ttlMs: 60_000, waitTimeoutMs: 30_000, retryIntervalMs: 250 };
/**
 * Run `work` under a fiducia lease only — no database layer. For work that
 * touches no Postgres, or that manages its own transactions and only needs
 * cross-host exclusion and a fencing token.
 *
 * `engage === false` is the contract's "neither" plan: `work` runs with no
 * grant and nothing is acquired. `engage` with no `lease` is `invalid_plan`.
 *
 * Ordering: acquire → work → release. The lease is always released, even
 * when `work` throws. If `work` succeeded but the authority reports that the
 * release matched no grant, the result is `lost_lease`: the lease lapsed
 * while the work ran and its effects may have raced the next holder.
 */
export async function withLease(key, engage, wait, opts, lease, work) {
    if (!engage)
        return runWork(key, { key, grant: undefined }, work);
    if (!lease)
        throw LockError.invalidPlan(key, "layers.fiducia is enabled but no lease authority was supplied");
    const grant = await acquireLease(key, wait, opts, lease);
    const outcome = await settled(runWork(key, { key, grant }, work));
    return settle(key, lease, grant, outcome);
}
export async function runWork(key, guarded, work) {
    try {
        return await work(guarded);
    }
    catch (cause) {
        throw LockError.work(key, cause);
    }
}
export async function acquireLease(key, wait, opts, lease) {
    try {
        return await lease.acquire(key, opts, wait);
    }
    catch (err) {
        throw tagStep(err, wait ? "fiducia.acquire" : "fiducia.try_acquire");
    }
}
export async function settled(promise) {
    try {
        return { ok: true, value: await promise };
    }
    catch (error) {
        return { ok: false, error };
    }
}
/** Release the lease and combine its outcome with the inner one. */
export async function settle(key, lease, grant, inner) {
    const released = await settled(lease.release(grant));
    if (!released.ok) {
        const cleanup = tagStep(released.error, "fiducia.release");
        if (!inner.ok)
            throw cleanupFailure(key, cleanup, inner.error);
        throw cleanup;
    }
    if (!released.value) {
        const cleanup = new LockError("lost_lease", key, `release of \`${key}\` (holder ${grant.holder}, fencing token ${grant.fencingToken}) matched no grant: the lease lapsed while the work ran`, { step: "fiducia.release" });
        if (!inner.ok)
            throw cleanupFailure(key, cleanup, inner.error);
        throw cleanup;
    }
    if (!inner.ok)
        throw inner.error;
    return inner.value;
}
