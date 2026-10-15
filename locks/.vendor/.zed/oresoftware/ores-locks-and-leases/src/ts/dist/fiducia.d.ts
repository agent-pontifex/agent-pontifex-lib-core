/**
 * `Lease` over the fiducia-cloud node HTTP protocol, using only `fetch`. It
 * speaks the same three endpoints the official clients do
 * (`/v1/locks/acquire`, `/v1/locks/renew`, `/v1/locks/release`) with the
 * same headers, so a service that already holds a `@fiducia/client` keeps it
 * for everything else and hands this adapter the same base URL and
 * credentials.
 *
 * The node never holds a request open: `acquire` returns at once with
 * `acquired: false` when the key is held, so the client owns the wait. This
 * adapter polls at `retryIntervalMs` until the grant arrives or
 * `waitTimeoutMs` elapses.
 */
import type { LockKey } from "./key.js";
import type { AcquireOptions, Lease, LeaseGrant } from "./lease.js";
export type FetchLike = (input: string, init: {
    method: string;
    headers: Record<string, string>;
    body: string;
    redirect: "manual";
}) => Promise<{
    status: number;
    text(): Promise<string>;
}>;
export interface FiduciaLeaseOptions {
    /** Base URL of the fiducia node or edge, e.g. `https://fiducia.example` or `http://localhost:8090`. */
    readonly baseUrl: string;
    /** Trusted internal hop: `x-fiducia-internal-auth` + `x-fiducia-org-id`. */
    readonly internal?: {
        readonly secret: string;
        readonly orgId: string;
    };
    /** Public edge: `Authorization: Bearer`. */
    readonly apiKey?: string;
    /** Send a credential over cleartext http to a non-local host. Only for fully trusted paths. */
    readonly allowCleartextInternal?: boolean;
    /** Swap the transport (tests, custom agents). Defaults to global `fetch`. */
    readonly fetch?: FetchLike;
    /** Source of holder ids when `AcquireOptions.holder` is absent. */
    readonly generateHolder?: () => string;
}
export declare function cleartextRefusal(baseUrl: string, hasCredential: boolean, allow: boolean): string | undefined;
/** An unguessable holder identity; holder names carry queue identity and cancellation authority. */
export declare function generatedHolder(): string;
export declare class FiduciaLease implements Lease {
    #private;
    constructor(options: FiduciaLeaseOptions);
    acquire(key: LockKey, opts: AcquireOptions, wait: boolean): Promise<LeaseGrant>;
    renew(grant: LeaseGrant, ttlMs: number): Promise<LeaseGrant>;
    release(grant: LeaseGrant): Promise<boolean>;
}
