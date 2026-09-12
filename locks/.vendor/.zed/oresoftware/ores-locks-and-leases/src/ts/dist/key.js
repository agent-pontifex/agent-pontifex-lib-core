/**
 * Lock identities and the advisory-key derivation shared by every runtime.
 */
/** The longest key the contract admits, in UTF-8 bytes. */
export const MAX_LOCK_KEY_BYTES = 512;
const encoder = new TextEncoder();
/** Validate the contract's length bound and brand the string. */
export function lockKey(key) {
    const bytes = encoder.encode(key).length;
    if (bytes > MAX_LOCK_KEY_BYTES) {
        throw new RangeError(`lock key is ${bytes} bytes; the contract allows at most ${MAX_LOCK_KEY_BYTES}`);
    }
    return key;
}
const FNV_OFFSET_BASIS = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const MASK64 = (1n << 64n) - 1n;
/** FNV-1a, 64-bit, over the UTF-8 bytes of `key`, as an unsigned bigint. */
export function fnv1a64(key) {
    let hash = FNV_OFFSET_BASIS;
    for (const byte of encoder.encode(key)) {
        hash ^= BigInt(byte);
        hash = (hash * FNV_PRIME) & MASK64;
    }
    return hash;
}
/**
 * The Postgres `bigint` every runtime locks for `key`: FNV-1a 64
 * reinterpreted as a two's-complement signed integer. Pass it to a driver as
 * a bigint or as `advisoryKey(k).toString()` — never as a Number, which
 * cannot hold 64 bits. Vectors: `conformance/cases/advisory-key.json`.
 */
export function advisoryKey(key) {
    return BigInt.asIntN(64, fnv1a64(key));
}
