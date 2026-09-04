// agent-pontifex lock catalog — TypeSpec authority. Peer of
// ../json-schema/contract.schema.json (ORESoftware/ores-contracts); neither is
// generated from the other. The lock vocabulary itself (LockLayers, PgScope,
// LockStep, LockErrorKind) is owned by ORESoftware/ores-locks-and-leases.

@doc("agent-pontifex lock catalog: the named locks this org takes, with their default layers and scope.")
namespace AgentPontifex.Locks;

@doc("The lock domains this org uses; a key is `agent-pontifex/<domain>/<name>`.")
enum LockDomain {
  jobs: "jobs",
  migrations: "migrations",
  outbox: "outbox",
  tenant: "tenant",
}

@doc("Whether the fiducia lease and/or the Postgres advisory lock are engaged for an entry.")
model LockLayers {
  fiducia: boolean;
  pgAdvisory: boolean;
}

@doc("Postgres advisory-lock scope: inside a transaction the routine commits, or on one dedicated session with no transaction.")
enum PgScope {
  transaction: "transaction",
  session: "session",
}

@doc("One catalog row. `name` may contain {placeholders} callers fill in.")
model LockCatalogEntry {
  domain: LockDomain;
  @maxLength(256)
  name: string;
  layers: LockLayers;
  pgScope: PgScope;
  @doc("true: block up to the wait budget; false: fail fast with `contention`.")
  wait: boolean;
  description: string;
}

@doc("The catalog: `locks/catalog.json` conforms to this.")
model LockCatalog {
  @maxLength(64)
  org: string;
  @maxLength(64)
  prefix: string;
  entries: LockCatalogEntry[];
}
