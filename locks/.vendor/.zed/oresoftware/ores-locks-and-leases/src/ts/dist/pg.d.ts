/**
 * The inner layer: Postgres advisory locks over a node-postgres-shaped
 * client. Nothing here imports `pg`; the structural types below are what
 * `pg.Pool` / `pg.PoolClient` already satisfy, so a service passes its
 * existing pool and no second driver is pulled in.
 */
import { type LockKey } from "./key.js";
import { type AcquireOptions, type Guarded, type Lease } from "./lease.js";
import type { LockLayers } from "./plan.js";
/** The subset of `pg.ClientBase` the routines use. */
export interface PgQueryable {
    query(text: string, values?: readonly unknown[]): Promise<{
        rows: Array<Record<string, unknown>>;
    }>;
}
/** A checked-out connection: `pg.PoolClient`. */
export interface PgPoolClient extends PgQueryable {
    release(err?: Error | boolean): void;
}
/** A pool: `pg.Pool`. */
export interface PgPool {
    connect(): Promise<PgPoolClient>;
}
/** What transaction-scoped work receives. */
export interface XactGuarded extends Guarded {
    /**
     * The client whose open transaction holds the advisory lock, when the
     * Postgres layer is on. Run every statement of the work through it; the
     * lock is released when the routine commits.
     */
    readonly client: PgQueryable | undefined;
}
/** What session-scoped work receives. */
export interface SessionGuarded extends Guarded {
    /** The dedicated connection holding the advisory lock, when the Postgres layer is on. */
    readonly client: PgQueryable | undefined;
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
export declare function withXactLock<T>(key: LockKey, layers: LockLayers, wait: boolean, opts: AcquireOptions, lease: Lease | undefined, pool: PgPool | undefined, work: (guarded: XactGuarded) => Promise<T>): Promise<T>;
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
export declare function withSessionLock<T>(key: LockKey, layers: LockLayers, wait: boolean, opts: AcquireOptions, lease: Lease | undefined, pool: PgPool | undefined, work: (guarded: SessionGuarded) => Promise<T>): Promise<T>;
