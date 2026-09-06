/** The one structured failure every routine surfaces. The contract's `LockError`. */
export class LockError extends Error {
    kind;
    key;
    /** Which step failed, when known. */
    step;
    constructor(kind, key, message, options) {
        super(message, options?.cause === undefined ? undefined : { cause: options.cause });
        this.name = "LockError";
        this.kind = kind;
        this.key = key;
        this.step = options?.step;
    }
    /** Retrying the whole routine is reasonable: busy or out of budget, nothing half-done. */
    get retryable() {
        return this.kind === "contention" || this.kind === "timeout";
    }
    toString() {
        return this.step
            ? `${this.kind} at ${this.step} for \`${this.key}\`: ${this.message}`
            : `${this.kind} for \`${this.key}\`: ${this.message}`;
    }
    static contention(key, step) {
        return new LockError("contention", key, `\`${key}\` is held by another holder`, { step });
    }
    static timeout(key, step, waitedMs) {
        return new LockError("timeout", key, `gave up waiting for \`${key}\` after ${Math.round(waitedMs)} ms`, { step });
    }
    static work(key, cause) {
        const message = cause instanceof Error ? cause.message : String(cause);
        return new LockError("work", key, message, { step: "work", cause });
    }
    static invalidPlan(key, message) {
        return new LockError("invalid_plan", key, message);
    }
    static database(key, step, cause) {
        const message = cause instanceof Error ? cause.message : String(cause);
        return new LockError("database", key, message, { step, cause });
    }
    static transport(key, cause, step) {
        const message = cause instanceof Error ? cause.message : String(cause);
        return new LockError("transport", key, message, step === undefined ? { cause } : { step, cause });
    }
}
/** Fill in the step on a LockError that has none; other errors pass through. */
export function tagStep(err, step) {
    if (err instanceof LockError && err.step === undefined)
        err.step = step;
    return err;
}
/**
 * Keep a safety-critical cleanup failure primary while retaining the guarded
 * operation's earlier failure. A failed release/unlock leaves ownership or
 * session state unknown, so callers must not see only a work error and assume
 * an immediate whole-operation retry is safe.
 */
export function cleanupFailure(key, cleanup, inner) {
    const normalized = cleanup instanceof LockError ? cleanup : LockError.transport(key, cleanup);
    const innerMessage = inner instanceof Error ? inner.toString() : String(inner);
    return new LockError(normalized.kind, normalized.key, `${normalized.message}; guarded operation also failed: ${innerMessage}`, normalized.step === undefined
        ? { cause: { cleanup, inner } }
        : { step: normalized.step, cause: { cleanup, inner } });
}
