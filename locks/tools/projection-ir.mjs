import assert from "node:assert/strict";

function fail(message) {
  throw new Error(message);
}

function annotationNumber(text, name) {
  const match = text.match(new RegExp(`@${name}\\((\\d+)\\)`));
  return match ? Number(match[1]) : undefined;
}

function parseType(raw) {
  const text = raw.trim();
  if (text.endsWith("[]")) return { kind: "array", items: parseType(text.slice(0, -2)) };
  if (["string", "boolean", "int32", "int64", "float32", "float64"].includes(text)) {
    return { kind: "scalar", type: text };
  }
  if (/^[A-Za-z_][A-Za-z0-9_.]*$/.test(text)) {
    return { kind: "ref", name: text.split(".").at(-1) };
  }
  fail(`unsupported TypeSpec field type: ${text}`);
}

export function parseTypeSpec(text) {
  const declarations = {};
  const enumRe = /\benum\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{([\s\S]*?)\n\}/g;
  for (const match of text.matchAll(enumRe)) {
    const values = [];
    const members = {};
    for (const member of match[2].matchAll(
      /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"((?:\\.|[^"\\])*)"\s*,?\s*$/gm,
    )) {
      const value = JSON.parse(`"${member[2]}"`);
      members[member[1]] = value;
      values.push(value);
    }
    if (values.length === 0) fail(`${match[1]}: enum has no values`);
    declarations[match[1]] = { kind: "enum", values, members };
  }

  const modelRe = /\bmodel\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{([\s\S]*?)\n\}/g;
  for (const match of text.matchAll(modelRe)) {
    const properties = {};
    const required = [];
    let annotations = "";
    for (const rawLine of match[2].split("\n")) {
      const line = rawLine.trim();
      if (!line || line.startsWith("//")) continue;
      if (line.startsWith("@")) {
        annotations += `${line}\n`;
        continue;
      }
      const field = line.match(/^([A-Za-z_][A-Za-z0-9_]*)(\?)?\s*:\s*([^;]+);\s*$/);
      if (!field) fail(`${match[1]}: cannot parse field line ${JSON.stringify(line)}`);
      const [, name, optional, typeText] = field;
      const property = parseType(typeText);
      for (const annotation of ["minLength", "maxLength"]) {
        const value = annotationNumber(annotations, annotation);
        if (value !== undefined) property[annotation] = value;
      }
      properties[name] = property;
      if (!optional) required.push(name);
      annotations = "";
    }
    if (Object.keys(properties).length === 0) fail(`${match[1]}: model has no fields`);
    declarations[match[1]] = {
      kind: "model",
      additionalProperties: false,
      properties,
      required: required.sort(),
    };
  }
  return declarations;
}

function normalizeJsonProperty(schema) {
  if (schema.$ref) return { kind: "ref", name: schema.$ref.split("/").at(-1) };
  if (schema.type === "array") {
    const out = { kind: "array", items: normalizeJsonProperty(schema.items ?? {}) };
    if (schema.minItems !== undefined) out.minItems = schema.minItems;
    if (schema.maxItems !== undefined) out.maxItems = schema.maxItems;
    return out;
  }
  const type = {
    string: "string",
    boolean: "boolean",
    integer: "int64",
    number: "float64",
  }[schema.type];
  if (!type) fail(`unsupported JSON Schema field: ${JSON.stringify(schema)}`);
  const out = { kind: "scalar", type };
  for (const key of ["minLength", "maxLength", "minimum", "maximum", "pattern", "format"]) {
    if (schema[key] !== undefined) out[key] = schema[key];
  }
  return out;
}

export function parseJsonSchema(document) {
  assert.equal(
    document.$schema,
    "https://json-schema.org/draft/2020-12/schema",
    "JSON Schema authority must remain Draft 2020-12",
  );
  const declarations = {};
  for (const [name, schema] of Object.entries(document.$defs ?? {})) {
    if (schema.type === "string" && Array.isArray(schema.enum)) {
      declarations[name] = {
        kind: "enum",
        values: [...schema.enum],
        members: Object.fromEntries(schema.enum.map((value) => [value, value])),
      };
      continue;
    }
    if (schema.type !== "object") fail(`${name}: expected object or enum`);
    declarations[name] = {
      kind: "model",
      additionalProperties: schema.additionalProperties,
      properties: Object.fromEntries(
        Object.entries(schema.properties ?? {}).map(([key, value]) => [key, normalizeJsonProperty(value)]),
      ),
      required: [...(schema.required ?? [])].sort(),
    };
  }
  return declarations;
}

function comparableProperty(property) {
  const out = { kind: property.kind };
  if (property.type !== undefined) out.type = property.type === "int32" ? "int64" : property.type;
  if (property.name !== undefined) out.name = property.name;
  if (property.items !== undefined) out.items = comparableProperty(property.items);
  for (const key of [
    "minLength", "maxLength", "minItems", "maxItems", "minimum", "maximum", "pattern", "format",
  ]) {
    if (property[key] !== undefined) out[key] = property[key];
  }
  return out;
}

function comparableDeclaration(declaration) {
  if (declaration.kind === "enum") return { kind: "enum", values: [...declaration.values] };
  return {
    kind: "model",
    additionalProperties: declaration.additionalProperties,
    required: [...declaration.required].sort(),
    properties: Object.fromEntries(
      Object.keys(declaration.properties).sort().map((name) => [name, comparableProperty(declaration.properties[name])]),
    ),
  };
}

export function assertPeerParity(typespec, jsonSchema) {
  assert.deepEqual(
    Object.keys(typespec).sort(),
    Object.keys(jsonSchema).sort(),
    "TypeSpec and JSON Schema declaration inventories differ",
  );
  for (const name of Object.keys(typespec).sort()) {
    assert.deepEqual(
      comparableDeclaration(typespec[name]),
      comparableDeclaration(jsonSchema[name]),
      `${name}: TypeSpec and JSON Schema structures differ`,
    );
  }
}

export function resolveProperty(ir, property) {
  return property.kind === "ref" ? ir[property.name] : property;
}

function validateValue(ir, property, value, label) {
  if (property.kind === "ref") return validateDeclaration(ir, ir[property.name], value, label);
  if (property.kind === "array") {
    if (!Array.isArray(value)) fail(`${label}: expected array`);
    if (property.minItems !== undefined && value.length < property.minItems) fail(`${label}: too few items`);
    if (property.maxItems !== undefined && value.length > property.maxItems) fail(`${label}: too many items`);
    value.forEach((item, index) => validateValue(ir, property.items, item, `${label}[${index}]`));
    return;
  }
  switch (property.type) {
    case "string":
      if (typeof value !== "string") fail(`${label}: expected string`);
      if (property.minLength !== undefined && [...value].length < property.minLength) fail(`${label}: too short`);
      if (property.maxLength !== undefined && [...value].length > property.maxLength) fail(`${label}: too long`);
      if (property.pattern !== undefined && !new RegExp(property.pattern, "u").test(value)) fail(`${label}: pattern mismatch`);
      return;
    case "boolean":
      if (typeof value !== "boolean") fail(`${label}: expected boolean`);
      return;
    case "int32":
    case "int64":
      if (!Number.isInteger(value)) fail(`${label}: expected integer`);
      return;
    case "float32":
    case "float64":
      if (typeof value !== "number" || !Number.isFinite(value)) fail(`${label}: expected number`);
      return;
    default:
      fail(`${label}: unsupported scalar ${property.type}`);
  }
}

function validateDeclaration(ir, declaration, value, label) {
  if (!declaration) fail(`${label}: unresolved declaration`);
  if (declaration.kind === "enum") {
    if (!declaration.values.includes(value)) fail(`${label}: invalid enum value ${value}`);
    return;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label}: expected object`);
  for (const name of declaration.required) {
    if (!Object.hasOwn(value, name)) fail(`${label}: missing ${name}`);
  }
  if (declaration.additionalProperties === false) {
    for (const name of Object.keys(value)) {
      if (!Object.hasOwn(declaration.properties, name)) fail(`${label}: unknown property ${name}`);
    }
  }
  for (const [name, property] of Object.entries(declaration.properties)) {
    if (Object.hasOwn(value, name)) validateValue(ir, property, value[name], `${label}.${name}`);
  }
}

export function validateCatalog(ir, catalog, rootModel) {
  const instance = { ...catalog };
  delete instance.$comment;
  validateDeclaration(ir, ir[rootModel], instance, rootModel);
}

export function scream(value) {
  return value.replace(/([a-z0-9])([A-Z])/g, "$1_$2").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_+|_+$/g, "").toUpperCase();
}

export function snake(value) {
  return value.replace(/([a-z0-9])([A-Z])/g, "$1_$2").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_+|_+$/g, "").toLowerCase();
}

export function protoType(property) {
  if (property.kind === "ref") return property.name;
  if (property.kind === "array") return protoType(property.items);
  return {
    string: "string", boolean: "bool", int32: "int32", int64: "int64", float32: "float", float64: "double",
  }[property.type] ?? fail(`no Proto type for ${JSON.stringify(property)}`);
}

function nextNumber(used) {
  let number = 1;
  while (used.has(number) || (number >= 19000 && number <= 19999)) number += 1;
  return number;
}

function reconcileNumberedSet(currentNames, record, check, label) {
  const fields = { ...(record.fields ?? record.values ?? {}) };
  const reservedNames = new Set(record.reservedNames ?? []);
  const reservedNumbers = new Set(record.reservedNumbers ?? []);
  const used = new Set([...Object.values(fields), ...reservedNumbers]);
  for (const existingName of Object.keys(fields)) {
    if (!currentNames.includes(existingName)) {
      if (check) fail(`${label}: removed ${existingName} must be moved to reserved entries`);
      reservedNames.add(existingName);
      reservedNumbers.add(fields[existingName]);
      delete fields[existingName];
    }
  }
  for (const name of currentNames) {
    if (reservedNames.has(name)) fail(`${label}: ${name} reuses a reserved name`);
    if (!Object.hasOwn(fields, name)) {
      if (check) fail(`${label}: missing number for ${name}`);
      const number = nextNumber(used);
      fields[name] = number;
      used.add(number);
    }
  }
  const numbers = Object.values(fields);
  assert.equal(new Set(numbers).size, numbers.length, `${label}: duplicate active numbers`);
  for (const number of numbers) {
    if (reservedNumbers.has(number)) fail(`${label}: active field reuses reserved number ${number}`);
  }
  return {
    fields,
    reservedNames: [...reservedNames].sort(),
    reservedNumbers: [...reservedNumbers].sort((a, b) => a - b),
  };
}

export function reconcileProtoLock(ir, config, lock, check) {
  const next = structuredClone(lock);
  next.formatVersion = 1;
  next.messages ??= {};
  next.enums ??= {};
  for (const [name, declaration] of Object.entries(ir)) {
    const fq = `${config.protoPackage}.${name}`;
    if (declaration.kind === "model") {
      next.messages[fq] = reconcileNumberedSet(
        Object.keys(declaration.properties),
        next.messages[fq] ?? { fields: {}, reservedNames: [], reservedNumbers: [] },
        check,
        fq,
      );
      continue;
    }
    const prefix = scream(name);
    const expectedNames = [`${prefix}_UNSPECIFIED`, ...declaration.values.map((value) => `${prefix}_${scream(value)}`)];
    const record = next.enums[fq] ?? { values: {}, reservedNames: [], reservedNumbers: [] };
    const normalized = reconcileNumberedSet(
      expectedNames,
      { fields: record.values, reservedNames: record.reservedNames, reservedNumbers: record.reservedNumbers },
      check,
      fq,
    );
    next.enums[fq] = {
      values: normalized.fields,
      reservedNames: normalized.reservedNames,
      reservedNumbers: normalized.reservedNumbers,
    };
    assert.equal(next.enums[fq].values[`${prefix}_UNSPECIFIED`], 0, `${fq}: UNSPECIFIED must remain 0`);
  }
  const requestFq = `${config.protoPackage}.${config.service.request}`;
  next.messages[requestFq] ??= { fields: {}, reservedNames: [], reservedNumbers: [] };
  return next;
}
