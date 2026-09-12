/**
 * The outer layer: a fenced, TTL-bounded lease from a lease authority.
 * `Lease` is the seam between this package and fiducia-cloud (or any
 * authority with the same three verbs). `fiducia.ts` ships the adapter over
 * the node HTTP protocol; tests use in-memory fakes.
 */
import type { LockKey } from "./key.js";
/**
 * Minted on every grant, monotonically increasing. Guarded writes should
 * record it (`WHERE fencing_token < $new`) so a holder whose lease lapsed
 * cannot overwrite a newer holder's work. A bigint because it is a 64-bit
 * integer on the wire.
 */
export type FencingToken = bigint;
/** Acquisition tuning shared by every layer. The contract's `AcquireOptions`. */
export interface AcquireOptions {
    /** Lease TTL in ms. Size it to the longest the guarded work can take. */
    readonly ttlMs: number;
    /** Total time to keep waiting, in ms. Ignored when `wait` is false. */
    readonly waitTimeoutMs: number;
    /** Poll interval while waiting on the fiducia layer, in ms. */
    readonly retryIntervalMs: number;
    /** Caller identity for the fiducia layer; also the release key. Absent: a generated id. */
    readonly holder?: string;
}
/** Mirrors the official fiducia clients: 60s lease, 30s wait budget, 250ms poll. */
export declare const DEFAULT_ACQUIRE_OPTIONS: AcquireOptions;
/** A held grant. The contract's `LeaseGrant`. */
export interface LeaseGrant {
    readonly key: LockKey;
    readonly holder: string;
    readonly fencingToken: FencingToken;
    /** Absolute expiry in Unix ms when the authority reports it. */
    readonly leaseExpiresMs?: number;
    readonly ttlMs: number;
}
/**
 * A lease authority: three verbs, fenced. Implementations map native failures
 * onto `LockErrorKind`: contention (`!wait`, held elsewhere), timeout (budget
 * elapsed), transport (unknown ownership), lost_lease (renewal refused).
 */
export interface Lease {
    /** With `wait`, block up to `opts.waitTimeoutMs`; without it, throw `contention` at once if held. */
    acquire(key: LockKey, opts: AcquireOptions, wait: boolean): Promise<LeaseGrant>;
    /** Extend a grant without changing its fencing token. A refusal is `lost_lease`, never a warning. */
    renew(grant: LeaseGrant, ttlMs: number): Promise<LeaseGrant>;
    /** `false` is a committed no-op: the authority matched no grant — the lease had already lapsed. */
    release(grant: LeaseGrant): Promise<boolean>;
}
/** What `work` receives from `withLease`: the grant when the layer is on. */
export interface Guarded {
    readonly key: LockKey;
    /** The fiducia grant; its `fencingToken` is what guarded writes should record. */
    readonly grant: LeaseGrant | undefined;
}
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
export declare function withLease<T>(key: LockKey, engage: boolean, wait: boolean, opts: AcquireOptions, lease: Lease | undefined, work: (guarded: Guarded) => Promise<T>): Promise<T>;
export declare function runWork<T, G>(key: LockKey, guarded: G, work: (guarded: G) => Promise<T>): Promise<T>;
export declare function acquireLease(key: LockKey, wait: boolean, opts: AcquireOptions, lease: Lease): Promise<LeaseGrant>;
export type Outcome<T> = {
    ok: true;
    value: T;
} | {
    ok: false;
    error: unknown;
};
export declare function settled<T>(promise: Promise<T>): Promise<Outcome<T>>;
/** Release the lease and combine its outcome with the inner one. */
export declare function settle<T>(key: LockKey, lease: Lease, grant: LeaseGrant, inner: Outcome<T>): Promise<T>;
