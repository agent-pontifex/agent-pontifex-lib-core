/**
 * agent-pontifex lock routines. Re-exports `@oresoftware/locks-and-leases` and adds
 * the org's key prefix and lock catalog. Generated from `../catalog.json`
 * by ores-locks-and-leases' `templates/lib-core/gen_org_locks.py`.
 */
import { lockKey, plan, type LockKey, type LockLayers, type LockPlan, type PgScope } from "@oresoftware/locks-and-leases";

export * from "@oresoftware/locks-and-leases";

/** This org's key prefix. */
export const ORG = "agent-pontifex";

/** The lock domains this org uses. */
export type Domain = "jobs" | "migrations" | "outbox" | "tenant";

/** Build `agent-pontifex/<domain>/<name>`. */
export function key(domain: Domain, name: string): LockKey {
  return lockKey(`${ORG}/${domain}/${name}`);
}

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
export function entryKey(entry: Entry, ...fill: string[]): LockKey {
  let i = 0;
  return key(entry.domain, entry.name.replace(/\{[^}]*\}/g, () => fill[i++] ?? ""));
}

/** The plan an entry's defaults produce. */
export function entryPlan(entry: Entry): LockPlan {
  return plan(entry.layers, entry.pgScope, entry.wait);
}

/** The catalog, as constants. */
export const catalog = {
  /** One migration runner at a time. Session scope because some DDL cannot run inside a transaction; fail fast so a second runner exits instead of queueing. */
  migrations_apply: { domain: "migrations", name: "apply", layers: { fiducia: true, pgAdvisory: true }, pgScope: "session", wait: false },
  /** A named job that must not overlap itself across replicas. Skip the run when it is already held. */
  jobs_singleton_job: { domain: "jobs", name: "singleton:{job}", layers: { fiducia: true, pgAdvisory: true }, pgScope: "transaction", wait: false },
  /** Transactional-outbox drainer: single-database exclusion is enough, and the transaction that reads the batch is the one that holds the lock. */
  outbox_drain: { domain: "outbox", name: "drain", layers: { fiducia: false, pgAdvisory: true }, pgScope: "transaction", wait: false },
  /** Serialize mutations of one tenant's aggregate across every server that can write it. Waits; contention here is normal. */
  tenant_tenant_id_mutate: { domain: "tenant", name: "{tenant_id}/mutate", layers: { fiducia: true, pgAdvisory: true }, pgScope: "transaction", wait: true },
} as const satisfies Record<string, Entry>;
