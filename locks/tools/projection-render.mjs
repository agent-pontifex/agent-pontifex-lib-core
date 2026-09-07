import assert from "node:assert/strict";
import { protoType, resolveProperty, scream, snake } from "./projection-ir.mjs";

function renderReserved(record) {
  const lines = [];
  if (record.reservedNumbers?.length) lines.push(`  reserved ${record.reservedNumbers.join(", ")};`);
  if (record.reservedNames?.length) {
    lines.push(`  reserved ${record.reservedNames.map((name) => JSON.stringify(name)).join(", ")};`);
  }
  return lines;
}

export function renderProto(ir, config, lock, banner) {
  const lines = [
    `// ${banner}`,
    "// TypeSpec-lane binary projection. JSON Schema remains an independent peer authority.",
    "",
    'syntax = "proto3";',
    "",
    `package ${config.protoPackage};`,
    "",
  ];
  for (const [name, declaration] of Object.entries(ir)) {
    const fq = `${config.protoPackage}.${name}`;
    if (declaration.kind === "enum") {
      const record = lock.enums[fq];
      const prefix = scream(name);
      lines.push(`enum ${name} {`, ...renderReserved(record));
      lines.push(`  ${prefix}_UNSPECIFIED = ${record.values[`${prefix}_UNSPECIFIED`]};`);
      for (const value of declaration.values) {
        const symbol = `${prefix}_${scream(value)}`;
        lines.push(`  ${symbol} = ${record.values[symbol]};`);
      }
      lines.push("}", "");
      continue;
    }
    const record = lock.messages[fq];
    lines.push(`message ${name} {`, ...renderReserved(record));
    for (const [fieldName, property] of Object.entries(declaration.properties)) {
      const repeated = property.kind === "array" ? "repeated " : "";
      const wireName = snake(fieldName);
      const jsonName = wireName === fieldName ? "" : ` [json_name = ${JSON.stringify(fieldName)}]`;
      lines.push(`  ${repeated}${protoType(property)} ${wireName} = ${record.fields[fieldName]}${jsonName};`);
    }
    lines.push("}", "");
  }
  lines.push(`message ${config.service.request} {}`, "");
  lines.push(`service ${config.service.name} {`);
  lines.push(`  rpc ${config.service.method}(${config.service.request}) returns (${config.service.response});`);
  lines.push("}", "");
  return lines.join("\n");
}

function sqlEnumValues(ir, name) {
  const declaration = ir[name];
  assert.equal(declaration?.kind, "enum", `${name}: expected enum`);
  return declaration.values.map((value) => `'${value.replaceAll("'", "''")}'`).join(", ");
}

export function renderSql(ir, config, banner) {
  const root = ir[config.rootModel];
  const entry = ir[config.entryModel];
  assert.equal(root?.kind, "model", `${config.rootModel}: expected model`);
  assert.equal(entry?.kind, "model", `${config.entryModel}: expected model`);
  assert.equal(root.properties.entries?.kind, "array", "LockCatalog.entries must be an array");
  assert.equal(root.properties.entries.items?.name, config.entryModel, "entries item type drift");
  assert.equal(resolveProperty(ir, entry.properties.layers)?.kind, "model", "LockCatalogEntry.layers must remain a model");
  const schema = config.sqlSchema;
  const lines = [
    `-- ${banner}`,
    "-- Persistence projection only; apply through a reviewed serialized migrator.",
    `CREATE SCHEMA IF NOT EXISTS ${schema};`,
    "",
    `CREATE TABLE ${schema}.lock_catalogs (`,
    `  org text PRIMARY KEY CHECK (char_length(org) BETWEEN 1 AND ${root.properties.org.maxLength}),`,
    `  prefix text NOT NULL UNIQUE CHECK (char_length(prefix) BETWEEN 1 AND ${root.properties.prefix.maxLength})`,
    ");",
    "",
    `CREATE TABLE ${schema}.lock_catalog_entries (`,
    `  org text NOT NULL REFERENCES ${schema}.lock_catalogs(org) ON DELETE CASCADE,`,
    "  ordinal integer NOT NULL CHECK (ordinal >= 0),",
    `  domain text NOT NULL CHECK (domain IN (${sqlEnumValues(ir, "LockDomain")})),`,
    `  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND ${entry.properties.name.maxLength}),`,
    "  fiducia boolean NOT NULL,",
    "  pg_advisory boolean NOT NULL,",
    `  pg_scope text NOT NULL CHECK (pg_scope IN (${sqlEnumValues(ir, "PgScope")})),`,
    "  wait boolean NOT NULL,",
    "  description text NOT NULL CHECK (char_length(description) >= 1),",
    "  PRIMARY KEY (org, ordinal),",
    "  UNIQUE (org, domain, name)",
    ");",
    "",
    `CREATE INDEX lock_catalog_entries_lookup_idx ON ${schema}.lock_catalog_entries (domain, name);`,
    `ALTER TABLE ${schema}.lock_catalogs ENABLE ROW LEVEL SECURITY;`,
    `ALTER TABLE ${schema}.lock_catalogs FORCE ROW LEVEL SECURITY;`,
    `ALTER TABLE ${schema}.lock_catalog_entries ENABLE ROW LEVEL SECURITY;`,
    `ALTER TABLE ${schema}.lock_catalog_entries FORCE ROW LEVEL SECURITY;`,
    `REVOKE ALL ON SCHEMA ${schema} FROM PUBLIC;`,
    `REVOKE ALL ON ALL TABLES IN SCHEMA ${schema} FROM PUBLIC;`,
    "",
  ];
  return lines.join("\n");
}

export function renderSeed(catalog, config, banner) {
  const schema = config.sqlSchema;
  const quote = (value) => `'${String(value).replaceAll("'", "''")}'`;
  return [
    `-- ${banner}`,
    "-- Deterministic seed for disposable/shadow databases; production apply remains migrator-owned.",
    `INSERT INTO ${schema}.lock_catalogs (org, prefix)`,
    `VALUES (${quote(catalog.org)}, ${quote(catalog.prefix)})`,
    "ON CONFLICT (org) DO UPDATE SET prefix = EXCLUDED.prefix;",
    "",
    `DELETE FROM ${schema}.lock_catalog_entries WHERE org = ${quote(catalog.org)};`,
    `INSERT INTO ${schema}.lock_catalog_entries`,
    "  (org, ordinal, domain, name, fiducia, pg_advisory, pg_scope, wait, description)",
    "VALUES",
    ...catalog.entries.map((entry, index) => {
      const suffix = index === catalog.entries.length - 1 ? ";" : ",";
      return `  (${quote(catalog.org)}, ${index}, ${quote(entry.domain)}, ${quote(entry.name)}, ${entry.layers.fiducia}, ${entry.layers.pgAdvisory}, ${quote(entry.pgScope)}, ${entry.wait}, ${quote(entry.description)})${suffix}`;
    }),
    "",
  ].join("\n");
}

export function renderGrpcManifest(config, protoDigest, canonical) {
  return canonical({
    formatVersion: 1,
    protocol: "grpc",
    protoPackage: config.protoPackage,
    service: config.service.name,
    methods: [{
      name: config.service.method,
      request: config.service.request,
      response: config.service.response,
      clientStreaming: false,
      serverStreaming: false,
      readOnly: config.service.readOnly === true,
    }],
    protoSha256: protoDigest,
    authorization: "server-policy-required",
    persistence: "serialized-migrator-only",
  });
}

export function renderReadme(banner) {
  return `# Generated lock-contract projections\n\n<!-- generated-policy: frozen -->\n\n${banner}.\n\n- \`sql/from-typespec.sql\` and \`sql/from-json-schema.sql\` are independent lanes and must remain byte-identical after normalization.\n- \`sql/catalog-seed.sql\` is for disposable and shadow databases; production changes still require the serialized migrator.\n- \`protobuf/agent_pontifex/locks/v1/locks.proto\` carries locked field/enum numbers and the read-only gRPC catalog service.\n- \`grpc/manifest.json\` binds service metadata to the exact Proto digest.\n- \`manifest.json\` records source and output digests.\n\nEdit the human-authored files under \`contracts/typespec\`, \`contracts/json-schema\`, \`catalog.json\`, or the reviewed projection metadata, then regenerate.\n`;
}
