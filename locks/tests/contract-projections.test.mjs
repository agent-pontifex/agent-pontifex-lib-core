import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import {
  ROOT,
  assertPeerParity,
  buildArtifacts,
  parseJsonSchema,
  parseTypeSpec,
  reconcileProtoLock,
  validateCatalog,
} from "../tools/generate-contract-projections.mjs";

const read = (relative) => fs.readFileSync(path.join(ROOT, relative), "utf8");
const json = (relative) => JSON.parse(read(relative));

const typeSpecIr = parseTypeSpec(read("contracts/typespec/main.tsp"));
const jsonSchemaIr = parseJsonSchema(json("contracts/json-schema/contract.schema.json"));
const config = json("projection/config.json");
const lock = json("projection/protobuf.lock.json");
const catalog = json("catalog.json");

test("peer authorities converge and catalog validates through both lanes", () => {
  assertPeerParity(typeSpecIr, jsonSchemaIr);
  validateCatalog(typeSpecIr, catalog, config.rootModel);
  validateCatalog(jsonSchemaIr, catalog, config.rootModel);
  assert.equal(Object.keys(typeSpecIr).length, 5);
  assert.equal(catalog.entries.length, 4);
});

test("generated SQL lanes, locked Proto, and gRPC manifest are deterministic", () => {
  const first = buildArtifacts({ check: true });
  const second = buildArtifacts({ check: true });
  assert.deepEqual(first, second);
  assert.equal(
    first.files["generated/sql/from-typespec.sql"],
    first.files["generated/sql/from-json-schema.sql"],
  );
  const proto = first.files[
    "generated/protobuf/agent_pontifex/locks/v1/locks.proto"
  ];
  assert.match(proto, /message LockCatalog\s*\{/);
  assert.match(proto, /repeated LockCatalogEntry entries = 3;/);
  assert.match(proto, /service LockCatalogService\s*\{/);
  assert.match(
    proto,
    /rpc GetLockCatalog\(GetLockCatalogRequest\) returns \(LockCatalog\);/,
  );
  const grpc = JSON.parse(first.files["generated/grpc/manifest.json"]);
  assert.equal(grpc.protocol, "grpc");
  assert.equal(grpc.methods[0].readOnly, true);
  assert.equal(grpc.methods[0].clientStreaming, false);
  assert.equal(grpc.methods[0].serverStreaming, false);
});

test("a peer-authority declaration drift fails closed", () => {
  const drifted = structuredClone(jsonSchemaIr);
  drifted.LockCatalog.properties.prefix.maxLength = 65;
  assert.throws(
    () => assertPeerParity(typeSpecIr, drifted),
    /LockCatalog: TypeSpec and JSON Schema structures differ/,
  );
});

test("protobuf numbering cannot float or reuse reserved identity", () => {
  const missing = structuredClone(lock);
  delete missing.messages["agent_pontifex.locks.v1.LockCatalogEntry"].fields.wait;
  assert.throws(
    () => reconcileProtoLock(typeSpecIr, config, missing, true),
    /missing number for wait/,
  );

  const reused = structuredClone(lock);
  reused.messages["agent_pontifex.locks.v1.LockCatalogEntry"].reservedNumbers = [5];
  assert.throws(
    () => reconcileProtoLock(typeSpecIr, config, reused, true),
    /active field reuses reserved number 5/,
  );
});

test("catalog values remain closed and bounded", () => {
  const badDomain = structuredClone(catalog);
  badDomain.entries[0].domain = "global";
  assert.throws(
    () => validateCatalog(typeSpecIr, badDomain, config.rootModel),
    /invalid enum value global/,
  );

  const unknown = structuredClone(catalog);
  unknown.entries[0].credential = "must-not-enter-the-contract";
  assert.throws(
    () => validateCatalog(jsonSchemaIr, unknown, config.rootModel),
    /unknown property credential/,
  );

  const tooLong = structuredClone(catalog);
  tooLong.entries[0].name = "x".repeat(257);
  assert.throws(
    () => validateCatalog(typeSpecIr, tooLong, config.rootModel),
    /too long/,
  );
});
