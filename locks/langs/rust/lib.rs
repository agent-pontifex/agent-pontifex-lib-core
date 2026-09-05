//! agent-pontifex lock routines.
//!
//! Re-exports [`ores_locks_and_leases`] and adds the org's key prefix and lock
//! catalog. Every key this crate builds is `agent-pontifex/<domain>/<name>`.
//! Generated from `../../catalog.json` by ores-locks-and-leases'
//! `templates/lib-core/gen_org_locks.py`; edit the catalog, not this file.

pub use ores_locks_and_leases::*;

/// This org's key prefix.
pub const ORG: &str = "agent-pontifex";

/// The lock domains this org uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Domain {
    Jobs,
    Migrations,
    Outbox,
    Tenant,
}

impl Domain {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Jobs => "jobs",
            Self::Migrations => "migrations",
            Self::Outbox => "outbox",
            Self::Tenant => "tenant",
        }
    }
}

/// Build `agent-pontifex/<domain>/<name>`.
pub fn key(domain: Domain, name: &str) -> Result<LockKey, key::InvalidLockKey> {
    LockKey::new(format!("{ORG}/{}/{name}", domain.as_str()))
}

/// One catalog row: the defaults a call site should use for a named lock.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Entry {
    pub domain: Domain,
    /// May contain `{placeholders}`; see [`Entry::key`].
    pub name: &'static str,
    pub layers: LockLayers,
    pub pg_scope: PgScope,
    pub wait: bool,
}

impl Entry {
    /// The key for this entry with `{placeholders}` filled from `fill`, in
    /// order of appearance.
    pub fn key(&self, fill: &[&str]) -> Result<LockKey, key::InvalidLockKey> {
        let mut name = String::new();
        let mut rest = self.name;
        let mut fills = fill.iter();
        while let Some(open) = rest.find('{') {
            name.push_str(&rest[..open]);
            let after = &rest[open..];
            let close = after.find('}').map(|i| i + 1).unwrap_or(after.len());
            name.push_str(fills.next().copied().unwrap_or(""));
            rest = &after[close..];
        }
        name.push_str(rest);
        key(self.domain, &name)
    }

    /// The plan this entry's defaults produce.
    pub fn plan(&self) -> LockPlan {
        plan(self.layers, self.pg_scope, self.wait)
    }
}

/// The catalog, as constants.
pub mod catalog {
    use super::*;

    /// One migration runner at a time. Session scope because some DDL cannot run inside a transaction; fail fast so a second runner exits instead of queueing.
    pub const MIGRATIONS_APPLY: Entry = Entry {
        domain: Domain::Migrations,
        name: "apply",
        layers: LockLayers { fiducia: true, pg_advisory: true },
        pg_scope: PgScope::Session,
        wait: false,
    };
    /// A named job that must not overlap itself across replicas. Skip the run when it is already held.
    pub const JOBS_SINGLETON_JOB: Entry = Entry {
        domain: Domain::Jobs,
        name: "singleton:{job}",
        layers: LockLayers { fiducia: true, pg_advisory: true },
        pg_scope: PgScope::Transaction,
        wait: false,
    };
    /// Transactional-outbox drainer: single-database exclusion is enough, and the transaction that reads the batch is the one that holds the lock.
    pub const OUTBOX_DRAIN: Entry = Entry {
        domain: Domain::Outbox,
        name: "drain",
        layers: LockLayers { fiducia: false, pg_advisory: true },
        pg_scope: PgScope::Transaction,
        wait: false,
    };
    /// Serialize mutations of one tenant's aggregate across every server that can write it. Waits; contention here is normal.
    pub const TENANT_TENANT_ID_MUTATE: Entry = Entry {
        domain: Domain::Tenant,
        name: "{tenant_id}/mutate",
        layers: LockLayers { fiducia: true, pg_advisory: true },
        pg_scope: PgScope::Transaction,
        wait: true,
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_carry_the_org_prefix() {
        let k = key(Domain::Jobs, "x").unwrap();
        assert!(k.as_str().starts_with("agent-pontifex/jobs/"));
    }

    #[test]
    fn placeholders_are_filled_in_order() {
        let entry = Entry {
            domain: Domain::Jobs,
            name: "{a}/x/{b}",
            layers: LockLayers::BOTH,
            pg_scope: PgScope::Transaction,
            wait: true,
        };
        assert_eq!(entry.key(&["1", "2"]).unwrap().as_str(), "agent-pontifex/jobs/1/x/2");
        assert_eq!(entry.plan().steps.first(), Some(&LockStep::FiduciaAcquire));
    }
}
