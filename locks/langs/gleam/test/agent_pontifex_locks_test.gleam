import agent_pontifex_locks as org_locks
import gleeunit
import gleeunit/should
import ores_locks_and_leases as locks

pub fn main() {
  gleeunit.main()
}

pub fn keys_carry_the_org_prefix_test() {
  let assert Ok(key) = org_locks.key(org_locks.Jobs, "x")
  locks.key_to_string(key) |> should.equal("agent-pontifex/jobs/x")
}

pub fn placeholders_are_filled_in_order_test() {
  let entry =
    org_locks.Entry(
      domain: org_locks.Jobs,
      name: "{a}/x/{b}",
      layers: locks.layers_both,
      pg_scope: locks.Transaction,
      wait: True,
    )
  let assert Ok(key) = org_locks.entry_key(entry, ["1", "2"])
  locks.key_to_string(key) |> should.equal("agent-pontifex/jobs/1/x/2")
  org_locks.catalog_is_well_formed() |> should.be_true
}
