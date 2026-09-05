//// agent-pontifex lock routines: `ores_locks_and_leases` with the org's key prefix
//// and lock catalog. Generated from `../../catalog.json` by
//// ores-locks-and-leases' `templates/lib-core/gen_org_locks.py`.

import gleam/list
import gleam/string
import ores_locks_and_leases as locks

/// This org's key prefix.
pub const org = "agent-pontifex"

/// The lock domains this org uses.
pub type Domain {
  Jobs
  Migrations
  Outbox
  Tenant
}

pub fn domain_to_string(domain: Domain) -> String {
  case domain {
    Jobs -> "jobs"
    Migrations -> "migrations"
    Outbox -> "outbox"
    Tenant -> "tenant"
  }
}

/// Build `agent-pontifex/<domain>/<name>`.
pub fn key(domain: Domain, name: String) -> Result(locks.LockKey, String) {
  locks.lock_key(org <> "/" <> domain_to_string(domain) <> "/" <> name)
}

/// One catalog row: the defaults a call site should use for a named lock.
pub type Entry {
  Entry(
    domain: Domain,
    /// May contain `{placeholders}`; see `entry_key`.
    name: String,
    layers: locks.Layers,
    pg_scope: locks.PgScope,
    wait: Bool,
  )
}

/// The key for `entry` with `{placeholders}` filled from `fill`, in order.
pub fn entry_key(
  entry: Entry,
  fill: List(String),
) -> Result(locks.LockKey, String) {
  key(entry.domain, fill_placeholders(entry.name, fill))
}

fn fill_placeholders(name: String, fill: List(String)) -> String {
  case string.split_once(name, "{") {
    Error(Nil) -> name
    Ok(#(before, rest)) -> {
      let after = case string.split_once(rest, "}") {
        Ok(#(_, after)) -> after
        Error(Nil) -> ""
      }
      let #(value, remaining) = case fill {
        [first, ..remaining] -> #(first, remaining)
        [] -> #("", [])
      }
      before <> value <> fill_placeholders(after, remaining)
    }
  }
}

/// The plan an entry's defaults produce.
pub fn entry_plan(entry: Entry) -> locks.Plan {
  locks.plan(entry.layers, entry.pg_scope, entry.wait)
}

/// One migration runner at a time. Session scope because some DDL cannot run inside a transaction; fail fast so a second runner exits instead of queueing.
pub const migrations_apply = Entry(
  domain: Migrations,
  name: "apply",
  layers: locks.Layers(fiducia: True, pg_advisory: True),
  pg_scope: locks.Session,
  wait: False,
)

/// A named job that must not overlap itself across replicas. Skip the run when it is already held.
pub const jobs_singleton_job = Entry(
  domain: Jobs,
  name: "singleton:{job}",
  layers: locks.Layers(fiducia: True, pg_advisory: True),
  pg_scope: locks.Transaction,
  wait: False,
)

/// Transactional-outbox drainer: single-database exclusion is enough, and the transaction that reads the batch is the one that holds the lock.
pub const outbox_drain = Entry(
  domain: Outbox,
  name: "drain",
  layers: locks.Layers(fiducia: False, pg_advisory: True),
  pg_scope: locks.Transaction,
  wait: False,
)

/// Serialize mutations of one tenant's aggregate across every server that can write it. Waits; contention here is normal.
pub const tenant_tenant_id_mutate = Entry(
  domain: Tenant,
  name: "{tenant_id}/mutate",
  layers: locks.Layers(fiducia: True, pg_advisory: True),
  pg_scope: locks.Transaction,
  wait: True,
)

/// Every catalog entry.
pub fn catalog() -> List(Entry) {
  [migrations_apply, jobs_singleton_job, outbox_drain, tenant_tenant_id_mutate]
}

/// Every catalog entry plans to something that runs `work` exactly once.
pub fn catalog_is_well_formed() -> Bool {
  list.all(catalog(), fn(entry) {
    list.filter(entry_plan(entry).steps, fn(step) { step == locks.Work })
    |> list.length
    == 1
  })
}
