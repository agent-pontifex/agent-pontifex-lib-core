-record(entry, {
    domain :: agent_pontifex_locks:domain(),
    name :: binary(),
    layers :: ores_locks_and_leases:layers(),
    pg_scope :: ores_locks_and_leases:pg_scope(),
    wait :: boolean()
}).
