# agent-pontifex-locks

Lock routines for **agent-pontifex**, wrapping
[`ORESoftware/ores-locks-and-leases`](https://github.com/ORESoftware/ores-locks-and-leases)
— a fiducia-cloud lease around a Postgres advisory lock, each layer
switchable, fencing tokens threaded through — with this org's key prefix and
lock catalog. One nested zed package, five runtimes:

| Path | Package |
| --- | --- |
| `rust` | `agent-pontifex-locks` crate |
| `typescript` | `@agent-pontifex/locks` |
| `dart` | `agent_pontifex_locks` |
| `gleam` | `agent_pontifex_locks` |
| `golang` | `github.com/agent-pontifex/agent-pontifex-lib-core/locks/golang` |

Every key this org locks is `agent-pontifex/<domain>/<name>`; the prefix is applied
by `key(domain, name)` in each runtime so two orgs sharing a database cannot
collide, and `advisory_key` is the shared FNV-1a derivation so every runtime
locks the same `bigint`.

## Catalog

`catalog.json` is the source; each runtime's constants are generated from it
(`gen_org_locks.py` in the shared repo's `templates/lib-core`). Add a row
there, re-run, commit the result.

| domain | name | layers | pg scope | wait | purpose |
| --- | --- | --- | --- | --- | --- |
| `migrations` | `apply` | fiducia=true pg=true | session | false | One migration runner at a time. Session scope because some DDL cannot run inside a transaction; fail fast so a second runner exits instead of queueing. |
| `jobs` | `singleton:{job}` | fiducia=true pg=true | transaction | false | A named job that must not overlap itself across replicas. Skip the run when it is already held. |
| `outbox` | `drain` | fiducia=false pg=true | transaction | false | Transactional-outbox drainer: single-database exclusion is enough, and the transaction that reads the batch is the one that holds the lock. |
| `tenant` | `{tenant_id}/mutate` | fiducia=true pg=true | transaction | true | Serialize mutations of one tenant's aggregate across every server that can write it. Waits; contention here is normal. |

The catalog is also a contract: `contracts/typespec/main.tsp` and
`contracts/json-schema/contract.schema.json` are the dual authorities checked
by `npx ores-contracts check --config contracts/contracts.config.json`.

## Resolving the shared package

`.zpkg.toml` declares the dependency; `zed install` vendors it under
`../.vendor/.zed/ORESoftware/ores-locks-and-leases`. The Rust crate pins the
shared crate by git tag and Go by module path, so they resolve without the
vendor step; TypeScript, Dart and Gleam point at the vendored slice.
