import type { LockKey } from "./key.js";
import type { LockStep } from "./plan.js";
/** Why an acquisition or guarded run failed. The contract's `LockErrorKind`. */
export type LockErrorKind = 
/** A layer is held by someone else and `wait` was false. */
"contention"
/** The wait budget elapsed before every layer was held. */
 | "timeout"
/** The fiducia lease could not be renewed or was reaped; fenced authority is gone. */
 | "lost_lease"
/** Transport/HTTP failure talking to the lease authority; ownership is unknown. */
 | "transport"
/** The database refused the advisory statement, the transaction, or the connection. */
 | "database"
/** The caller's work threw; outer layers were still released / rolled back. */
 | "work"
/** The inputs cannot be planned. */
 | "invalid_plan";
/** The one structured failure every routine surfaces. The contract's `LockError`. */
export declare class LockError extends Error {
    readonly kind: LockErrorKind;
    readonly key: LockKey;
    /** Which step failed, when known. */
    step: LockStep | undefined;
    constructor(kind: LockErrorKind, key: LockKey, message: string, options?: {
        step?: LockStep;
        cause?: unknown;
    });
    /** Retrying the whole routine is reasonable: busy or out of budget, nothing half-done. */
    get retryable(): boolean;
    toString(): string;
    static contention(key: LockKey, step: LockStep): LockError;
    static timeout(key: LockKey, step: LockStep, waitedMs: number): LockError;
    static work(key: LockKey, cause: unknown): LockError;
    static invalidPlan(key: LockKey, message: string): LockError;
    static database(key: LockKey, step: LockStep, cause: unknown): LockError;
    static transport(key: LockKey, cause: unknown, step?: LockStep): LockError;
}
/** Fill in the step on a LockError that has none; other errors pass through. */
export declare function tagStep(err: unknown, step: LockStep): unknown;
/**
 * Keep a safety-critical cleanup failure primary while retaining the guarded
 * operation's earlier failure. A failed release/unlock leaves ownership or
 * session state unknown, so callers must not see only a work error and assume
 * an immediate whole-operation retry is safe.
 */
export declare function cleanupFailure(key: LockKey, cleanup: unknown, inner: unknown): LockError;
