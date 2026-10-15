-module(ores_locks_and_leases@pg).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/ores_locks_and_leases/pg.gleam").
-export([xact_lock/2, try_xact_lock/2, with_xact_lock/7, dedicated/1, dedicated_inner/1, with_session_lock/7]).
-export_type([guarded/0, dedicated_connection/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " The inner layer over `pog`: transaction- and session-scoped Postgres\n"
    " advisory locks, composed with the fiducia lease from the core module.\n"
    "\n"
    " Session scope needs one physical connection for lock, work and unlock.\n"
    " `pog` pools, so `DedicatedConnection` wraps a pool built with\n"
    " `pog.pool_size(1)` — the only handle `with_session_lock` accepts.\n"
).

-type guarded() :: {guarded,
        ores_locks_and_leases:lock_key(),
        gleam@option:option(ores_locks_and_leases:lease_grant()),
        gleam@option:option(pog:connection())}.

-opaque dedicated_connection() :: {dedicated_connection, pog:connection()}.

-file("src/ores_locks_and_leases/pg.gleam", 29).
-spec key_param(ores_locks_and_leases:lock_key()) -> pog:value().
key_param(Key) ->
    pog_ffi:coerce(ores_locks_and_leases:key_advisory(Key)).

-file("src/ores_locks_and_leases/pg.gleam", 33).
-spec query_error_message(pog:query_error()) -> binary().
query_error_message(Error) ->
    gleam@string:inspect(Error).

-file("src/ores_locks_and_leases/pg.gleam", 37).
-spec exec(
    pog:connection(),
    ores_locks_and_leases:lock_key(),
    binary(),
    ores_locks_and_leases:step()
) -> {ok, nil} | {error, ores_locks_and_leases:lock_error()}.
exec(Conn, Key, Sql, Step) ->
    _pipe = pog:'query'(Sql),
    _pipe@1 = pog:parameter(_pipe, key_param(Key)),
    _pipe@2 = pog:execute(_pipe@1, Conn),
    _pipe@3 = gleam@result:map(_pipe@2, fun(_) -> nil end),
    gleam@result:map_error(
        _pipe@3,
        fun(Error) ->
            ores_locks_and_leases:database_error(
                Key,
                Step,
                query_error_message(Error)
            )
        end
    ).

-file("src/ores_locks_and_leases/pg.gleam", 52).
-spec query_bool(
    pog:connection(),
    ores_locks_and_leases:lock_key(),
    binary(),
    ores_locks_and_leases:step()
) -> {ok, boolean()} | {error, ores_locks_and_leases:lock_error()}.
query_bool(Conn, Key, Sql, Step) ->
    Decoder = begin
        gleam@dynamic@decode:field(
            0,
            {decoder, fun gleam@dynamic@decode:decode_bool/1},
            fun(Value) -> gleam@dynamic@decode:success(Value) end
        )
    end,
    _pipe = pog:'query'(Sql),
    _pipe@1 = pog:parameter(_pipe, key_param(Key)),
    _pipe@2 = pog:returning(_pipe@1, Decoder),
    _pipe@3 = pog:execute(_pipe@2, Conn),
    _pipe@4 = gleam@result:map_error(
        _pipe@3,
        fun(Error) ->
            ores_locks_and_leases:database_error(
                Key,
                Step,
                query_error_message(Error)
            )
        end
    ),
    gleam@result:'try'(
        _pipe@4,
        fun(Returned) -> case erlang:element(3, Returned) of
                [Value@1 | _] ->
                    {ok, Value@1};

                [] ->
                    {error,
                        ores_locks_and_leases:database_error(
                            Key,
                            Step,
                            <<<<"`"/utf8, Sql/binary>>/binary,
                                "` returned no row"/utf8>>
                        )}
            end end
    ).

-file("src/ores_locks_and_leases/pg.gleam", 80).
?DOC(
    " `SELECT pg_advisory_xact_lock($1)` on `conn`, which must be inside a\n"
    " transaction. Released at commit/rollback.\n"
).
-spec xact_lock(pog:connection(), ores_locks_and_leases:lock_key()) -> {ok, nil} |
    {error, ores_locks_and_leases:lock_error()}.
xact_lock(Conn, Key) ->
    exec(
        Conn,
        Key,
        <<"SELECT pg_advisory_xact_lock($1)"/utf8>>,
        pg_advisory_xact_lock
    ).

-file("src/ores_locks_and_leases/pg.gleam", 88).
?DOC(" `SELECT pg_try_advisory_xact_lock($1)`. A held key is `Contention`.\n").
-spec try_xact_lock(pog:connection(), ores_locks_and_leases:lock_key()) -> {ok,
        nil} |
    {error, ores_locks_and_leases:lock_error()}.
try_xact_lock(Conn, Key) ->
    gleam@result:'try'(
        query_bool(
            Conn,
            Key,
            <<"SELECT pg_try_advisory_xact_lock($1)"/utf8>>,
            pg_try_advisory_xact_lock
        ),
        fun(Acquired) -> case Acquired of
                true ->
                    {ok, nil};

                false ->
                    {error,
                        ores_locks_and_leases:contention(
                            Key,
                            pg_try_advisory_xact_lock
                        )}
            end end
    ).

-file("src/ores_locks_and_leases/pg.gleam", 342).
-spec finish(
    ores_locks_and_leases:lock_key(),
    gleam@option:option(ores_locks_and_leases:lease()),
    gleam@option:option(ores_locks_and_leases:lease_grant()),
    {ok, JIL} | {error, ores_locks_and_leases:lock_error()}
) -> {ok, JIL} | {error, ores_locks_and_leases:lock_error()}.
finish(Key, Lease, Grant, Inner) ->
    case {Lease, Grant} of
        {{some, Lease@1}, {some, Grant@1}} ->
            ores_locks_and_leases:settle(Key, Lease@1, Grant@1, Inner);

        {_, _} ->
            Inner
    end.

-file("src/ores_locks_and_leases/pg.gleam", 189).
-spec decode_error(ores_locks_and_leases:lock_key(), binary()) -> ores_locks_and_leases:lock_error().
decode_error(Key, Encoded) ->
    case gleam@string:split(Encoded, <<"\x{1F}"/utf8>>) of
        [Kind, Step, Message] ->
            Kind@1 = case Kind of
                <<"contention"/utf8>> ->
                    contention;

                <<"timeout"/utf8>> ->
                    timeout;

                <<"lost_lease"/utf8>> ->
                    lost_lease;

                <<"transport"/utf8>> ->
                    transport;

                <<"database"/utf8>> ->
                    database;

                <<"work"/utf8>> ->
                    work_failed;

                _ ->
                    invalid_plan
            end,
            Step@2 = case ores_locks_and_leases:step_from_string(Step) of
                {ok, Step@1} ->
                    {some, Step@1};

                {error, nil} ->
                    none
            end,
            {lock_error, Kind@1, Key, Step@2, Message};

        _ ->
            ores_locks_and_leases:database_error(Key, pg_rollback, Encoded)
    end.

-file("src/ores_locks_and_leases/pg.gleam", 177).
-spec encode_error(ores_locks_and_leases:lock_error()) -> binary().
encode_error(Error) ->
    Step@1 = case erlang:element(4, Error) of
        {some, Step} ->
            ores_locks_and_leases:step_to_string(Step);

        none ->
            <<""/utf8>>
    end,
    <<<<<<<<(ores_locks_and_leases:kind_to_string(erlang:element(2, Error)))/binary,
                    "\x{1F}"/utf8>>/binary,
                Step@1/binary>>/binary,
            "\x{1F}"/utf8>>/binary,
        (erlang:element(5, Error))/binary>>.

-file("src/ores_locks_and_leases/pg.gleam", 139).
-spec run_xact(
    pog:connection(),
    ores_locks_and_leases:lock_key(),
    boolean(),
    gleam@option:option(ores_locks_and_leases:lease_grant()),
    fun((guarded()) -> {ok, JHJ} | {error, binary()})
) -> {ok, JHJ} | {error, ores_locks_and_leases:lock_error()}.
run_xact(Db, Key, Wait, Grant, Work) ->
    Outcome = pog:transaction(
        Db,
        fun(Conn) ->
            Locked = case Wait of
                true ->
                    xact_lock(Conn, Key);

                false ->
                    try_xact_lock(Conn, Key)
            end,
            case Locked of
                {error, Error} ->
                    {error, encode_error(Error)};

                {ok, nil} ->
                    case Work({guarded, Key, Grant, {some, Conn}}) of
                        {ok, Value} ->
                            {ok, Value};

                        {error, Cause} ->
                            {error,
                                encode_error(
                                    ores_locks_and_leases:work_error(Key, Cause)
                                )}
                    end
            end
        end
    ),
    case Outcome of
        {ok, Value@1} ->
            {ok, Value@1};

        {error, {transaction_rolled_back, Encoded}} ->
            {error, decode_error(Key, Encoded)};

        {error, {transaction_query_error, Error@1}} ->
            {error,
                ores_locks_and_leases:database_error(
                    Key,
                    pg_commit,
                    query_error_message(Error@1)
                )}
    end.

-file("src/ores_locks_and_leases/pg.gleam", 329).
-spec acquire(
    ores_locks_and_leases:lock_key(),
    boolean(),
    ores_locks_and_leases:acquire_options(),
    gleam@option:option(ores_locks_and_leases:lease())
) -> {ok, gleam@option:option(ores_locks_and_leases:lease_grant())} |
    {error, ores_locks_and_leases:lock_error()}.
acquire(Key, Wait, Opts, Lease) ->
    case Lease of
        none ->
            {ok, none};

        {some, Lease@1} ->
            _pipe = ores_locks_and_leases:acquire_lease(
                Key,
                Wait,
                Opts,
                Lease@1
            ),
            gleam@result:map(_pipe, fun(Field@0) -> {some, Field@0} end)
    end.

-file("src/ores_locks_and_leases/pg.gleam", 313).
-spec pick_lease(
    ores_locks_and_leases:lock_key(),
    ores_locks_and_leases:layers(),
    gleam@option:option(ores_locks_and_leases:lease())
) -> {ok, gleam@option:option(ores_locks_and_leases:lease())} |
    {error, ores_locks_and_leases:lock_error()}.
pick_lease(Key, Layers, Lease) ->
    case {erlang:element(2, Layers), Lease} of
        {false, _} ->
            {ok, none};

        {true, {some, Lease@1}} ->
            {ok, {some, Lease@1}};

        {true, none} ->
            {error,
                ores_locks_and_leases:invalid_plan(
                    Key,
                    <<"layers.fiducia is enabled but no lease authority was supplied"/utf8>>
                )}
    end.

-file("src/ores_locks_and_leases/pg.gleam", 109).
?DOC(
    " Run `work` under a fiducia lease and/or a transaction-scoped advisory\n"
    " lock. `layers.fiducia` needs `lease`; `layers.pg_advisory` needs `db`; a\n"
    " missing one is `InvalidPlan` before anything is acquired. The\n"
    " transaction commits when `work` returns `Ok` and rolls back on `Error`;\n"
    " the lease is released either way.\n"
).
-spec with_xact_lock(
    ores_locks_and_leases:lock_key(),
    ores_locks_and_leases:layers(),
    boolean(),
    ores_locks_and_leases:acquire_options(),
    gleam@option:option(ores_locks_and_leases:lease()),
    gleam@option:option(pog:connection()),
    fun((guarded()) -> {ok, JHD} | {error, binary()})
) -> {ok, JHD} | {error, ores_locks_and_leases:lock_error()}.
with_xact_lock(Key, Layers, Wait, Opts, Lease, Db, Work) ->
    gleam@result:'try'(
        pick_lease(Key, Layers, Lease),
        fun(Lease@1) ->
            gleam@result:'try'(case {erlang:element(3, Layers), Db} of
                    {false, _} ->
                        {ok, none};

                    {true, {some, Db@1}} ->
                        {ok, {some, Db@1}};

                    {true, none} ->
                        {error,
                            ores_locks_and_leases:invalid_plan(
                                Key,
                                <<"layers.pg_advisory is enabled but no database connection was supplied"/utf8>>
                            )}
                end, fun(Db@2) ->
                    gleam@result:'try'(
                        acquire(Key, Wait, Opts, Lease@1),
                        fun(Grant) ->
                            Inner = case Db@2 of
                                none ->
                                    _pipe = Work({guarded, Key, Grant, none}),
                                    gleam@result:map_error(
                                        _pipe,
                                        fun(_capture) ->
                                            ores_locks_and_leases:work_error(
                                                Key,
                                                _capture
                                            )
                                        end
                                    );

                                {some, Db@3} ->
                                    run_xact(Db@3, Key, Wait, Grant, Work)
                            end,
                            finish(Key, Lease@1, Grant, Inner)
                        end
                    )
                end)
        end
    ).

-file("src/ores_locks_and_leases/pg.gleam", 219).
?DOC(
    " Wrap a connection the caller built with `pog.pool_size(1)`. A larger\n"
    " pool makes `pg_advisory_unlock` a silent no-op on a different session.\n"
).
-spec dedicated(pog:connection()) -> dedicated_connection().
dedicated(Conn) ->
    {dedicated_connection, Conn}.

-file("src/ores_locks_and_leases/pg.gleam", 223).
-spec dedicated_inner(dedicated_connection()) -> pog:connection().
dedicated_inner(Conn) ->
    {dedicated_connection, Inner} = Conn,
    Inner.

-file("src/ores_locks_and_leases/pg.gleam", 305).
-spec unlock_mismatch(ores_locks_and_leases:lock_key()) -> ores_locks_and_leases:lock_error().
unlock_mismatch(Key) ->
    ores_locks_and_leases:database_error(
        Key,
        pg_advisory_unlock,
        <<"pg_advisory_unlock reported the session did not hold the lock"/utf8>>
    ).

-file("src/ores_locks_and_leases/pg.gleam", 262).
-spec run_session(
    pog:connection(),
    ores_locks_and_leases:lock_key(),
    boolean(),
    gleam@option:option(ores_locks_and_leases:lease_grant()),
    fun((guarded()) -> {ok, JHW} | {error, binary()})
) -> {ok, JHW} | {error, ores_locks_and_leases:lock_error()}.
run_session(Conn, Key, Wait, Grant, Work) ->
    gleam@result:'try'(case Wait of
            true ->
                exec(
                    Conn,
                    Key,
                    <<"SELECT pg_advisory_lock($1)"/utf8>>,
                    pg_advisory_lock
                );

            false ->
                gleam@result:'try'(
                    query_bool(
                        Conn,
                        Key,
                        <<"SELECT pg_try_advisory_lock($1)"/utf8>>,
                        pg_try_advisory_lock
                    ),
                    fun(Acquired) -> case Acquired of
                            true ->
                                {ok, nil};

                            false ->
                                {error,
                                    ores_locks_and_leases:contention(
                                        Key,
                                        pg_try_advisory_lock
                                    )}
                        end end
                )
        end, fun(_) ->
            Inner = begin
                _pipe = Work({guarded, Key, Grant, {some, Conn}}),
                gleam@result:map_error(
                    _pipe,
                    fun(_capture) ->
                        ores_locks_and_leases:work_error(Key, _capture)
                    end
                )
            end,
            Unlocked = query_bool(
                Conn,
                Key,
                <<"SELECT pg_advisory_unlock($1)"/utf8>>,
                pg_advisory_unlock
            ),
            case {Inner, Unlocked} of
                {{error, Inner@1}, {error, Cleanup}} ->
                    {error,
                        ores_locks_and_leases:cleanup_failure(Cleanup, Inner@1)};

                {{error, Inner@2}, {ok, false}} ->
                    {error,
                        ores_locks_and_leases:cleanup_failure(
                            unlock_mismatch(Key),
                            Inner@2
                        )};

                {{error, Inner@3}, {ok, true}} ->
                    {error, Inner@3};

                {{ok, _}, {error, Error}} ->
                    {error, Error};

                {{ok, _}, {ok, false}} ->
                    {error, unlock_mismatch(Key)};

                {{ok, Value}, {ok, true}} ->
                    {ok, Value}
            end
        end).

-file("src/ores_locks_and_leases/pg.gleam", 232).
?DOC(
    " Run `work` under a fiducia lease and/or a session-scoped advisory lock.\n"
    " No transaction is opened. The lock is always unlocked after `work`; an\n"
    " unlock that reports the session did not hold the lock is `Database` at\n"
    " `pg.advisory_unlock` and wins over a successful `work`.\n"
).
-spec with_session_lock(
    ores_locks_and_leases:lock_key(),
    ores_locks_and_leases:layers(),
    boolean(),
    ores_locks_and_leases:acquire_options(),
    gleam@option:option(ores_locks_and_leases:lease()),
    gleam@option:option(dedicated_connection()),
    fun((guarded()) -> {ok, JHQ} | {error, binary()})
) -> {ok, JHQ} | {error, ores_locks_and_leases:lock_error()}.
with_session_lock(Key, Layers, Wait, Opts, Lease, Conn, Work) ->
    gleam@result:'try'(
        pick_lease(Key, Layers, Lease),
        fun(Lease@1) ->
            gleam@result:'try'(case {erlang:element(3, Layers), Conn} of
                    {false, _} ->
                        {ok, none};

                    {true, {some, Conn@1}} ->
                        {ok, {some, dedicated_inner(Conn@1)}};

                    {true, none} ->
                        {error,
                            ores_locks_and_leases:invalid_plan(
                                Key,
                                <<"layers.pg_advisory is enabled with session scope but no dedicated connection was supplied"/utf8>>
                            )}
                end, fun(Conn@2) ->
                    gleam@result:'try'(
                        acquire(Key, Wait, Opts, Lease@1),
                        fun(Grant) ->
                            Inner = case Conn@2 of
                                none ->
                                    _pipe = Work({guarded, Key, Grant, none}),
                                    gleam@result:map_error(
                                        _pipe,
                                        fun(_capture) ->
                                            ores_locks_and_leases:work_error(
                                                Key,
                                                _capture
                                            )
                                        end
                                    );

                                {some, Conn@3} ->
                                    run_session(Conn@3, Key, Wait, Grant, Work)
                            end,
                            finish(Key, Lease@1, Grant, Inner)
                        end
                    )
                end)
        end
    ).
