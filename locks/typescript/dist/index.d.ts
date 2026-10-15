/**
 * agent-pontifex lock routines. Re-exports `@oresoftware/locks-and-leases` and adds
 * the org's key prefix and lock catalog. Generated from `../catalog.json`
 * by ores-locks-and-leases' `templates/lib-core/gen_org_locks.py`.
 */
import { type LockKey, type LockLayers, type LockPlan, type PgScope } from "@oresoftware/locks-and-leases";
export * from "@oresoftware/locks-and-leases";
/** This org's key prefix. */
export declare const ORG = "agent-pontifex";
/** The lock domains this org uses. */
export type Domain = "jobs" | "migrations" | "outbox" | "tenant";
/** Build `agent-pontifex/<domain>/<name>`. */
export declare function key(domain: Domain, name: string): LockKey;
/** One catalog row: the defaults a call site should use for a named lock. */
export interface Entry {
    readonly domain: Domain;
    /** May contain `{placeholders}`; see `entryKey`. */
    readonly name: string;
    readonly layers: LockLayers;
    readonly pgScope: PgScope;
    readonly wait: boolean;
}
/** The key for `entry` with `{placeholders}` filled from `fill`, in order of appearance. */
export declare function entryKey(entry: Entry, ...fill: string[]): LockKey;
/** The plan an entry's defaults produce. */
export declare function entryPlan(entry: Entry): LockPlan;
/** The catalog, as constants. */
export declare const catalog: {
    /** One migration runner at a time. Session scope because some DDL cannot run inside a transaction; fail fast so a second runner exits instead of queueing. */
    readonly migrations_apply: {
        readonly domain: "migrations";
        readonly name: "apply";
        readonly layers: {
            readonly fiducia: true;
            readonly pgAdvisory: true;
        };
        readonly pgScope: "session";
        readonly wait: false;
    };
    /** A named job that must not overlap itself across replicas. Skip the run when it is already held. */
    readonly jobs_singleton_job: {
        readonly domain: "jobs";
        readonly name: "singleton:{job}";
        readonly layers: {
            readonly fiducia: true;
            readonly pgAdvisory: true;
        };
        readonly pgScope: "transaction";
        readonly wait: false;
    };
    /** Transactional-outbox drainer: single-database exclusion is enough, and the transaction that reads the batch is the one that holds the lock. */
    readonly outbox_drain: {
        readonly domain: "outbox";
        readonly name: "drain";
        readonly layers: {
            readonly fiducia: false;
            readonly pgAdvisory: true;
        };
        readonly pgScope: "transaction";
        readonly wait: false;
    };
    /** Serialize mutations of one tenant's aggregate across every server that can write it. Waits; contention here is normal. */
    readonly tenant_tenant_id_mutate: {
        readonly domain: "tenant";
        readonly name: "{tenant_id}/mutate";
        readonly layers: {
            readonly fiducia: true;
            readonly pgAdvisory: true;
        };
        readonly pgScope: "transaction";
        readonly wait: true;
    };
};
