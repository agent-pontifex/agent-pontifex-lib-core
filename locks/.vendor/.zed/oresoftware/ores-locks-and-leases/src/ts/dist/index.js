/**
 * @oresoftware/locks-and-leases — composed distributed locking for the
 * ORESoftware fleet: a fiducia-cloud lease around a Postgres advisory lock,
 * each layer individually switchable, with fencing tokens threaded through
 * to the guarded work.
 *
 * ```text
 * fiducia.acquire ─► pg.begin ─► pg.advisory_xact_lock ─► work ─► pg.commit ─► fiducia.release
 * ```
 *
 * The TypeScript slice of ORESoftware/ores-locks-and-leases; held to the same
 * `conformance/cases/*.json` as the Rust, Go, Dart and Gleam slices.
 */
export { MAX_LOCK_KEY_BYTES, advisoryKey, fnv1a64, lockKey } from "./key.js";
export { ALL_STEPS, LAYERS_BOTH, LAYERS_FIDUCIA_ONLY, LAYERS_NONE, LAYERS_PG_ONLY, plan, } from "./plan.js";
export { LockError } from "./errors.js";
export { DEFAULT_ACQUIRE_OPTIONS, withLease, } from "./lease.js";
export { withSessionLock, withXactLock, } from "./pg.js";
export { FiduciaLease, cleartextRefusal, generatedHolder } from "./fiducia.js";
