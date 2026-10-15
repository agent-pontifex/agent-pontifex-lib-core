-module(agent_pontifex_locks).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/agent_pontifex_locks.gleam").
-export([domain_to_string/1, key/2, entry_key/2, entry_plan/1, catalog/0, catalog_is_well_formed/0]).
-export_type([domain/0, entry/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " agent-pontifex lock routines: `ores_locks_and_leases` with the org's key prefix\n"
    " and lock catalog. Generated from `../catalog.json` by\n"
    " ores-locks-and-leases' `templates/lib-core/gen_org_locks.py`.\n"
).

-type domain() :: jobs | migrations | outbox | tenant.

-type entry() :: {entry,
        domain(),
        binary(),
        ores_locks_and_leases:layers(),
        ores_locks_and_leases:pg_scope(),
        boolean()}.

-file("src/agent_pontifex_locks.gleam", 20).
-spec domain_to_string(domain()) -> binary().
domain_to_string(Domain) ->
    case Domain of
        jobs ->
            <<"jobs"/utf8>>;

        migrations ->
            <<"migrations"/utf8>>;

        outbox ->
            <<"outbox"/utf8>>;

        tenant ->
            <<"tenant"/utf8>>
    end.

-file("src/agent_pontifex_locks.gleam", 30).
?DOC(" Build `agent-pontifex/<domain>/<name>`.\n").
-spec key(domain(), binary()) -> {ok, ores_locks_and_leases:lock_key()} |
    {error, binary()}.
key(Domain, Name) ->
    ores_locks_and_leases:lock_key(
        <<<<<<<<"agent-pontifex"/utf8, "/"/utf8>>/binary,
                    (domain_to_string(Domain))/binary>>/binary,
                "/"/utf8>>/binary,
            Name/binary>>
    ).

-file("src/agent_pontifex_locks.gleam", 54).
-spec fill_placeholders(binary(), list(binary())) -> binary().
fill_placeholders(Name, Fill) ->
    case gleam@string:split_once(Name, <<"{"/utf8>>) of
        {error, nil} ->
            Name;

        {ok, {Before, Rest}} ->
            After@1 = case gleam@string:split_once(Rest, <<"}"/utf8>>) of
                {ok, {_, After}} ->
                    After;

                {error, nil} ->
                    <<""/utf8>>
            end,
            {Value, Remaining@1} = case Fill of
                [First | Remaining] ->
                    {First, Remaining};

                [] ->
                    {<<""/utf8>>, []}
            end,
            <<<<Before/binary, Value/binary>>/binary,
                (fill_placeholders(After@1, Remaining@1))/binary>>
    end.

-file("src/agent_pontifex_locks.gleam", 47).
?DOC(" The key for `entry` with `{placeholders}` filled from `fill`, in order.\n").
-spec entry_key(entry(), list(binary())) -> {ok,
        ores_locks_and_leases:lock_key()} |
    {error, binary()}.
entry_key(Entry, Fill) ->
    key(
        erlang:element(2, Entry),
        fill_placeholders(erlang:element(3, Entry), Fill)
    ).

-file("src/agent_pontifex_locks.gleam", 72).
?DOC(" The plan an entry's defaults produce.\n").
-spec entry_plan(entry()) -> ores_locks_and_leases:plan().
entry_plan(Entry) ->
    ores_locks_and_leases:plan(
        erlang:element(4, Entry),
        erlang:element(5, Entry),
        erlang:element(6, Entry)
    ).

-file("src/agent_pontifex_locks.gleam", 113).
?DOC(" Every catalog entry.\n").
-spec catalog() -> list(entry()).
catalog() ->
    [{entry, migrations, <<"apply"/utf8>>, {layers, true, true}, session, false},
        {entry,
            jobs,
            <<"singleton:{job}"/utf8>>,
            {layers, true, true},
            transaction,
            false},
        {entry,
            outbox,
            <<"drain"/utf8>>,
            {layers, false, true},
            transaction,
            false},
        {entry,
            tenant,
            <<"{tenant_id}/mutate"/utf8>>,
            {layers, true, true},
            transaction,
            true}].

-file("src/agent_pontifex_locks.gleam", 118).
?DOC(" Every catalog entry plans to something that runs `work` exactly once.\n").
-spec catalog_is_well_formed() -> boolean().
catalog_is_well_formed() ->
    gleam@list:all(
        catalog(),
        fun(Entry) ->
            begin
                _pipe = gleam@list:filter(
                    erlang:element(5, entry_plan(Entry)),
                    fun(Step) -> Step =:= work end
                ),
                erlang:length(_pipe)
            end
            =:= 1
        end
    ).
