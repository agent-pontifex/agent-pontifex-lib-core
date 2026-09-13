-record(lease, {
    acquire :: fun((ores_locks_and_leases:lock_key(), ores_locks_and_leases:acquire_options(), boolean()) -> {ok,
            ores_locks_and_leases:lease_grant()} |
        {error, ores_locks_and_leases:lock_error()}),
    renew :: fun((ores_locks_and_leases:lease_grant(), integer()) -> {ok,
            ores_locks_and_leases:lease_grant()} |
        {error, ores_locks_and_leases:lock_error()}),
    release :: fun((ores_locks_and_leases:lease_grant()) -> {ok, boolean()} |
        {error, ores_locks_and_leases:lock_error()})
}).
