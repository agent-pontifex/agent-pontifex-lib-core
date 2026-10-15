-record(lock_error, {
    kind :: ores_locks_and_leases:kind(),
    key :: ores_locks_and_leases:lock_key(),
    step :: gleam@option:option(ores_locks_and_leases:step()),
    message :: binary()
}).
