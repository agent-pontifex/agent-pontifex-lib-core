/**
 * The lock plan: which layers, in which order, as data. Every runtime derives
 * its behavior from the same pure function; the matrix lives in
 * `conformance/cases/lock-plan.json`.
 */
/** Which coordination layers a routine engages. Both false is a deliberate pass-through. */
export interface LockLayers {
    /** The fiducia-cloud lease: outermost, cross-host, TTL-bounded, fenced. */
    readonly fiducia: boolean;
    /** A Postgres advisory lock: inner, single-database, released by Postgres. */
    readonly pgAdvisory: boolean;
}
export declare const LAYERS_NONE: LockLayers;
export declare const LAYERS_FIDUCIA_ONLY: LockLayers;
export declare const LAYERS_PG_ONLY: LockLayers;
export declare const LAYERS_BOTH: LockLayers;
/**
 * How the Postgres advisory lock is scoped. `transaction`:
 * `pg_advisory_xact_lock` inside a transaction the routine opens; the work
 * runs inside it; released at commit/rollback. `session`:
 * `pg_advisory_lock` / `pg_advisory_unlock` on one dedicated connection; no
 * transaction is opened.
 */
export type PgScope = "transaction" | "session";
/** One action in a plan. The contract's `LockStep` enum. */
export type LockStep = "fiducia.acquire" | "fiducia.try_acquire" | "fiducia.release" | "pg.begin" | "pg.advisory_xact_lock" | "pg.try_advisory_xact_lock" | "pg.commit" | "pg.rollback" | "pg.advisory_lock" | "pg.try_advisory_lock" | "pg.advisory_unlock" | "work";
export declare const ALL_STEPS: readonly LockStep[];
export interface LockPlan {
    readonly layers: LockLayers;
    readonly pgScope: PgScope;
    readonly wait: boolean;
    readonly steps: readonly LockStep[];
}
/**
 * Compute the plan. Pure; identical across every language slice. `wait`
 * blocks each layer up to its budget; `!wait` uses the non-blocking form of
 * each acquisition and fails fast with `contention`.
 */
export declare function plan(layers: LockLayers, pgScope: PgScope, wait: boolean): LockPlan;
