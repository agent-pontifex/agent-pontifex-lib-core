package agent_pontifexlocks

import (
	"testing"

	oreslocks "github.com/ORESoftware/ores-locks-and-leases/src/go"
)

func TestKeysCarryTheOrgPrefix(t *testing.T) {
	k, err := Key(DomainJobs, "x")
	if err != nil || string(k) != "agent-pontifex/jobs/x" {
		t.Fatalf("%q %v", k, err)
	}
}

func TestPlaceholdersAreFilledInOrder(t *testing.T) {
	e := Entry{Domain: DomainJobs, Name: "{a}/x/{b}", Layers: oreslocks.LayersBoth, PgScope: oreslocks.ScopeTransaction, Wait: true}
	k, err := e.Key("1", "2")
	if err != nil || string(k) != "agent-pontifex/jobs/1/x/2" {
		t.Fatalf("%q %v", k, err)
	}
	if e.Plan().Steps[0] != oreslocks.StepFiduciaAcquire {
		t.Fatal("fiducia must be outermost")
	}
}
