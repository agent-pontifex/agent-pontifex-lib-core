// Package agent_pontifexlocks wraps ORESoftware/ores-locks-and-leases with the agent-pontifex
// key prefix and lock catalog. Generated from ../catalog.json by
// ores-locks-and-leases' templates/lib-core/gen_org_locks.py.
package agent_pontifexlocks

import (
	"regexp"

	oreslocks "github.com/ORESoftware/ores-locks-and-leases/src/go"
)

// Org is this org's key prefix.
const Org = "agent-pontifex"

// Domain is one of the lock domains this org uses.
type Domain string

const (
	DomainJobs       Domain = "jobs"
	DomainMigrations Domain = "migrations"
	DomainOutbox     Domain = "outbox"
	DomainTenant     Domain = "tenant"
)

// Key builds agent-pontifex/<domain>/<name>.
func Key(domain Domain, name string) (oreslocks.LockKey, error) {
	return oreslocks.NewLockKey(Org + "/" + string(domain) + "/" + name)
}

// Entry is one catalog row: the defaults a call site should use for a named lock.
type Entry struct {
	Domain Domain
	// Name may contain {placeholders}; see Entry.Key.
	Name    string
	Layers  oreslocks.Layers
	PgScope oreslocks.PgScope
	Wait    bool
}

var placeholder = regexp.MustCompile(`\{[^}]*\}`)

// Key returns the entry's key with {placeholders} filled from fill, in order.
func (e Entry) Key(fill ...string) (oreslocks.LockKey, error) {
	i := 0
	name := placeholder.ReplaceAllStringFunc(e.Name, func(string) string {
		if i < len(fill) {
			v := fill[i]
			i++
			return v
		}
		return ""
	})
	return Key(e.Domain, name)
}

// Plan is the plan the entry's defaults produce.
func (e Entry) Plan() oreslocks.Plan { return oreslocks.MakePlan(e.Layers, e.PgScope, e.Wait) }

// The catalog, as constants.
var (
	// One migration runner at a time. Session scope because some DDL cannot run inside a transaction; fail fast so a second runner exits instead of queueing.
	MigrationsApply = Entry{Domain: DomainMigrations, Name: "apply", Layers: oreslocks.Layers{Fiducia: true, PgAdvisory: true}, PgScope: oreslocks.ScopeSession, Wait: false}
	// A named job that must not overlap itself across replicas. Skip the run when it is already held.
	JobsSingletonJob = Entry{Domain: DomainJobs, Name: "singleton:{job}", Layers: oreslocks.Layers{Fiducia: true, PgAdvisory: true}, PgScope: oreslocks.ScopeTransaction, Wait: false}
	// Transactional-outbox drainer: single-database exclusion is enough, and the transaction that reads the batch is the one that holds the lock.
	OutboxDrain = Entry{Domain: DomainOutbox, Name: "drain", Layers: oreslocks.Layers{Fiducia: false, PgAdvisory: true}, PgScope: oreslocks.ScopeTransaction, Wait: false}
	// Serialize mutations of one tenant's aggregate across every server that can write it. Waits; contention here is normal.
	TenantTenantIdMutate = Entry{Domain: DomainTenant, Name: "{tenant_id}/mutate", Layers: oreslocks.Layers{Fiducia: true, PgAdvisory: true}, PgScope: oreslocks.ScopeTransaction, Wait: true}
)
