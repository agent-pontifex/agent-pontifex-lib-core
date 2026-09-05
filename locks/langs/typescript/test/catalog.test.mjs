import assert from "node:assert/strict";
import { test } from "node:test";
import { ORG, catalog, entryKey, entryPlan, key } from "../dist/index.js";

test("keys carry the org prefix", () => {
  assert.equal(key("jobs", "x"), "agent-pontifex/jobs/x");
  assert.equal(ORG, "agent-pontifex");
});

test("placeholders are filled in order and every entry plans", () => {
  assert.equal(entryKey({ domain: "jobs", name: "{a}/x/{b}", layers: { fiducia: true, pgAdvisory: true }, pgScope: "transaction", wait: true }, "1", "2"), "agent-pontifex/jobs/1/x/2");
  for (const entry of Object.values(catalog)) assert.ok(entryPlan(entry).steps.includes("work"));
});
