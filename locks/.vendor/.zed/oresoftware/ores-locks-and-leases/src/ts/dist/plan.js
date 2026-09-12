/**
 * The lock plan: which layers, in which order, as data. Every runtime derives
 * its behavior from the same pure function; the matrix lives in
 * `conformance/cases/lock-plan.json`.
 */
export const LAYERS_NONE = { fiducia: false, pgAdvisory: false };
export const LAYERS_FIDUCIA_ONLY = { fiducia: true, pgAdvisory: false };
export const LAYERS_PG_ONLY = { fiducia: false, pgAdvisory: true };
export const LAYERS_BOTH = { fiducia: true, pgAdvisory: true };
export const ALL_STEPS = [
    "fiducia.acquire",
    "fiducia.try_acquire",
    "fiducia.release",
    "pg.begin",
    "pg.advisory_xact_lock",
    "pg.try_advisory_xact_lock",
    "pg.commit",
    "pg.rollback",
    "pg.advisory_lock",
    "pg.try_advisory_lock",
    "pg.advisory_unlock",
    "work",
];
/**
 * Compute the plan. Pure; identical across every language slice. `wait`
 * blocks each layer up to its budget; `!wait` uses the non-blocking form of
 * each acquisition and fails fast with `contention`.
 */
export function plan(layers, pgScope, wait) {
    const steps = [];
    if (layers.fiducia)
        steps.push(wait ? "fiducia.acquire" : "fiducia.try_acquire");
    if (!layers.pgAdvisory) {
        steps.push("work");
    }
    else if (pgScope === "session") {
        steps.push(wait ? "pg.advisory_lock" : "pg.try_advisory_lock", "work", "pg.advisory_unlock");
    }
    else {
        steps.push("pg.begin", wait ? "pg.advisory_xact_lock" : "pg.try_advisory_xact_lock", "work", "pg.commit");
    }
    if (layers.fiducia)
        steps.push("fiducia.release");
    return { layers, pgScope, wait, steps };
}
