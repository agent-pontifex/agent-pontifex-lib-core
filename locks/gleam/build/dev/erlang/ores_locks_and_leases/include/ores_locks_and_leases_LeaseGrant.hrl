-record(lease_grant, {
    key :: ores_locks_and_leases:lock_key(),
    holder :: binary(),
    fencing_token :: integer(),
    lease_expires_ms :: gleam@option:option(integer()),
    ttl_ms :: integer()
}).
