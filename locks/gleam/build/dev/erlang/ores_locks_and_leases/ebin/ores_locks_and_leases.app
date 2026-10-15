{application, ores_locks_and_leases, [
    {vsn, "0.1.1"},
    {applications, [gleam_erlang,
                    gleam_http,
                    gleam_httpc,
                    gleam_json,
                    gleam_stdlib,
                    pog]},
    {description, "Composed distributed locking for the ORESoftware fleet: a fiducia-cloud lease around a Postgres advisory lock, each layer switchable, with fencing tokens threaded through to the guarded work."},
    {modules, []},
    {registered, []}
]}.
