-record(plan, {
    layers :: ores_locks_and_leases:layers(),
    pg_scope :: ores_locks_and_leases:pg_scope(),
    wait :: boolean(),
    steps :: list(ores_locks_and_leases:step())
}).
