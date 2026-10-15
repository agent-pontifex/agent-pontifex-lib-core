-module(ores_locks_and_leases).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/ores_locks_and_leases.gleam").
-export([lock_key/1, key_to_string/1, fnv1a64/1, advisory_key/1, key_advisory/1, pg_scope_to_string/1, pg_scope_from_string/1, step_to_string/1, step_from_string/1, plan/3, kind_to_string/1, error_to_string/1, retryable/1, contention/2, timeout/3, work_error/2, invalid_plan/2, database_error/3, transport_error/2, tag_step/2, cleanup_failure/2, default_acquire_options/0, settle/4, acquire_lease/4, with_lease/6, holder_or/2]).
-export_type([lock_key/0, layers/0, pg_scope/0, step/0, plan/0, kind/0, lock_error/0, acquire_options/0, lease_grant/0, lease/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " Composed distributed locking for the ORESoftware fleet — the Gleam slice\n"
    " of `ORESoftware/ores-locks-and-leases`.\n"
    "\n"
    " Two layers, each individually switchable through `Layers`: an outer\n"
    " fiducia-cloud lease (cross-host, TTL-bounded, fenced) and an inner\n"
    " Postgres advisory lock (transaction- or session-scoped). The order is the\n"
    " contract's and the same in every language slice:\n"
    "\n"
    "     fiducia.acquire -> pg.begin -> pg.advisory_xact_lock -> work -> pg.commit -> fiducia.release\n"
    "\n"
    " This module is the dependency-free core: keys, the plan, errors, the\n"
    " `Lease` seam and `with_lease` (fiducia only / neither). The adapters live\n"
    " beside it: `ores_locks_and_leases/pg` (pog) and\n"
    " `ores_locks_and_leases/fiducia` (gleam_httpc).\n"
).

-opaque lock_key() :: {lock_key, binary()}.

-type layers() :: {layers, boolean(), boolean()}.

-type pg_scope() :: transaction | session.

-type step() :: fiducia_acquire |
    fiducia_try_acquire |
    fiducia_release |
    pg_begin |
    pg_advisory_xact_lock |
    pg_try_advisory_xact_lock |
    pg_commit |
    pg_rollback |
    pg_advisory_lock |
    pg_try_advisory_lock |
    pg_advisory_unlock |
    work.

-type plan() :: {plan, layers(), pg_scope(), boolean(), list(step())}.

-type kind() :: contention |
    timeout |
    lost_lease |
    transport |
    database |
    work_failed |
    invalid_plan.

-type lock_error() :: {lock_error,
        kind(),
        lock_key(),
        gleam@option:option(step()),
        binary()}.

-type acquire_options() :: {acquire_options,
        integer(),
        integer(),
        integer(),
        gleam@option:option(binary())}.

-type lease_grant() :: {lease_grant,
        lock_key(),
        binary(),
        integer(),
        gleam@option:option(integer()),
        integer()}.

-type lease() :: {lease,
        fun((lock_key(), acquire_options(), boolean()) -> {ok, lease_grant()} |
            {error, lock_error()}),
        fun((lease_grant(), integer()) -> {ok, lease_grant()} |
            {error, lock_error()}),
        fun((lease_grant()) -> {ok, boolean()} | {error, lock_error()})}.

-file("src/ores_locks_and_leases.gleam", 33).
?DOC(" Validate the contract's length bound.\n").
-spec lock_key(binary()) -> {ok, lock_key()} | {error, binary()}.
lock_key(Key) ->
    Bytes = erlang:byte_size(gleam_stdlib:identity(Key)),
    case Bytes > 512 of
        true ->
            {error,
                <<<<<<"lock key is "/utf8,
                            (erlang:integer_to_binary(Bytes))/binary>>/binary,
                        " bytes; the contract allows at most "/utf8>>/binary,
                    (erlang:integer_to_binary(512))/binary>>};

        false ->
            {ok, {lock_key, Key}}
    end.

-file("src/ores_locks_and_leases.gleam", 47).
-spec key_to_string(lock_key()) -> binary().
key_to_string(Key) ->
    {lock_key, S} = Key,
    S.

-file("src/ores_locks_and_leases.gleam", 69).
-spec fold_bytes(bitstring(), integer()) -> integer().
fold_bytes(Bytes, Hash) ->
    case Bytes of
        <<Byte/integer, Rest/bitstring>> ->
            fold_bytes(
                Rest,
                erlang:'band'(
                    erlang:'bxor'(Hash, Byte) * 1099511628211,
                    18446744073709551615
                )
            );

        _ ->
            Hash
    end.

-file("src/ores_locks_and_leases.gleam", 65).
?DOC(
    " FNV-1a, 64-bit, over the UTF-8 bytes of `key`, as an unsigned integer.\n"
    " Gleam integers are arbitrary precision on the Erlang target, so the\n"
    " product is masked back to 64 bits after every step.\n"
).
-spec fnv1a64(binary()) -> integer().
fnv1a64(Key) ->
    fold_bytes(gleam_stdlib:identity(Key), 14695981039346656037).

-file("src/ores_locks_and_leases.gleam", 86).
?DOC(
    " The Postgres `bigint` every runtime locks for `key`: FNV-1a 64\n"
    " reinterpreted as a two's-complement signed integer. Vectors:\n"
    " `conformance/cases/advisory-key.json`.\n"
).
-spec advisory_key(binary()) -> integer().
advisory_key(Key) ->
    Unsigned = fnv1a64(Key),
    case Unsigned >= 9223372036854775808 of
        true ->
            Unsigned - 18446744073709551616;

        false ->
            Unsigned
    end.

-file("src/ores_locks_and_leases.gleam", 94).
-spec key_advisory(lock_key()) -> integer().
key_advisory(Key) ->
    advisory_key(key_to_string(Key)).

-file("src/ores_locks_and_leases.gleam", 124).
-spec pg_scope_to_string(pg_scope()) -> binary().
pg_scope_to_string(Scope) ->
    case Scope of
        transaction ->
            <<"transaction"/utf8>>;

        session ->
            <<"session"/utf8>>
    end.

-file("src/ores_locks_and_leases.gleam", 131).
-spec pg_scope_from_string(binary()) -> {ok, pg_scope()} | {error, nil}.
pg_scope_from_string(Value) ->
    case Value of
        <<"transaction"/utf8>> ->
            {ok, transaction};

        <<"session"/utf8>> ->
            {ok, session};

        _ ->
            {error, nil}
    end.

-file("src/ores_locks_and_leases.gleam", 170).
-spec step_to_string(step()) -> binary().
step_to_string(Step) ->
    case Step of
        fiducia_acquire ->
            <<"fiducia.acquire"/utf8>>;

        fiducia_try_acquire ->
            <<"fiducia.try_acquire"/utf8>>;

        fiducia_release ->
            <<"fiducia.release"/utf8>>;

        pg_begin ->
            <<"pg.begin"/utf8>>;

        pg_advisory_xact_lock ->
            <<"pg.advisory_xact_lock"/utf8>>;

        pg_try_advisory_xact_lock ->
            <<"pg.try_advisory_xact_lock"/utf8>>;

        pg_commit ->
            <<"pg.commit"/utf8>>;

        pg_rollback ->
            <<"pg.rollback"/utf8>>;

        pg_advisory_lock ->
            <<"pg.advisory_lock"/utf8>>;

        pg_try_advisory_lock ->
            <<"pg.try_advisory_lock"/utf8>>;

        pg_advisory_unlock ->
            <<"pg.advisory_unlock"/utf8>>;

        work ->
            <<"work"/utf8>>
    end.

-file("src/ores_locks_and_leases.gleam", 187).
-spec step_from_string(binary()) -> {ok, step()} | {error, nil}.
step_from_string(Value) ->
    gleam@list:find(
        [fiducia_acquire,
            fiducia_try_acquire,
            fiducia_release,
            pg_begin,
            pg_advisory_xact_lock,
            pg_try_advisory_xact_lock,
            pg_commit,
            pg_rollback,
            pg_advisory_lock,
            pg_try_advisory_lock,
            pg_advisory_unlock,
            work],
        fun(Step) -> step_to_string(Step) =:= Value end
    ).

-file("src/ores_locks_and_leases.gleam", 199).
?DOC(
    " Compute the plan. Pure; identical across every language slice. `wait`\n"
    " blocks each layer up to its budget; otherwise the non-blocking form of\n"
    " each acquisition is used and the routine fails fast with `Contention`.\n"
).
-spec plan(layers(), pg_scope(), boolean()) -> plan().
plan(Layers, Pg_scope, Wait) ->
    Pick = fun(Blocking, Non_blocking) -> case Wait of
            true ->
                Blocking;

            false ->
                Non_blocking
        end end,
    Outer_open = case erlang:element(2, Layers) of
        true ->
            [Pick(fiducia_acquire, fiducia_try_acquire)];

        false ->
            []
    end,
    Inner = case {erlang:element(3, Layers), Pg_scope} of
        {false, _} ->
            [work];

        {true, transaction} ->
            [pg_begin,
                Pick(pg_advisory_xact_lock, pg_try_advisory_xact_lock),
                work,
                pg_commit];

        {true, session} ->
            [Pick(pg_advisory_lock, pg_try_advisory_lock),
                work,
                pg_advisory_unlock]
    end,
    Outer_close = case erlang:element(2, Layers) of
        true ->
            [fiducia_release];

        false ->
            []
    end,
    {plan,
        Layers,
        Pg_scope,
        Wait,
        lists:append([Outer_open, Inner, Outer_close])}.

-file("src/ores_locks_and_leases.gleam", 260).
-spec kind_to_string(kind()) -> binary().
kind_to_string(Kind) ->
    case Kind of
        contention ->
            <<"contention"/utf8>>;

        timeout ->
            <<"timeout"/utf8>>;

        lost_lease ->
            <<"lost_lease"/utf8>>;

        transport ->
            <<"transport"/utf8>>;

        database ->
            <<"database"/utf8>>;

        work_failed ->
            <<"work"/utf8>>;

        invalid_plan ->
            <<"invalid_plan"/utf8>>
    end.

-file("src/ores_locks_and_leases.gleam", 278).
-spec error_to_string(lock_error()) -> binary().
error_to_string(Error) ->
    At = case erlang:element(4, Error) of
        {some, Step} ->
            <<" at "/utf8, (step_to_string(Step))/binary>>;

        none ->
            <<""/utf8>>
    end,
    <<<<<<<<<<(kind_to_string(erlang:element(2, Error)))/binary, At/binary>>/binary,
                    " for `"/utf8>>/binary,
                (key_to_string(erlang:element(3, Error)))/binary>>/binary,
            "`: "/utf8>>/binary,
        (erlang:element(5, Error))/binary>>.

-file("src/ores_locks_and_leases.gleam", 293).
?DOC(
    " Retrying the whole routine is reasonable: busy or out of budget, nothing\n"
    " half-done.\n"
).
-spec retryable(lock_error()) -> boolean().
retryable(Error) ->
    case erlang:element(2, Error) of
        contention ->
            true;

        timeout ->
            true;

        _ ->
            false
    end.

-file("src/ores_locks_and_leases.gleam", 300).
-spec contention(lock_key(), step()) -> lock_error().
contention(Key, Step) ->
    {lock_error,
        contention,
        Key,
        {some, Step},
        <<<<"`"/utf8, (key_to_string(Key))/binary>>/binary,
            "` is held by another holder"/utf8>>}.

-file("src/ores_locks_and_leases.gleam", 309).
-spec timeout(lock_key(), step(), integer()) -> lock_error().
timeout(Key, Step, Waited_ms) ->
    {lock_error,
        timeout,
        Key,
        {some, Step},
        <<<<<<<<"gave up waiting for `"/utf8, (key_to_string(Key))/binary>>/binary,
                    "` after "/utf8>>/binary,
                (erlang:integer_to_binary(Waited_ms))/binary>>/binary,
            " ms"/utf8>>}.

-file("src/ores_locks_and_leases.gleam", 322).
-spec work_error(lock_key(), binary()) -> lock_error().
work_error(Key, Cause) ->
    {lock_error, work_failed, Key, {some, work}, Cause}.

-file("src/ores_locks_and_leases.gleam", 326).
-spec invalid_plan(lock_key(), binary()) -> lock_error().
invalid_plan(Key, Message) ->
    {lock_error, invalid_plan, Key, none, Message}.

-file("src/ores_locks_and_leases.gleam", 330).
-spec database_error(lock_key(), step(), binary()) -> lock_error().
database_error(Key, Step, Message) ->
    {lock_error, database, Key, {some, Step}, Message}.

-file("src/ores_locks_and_leases.gleam", 334).
-spec transport_error(lock_key(), binary()) -> lock_error().
transport_error(Key, Message) ->
    {lock_error, transport, Key, none, Message}.

-file("src/ores_locks_and_leases.gleam", 339).
?DOC(" Fill in the step on an error that has none.\n").
-spec tag_step(lock_error(), step()) -> lock_error().
tag_step(Error, Step) ->
    case erlang:element(4, Error) of
        {some, _} ->
            Error;

        none ->
            {lock_error,
                erlang:element(2, Error),
                erlang:element(3, Error),
                {some, Step},
                erlang:element(5, Error)}
    end.

-file("src/ores_locks_and_leases.gleam", 350).
?DOC(
    " Keep a safety-critical cleanup failure primary while retaining the guarded\n"
    " operation's earlier failure. A failed release/unlock leaves ownership or\n"
    " session state unknown, so callers must not see only a work error and assume\n"
    " an immediate whole-operation retry is safe.\n"
).
-spec cleanup_failure(lock_error(), lock_error()) -> lock_error().
cleanup_failure(Cleanup, Inner) ->
    {lock_error,
        erlang:element(2, Cleanup),
        erlang:element(3, Cleanup),
        erlang:element(4, Cleanup),
        <<<<(erlang:element(5, Cleanup))/binary,
                "; guarded operation also failed: "/utf8>>/binary,
            (error_to_string(Inner))/binary>>}.

-file("src/ores_locks_and_leases.gleam", 377).
?DOC(" Mirrors the official fiducia clients: 60s lease, 30s wait budget, 250ms poll.\n").
-spec default_acquire_options() -> acquire_options().
default_acquire_options() ->
    {acquire_options, 60000, 30000, 250, none}.

-file("src/ores_locks_and_leases.gleam", 476).
-spec release_lost(lock_key(), lease_grant()) -> lock_error().
release_lost(Key, Grant) ->
    {lock_error,
        lost_lease,
        Key,
        {some, fiducia_release},
        <<<<<<<<<<<<"release of `"/utf8, (key_to_string(Key))/binary>>/binary,
                            "` (holder "/utf8>>/binary,
                        (erlang:element(3, Grant))/binary>>/binary,
                    ", fencing token "/utf8>>/binary,
                (erlang:integer_to_binary(erlang:element(4, Grant)))/binary>>/binary,
            ") matched no grant: the lease lapsed while the work ran"/utf8>>}.

-file("src/ores_locks_and_leases.gleam", 457).
?DOC(" Release the lease and combine its outcome with the inner one.\n").
-spec settle(
    lock_key(),
    lease(),
    lease_grant(),
    {ok, IVL} | {error, lock_error()}
) -> {ok, IVL} | {error, lock_error()}.
settle(Key, Lease, Grant, Inner) ->
    Released = (erlang:element(4, Lease))(Grant),
    case {Inner, Released} of
        {{error, Inner@1}, {error, Cleanup}} ->
            {error,
                cleanup_failure(tag_step(Cleanup, fiducia_release), Inner@1)};

        {{error, Inner@2}, {ok, false}} ->
            {error, cleanup_failure(release_lost(Key, Grant), Inner@2)};

        {{error, Inner@3}, {ok, true}} ->
            {error, Inner@3};

        {{ok, _}, {error, Error}} ->
            {error, tag_step(Error, fiducia_release)};

        {{ok, _}, {ok, false}} ->
            {error, release_lost(Key, Grant)};

        {{ok, Value}, {ok, true}} ->
            {ok, Value}
    end.

-file("src/ores_locks_and_leases.gleam", 443).
?DOC(" Acquire through the lease, tagging the step on an untagged error.\n").
-spec acquire_lease(lock_key(), boolean(), acquire_options(), lease()) -> {ok,
        lease_grant()} |
    {error, lock_error()}.
acquire_lease(Key, Wait, Opts, Lease) ->
    Step = case Wait of
        true ->
            fiducia_acquire;

        false ->
            fiducia_try_acquire
    end,
    _pipe = (erlang:element(2, Lease))(Key, Opts, Wait),
    gleam@result:map_error(_pipe, fun(_capture) -> tag_step(_capture, Step) end).

-file("src/ores_locks_and_leases.gleam", 419).
?DOC(
    " Run `work` under a fiducia lease only — no database layer. `engage` is\n"
    " the `layers.fiducia` boolean: `False` is the contract's \"neither\" plan\n"
    " (work runs with `None`, nothing is acquired); `True` with no lease is\n"
    " `InvalidPlan`. The lease is always released, even when `work` fails; a\n"
    " release that matched no grant after a successful `work` is `LostLease`.\n"
).
-spec with_lease(
    lock_key(),
    boolean(),
    boolean(),
    acquire_options(),
    gleam@option:option(lease()),
    fun((gleam@option:option(lease_grant())) -> {ok, IVE} | {error, binary()})
) -> {ok, IVE} | {error, lock_error()}.
with_lease(Key, Engage, Wait, Opts, Lease, Work) ->
    case {Engage, Lease} of
        {false, _} ->
            _pipe = Work(none),
            gleam@result:map_error(
                _pipe,
                fun(_capture) -> work_error(Key, _capture) end
            );

        {true, none} ->
            {error,
                invalid_plan(
                    Key,
                    <<"layers.fiducia is enabled but no lease authority was supplied"/utf8>>
                )};

        {true, {some, Lease@1}} ->
            gleam@result:'try'(
                acquire_lease(Key, Wait, Opts, Lease@1),
                fun(Grant) ->
                    Inner = begin
                        _pipe@1 = Work({some, Grant}),
                        gleam@result:map_error(
                            _pipe@1,
                            fun(_capture@1) -> work_error(Key, _capture@1) end
                        )
                    end,
                    settle(Key, Lease@1, Grant, Inner)
                end
            )
    end.

-file("src/ores_locks_and_leases.gleam", 492).
?DOC(" A holder id for adapters when the caller supplied none.\n").
-spec holder_or(acquire_options(), fun(() -> binary())) -> binary().
holder_or(Opts, Generate) ->
    case erlang:element(5, Opts) of
        {some, Holder} ->
            Holder;

        none ->
            Generate()
    end.
