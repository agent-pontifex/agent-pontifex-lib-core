/**
 * Lock identities and the advisory-key derivation shared by every runtime.
 */
/** The longest key the contract admits, in UTF-8 bytes. */
export declare const MAX_LOCK_KEY_BYTES = 512;
/**
 * A caller-chosen lock identity. Convention: `<org>/<domain>/<name>`, e.g.
 * `zed-pkg/registry/publish:zed-lib-core`.
 */
export type LockKey = string & {
    readonly __brand: "LockKey";
};
/** Validate the contract's length bound and brand the string. */
export declare function lockKey(key: string): LockKey;
/** FNV-1a, 64-bit, over the UTF-8 bytes of `key`, as an unsigned bigint. */
export declare function fnv1a64(key: string): bigint;
/**
 * The Postgres `bigint` every runtime locks for `key`: FNV-1a 64
 * reinterpreted as a two's-complement signed integer. Pass it to a driver as
 * a bigint or as `advisoryKey(k).toString()` — never as a Number, which
 * cannot hold 64 bits. Vectors: `conformance/cases/advisory-key.json`.
 */
export declare function advisoryKey(key: string): bigint;
