{application, agent_pontifex_locks, [
    {vsn, "0.1.0"},
    {applications, [gleam_stdlib,
                    gleeunit,
                    ores_locks_and_leases]},
    {description, "agent-pontifex lock routines: ores_locks_and_leases with the agent-pontifex key prefix and lock catalog."},
    {modules, [agent_pontifex_locks_test]},
    {registered, []}
]}.
