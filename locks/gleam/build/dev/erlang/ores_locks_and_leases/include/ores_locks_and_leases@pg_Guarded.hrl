-record(guarded, {
    key :: ores_locks_and_leases:lock_key(),
    grant :: gleam@option:option(ores_locks_and_leases:lease_grant()),
    conn :: gleam@option:option(pog:connection())
}).
