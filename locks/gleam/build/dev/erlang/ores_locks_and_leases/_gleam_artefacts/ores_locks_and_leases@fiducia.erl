-module(ores_locks_and_leases@fiducia).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/ores_locks_and_leases/fiducia.gleam").
-export([generated_holder/0, internal/3, bearer/2, cleartext_refusal/3, release/2, renew/3, acquire/4, lease/1]).
-export_type([config/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " `Lease` over the fiducia-cloud node HTTP protocol with `gleam_httpc`. It\n"
    " speaks the same three endpoints the official clients do\n"
    " (`/v1/locks/acquire`, `/v1/locks/renew`, `/v1/locks/release`) with the\n"
    " same headers.\n"
    "\n"
    " The node never holds a request open: `acquire` returns at once with\n"
    " `acquired: false` when the key is held, so the client owns the wait.\n"
    " This adapter polls at `retry_interval_ms` until the grant arrives or\n"
    " `wait_timeout_ms` elapses.\n"
).

-type config() :: {config,
        binary(),
        gleam@option:option({binary(), binary()}),
        gleam@option:option(binary()),
        boolean(),
        fun(() -> binary())}.

-file("src/ores_locks_and_leases/fiducia.gleam", 79).
?DOC(" An unguessable holder identity.\n").
-spec generated_holder() -> binary().
generated_holder() ->
    <<<<<<"ores-locks-"/utf8,
                (erlang:integer_to_binary(gleam@int:random(1000000000000)))/binary>>/binary,
            "-"/utf8>>/binary,
        (erlang:integer_to_binary(gleam@int:random(1000000000000)))/binary>>.

-file("src/ores_locks_and_leases/fiducia.gleam", 62).
-spec strip_trailing_slash(binary()) -> binary().
strip_trailing_slash(Url) ->
    case gleam_stdlib:string_ends_with(Url, <<"/"/utf8>>) of
        true ->
            strip_trailing_slash(gleam@string:drop_end(Url, 1));

        false ->
            Url
    end.

-file("src/ores_locks_and_leases/fiducia.gleam", 41).
?DOC(" The trusted internal hop straight to a fiducia-node.\n").
-spec internal(binary(), binary(), binary()) -> config().
internal(Base_url, Secret, Org_id) ->
    {config,
        strip_trailing_slash(Base_url),
        {some, {Secret, Org_id}},
        none,
        false,
        fun generated_holder/0}.

-file("src/ores_locks_and_leases/fiducia.gleam", 52).
?DOC(" A public edge or load-balancer endpoint authenticated with an API key.\n").
-spec bearer(binary(), binary()) -> config().
bearer(Base_url, Api_key) ->
    {config,
        strip_trailing_slash(Base_url),
        none,
        {some, Api_key},
        false,
        fun generated_holder/0}.

-file("src/ores_locks_and_leases/fiducia.gleam", 189).
-spec field_bool(gleam@dynamic:dynamic_(), binary()) -> boolean().
field_bool(Output, Name) ->
    _pipe = gleam@dynamic@decode:run(
        Output,
        gleam@dynamic@decode:at(
            [Name],
            {decoder, fun gleam@dynamic@decode:decode_bool/1}
        )
    ),
    gleam@result:unwrap(_pipe, false).

-file("src/ores_locks_and_leases/fiducia.gleam", 87).
?DOC(" Why a credential must not be sent to `base_url`, if it must not.\n").
-spec cleartext_refusal(binary(), boolean(), boolean()) -> gleam@option:option(binary()).
cleartext_refusal(Base_url, Has_credential, Allow) ->
    case (Has_credential andalso not Allow) andalso gleam_stdlib:string_starts_with(
        Base_url,
        <<"http://"/utf8>>
    ) of
        false ->
            none;

        true ->
            Host = begin
                _pipe = Base_url,
                _pipe@1 = gleam@string:drop_start(_pipe, 7),
                _pipe@2 = gleam@string:split_once(_pipe@1, <<"/"/utf8>>),
                _pipe@3 = gleam@result:map(
                    _pipe@2,
                    fun(Pair) -> erlang:element(1, Pair) end
                ),
                _pipe@4 = gleam@result:unwrap(
                    _pipe@3,
                    gleam@string:drop_start(Base_url, 7)
                ),
                _pipe@5 = gleam@string:split_once(_pipe@4, <<":"/utf8>>),
                _pipe@6 = gleam@result:map(
                    _pipe@5,
                    fun(Pair@1) -> erlang:element(1, Pair@1) end
                ),
                gleam@result:unwrap(
                    _pipe@6,
                    gleam@string:drop_start(Base_url, 7)
                )
            end,
            Local = ((((((Host =:= <<"localhost"/utf8>>) orelse (Host =:= <<"127.0.0.1"/utf8>>))
            orelse (Host =:= <<"[::1]"/utf8>>))
            orelse gleam_stdlib:string_ends_with(Host, <<".svc"/utf8>>))
            orelse gleam_stdlib:string_ends_with(
                Host,
                <<".cluster.local"/utf8>>
            ))
            orelse gleam_stdlib:string_ends_with(Host, <<".internal"/utf8>>))
            orelse gleam_stdlib:string_ends_with(Host, <<".local"/utf8>>),
            case Local of
                true ->
                    none;

                false ->
                    {some,
                        <<<<"fiducia: refusing to send a credential over cleartext http to \""/utf8,
                                Host/binary>>/binary,
                            "\"; use https or allow_cleartext_internal"/utf8>>}
            end
    end.

-file("src/ores_locks_and_leases/fiducia.gleam", 125).
-spec post(config(), binary(), gleam@json:json()) -> {ok,
        gleam@dynamic:dynamic_()} |
    {error, binary()}.
post(Config, Path, Body) ->
    Has_credential = gleam@option:is_some(erlang:element(3, Config)) orelse gleam@option:is_some(
        erlang:element(4, Config)
    ),
    gleam@result:'try'(
        case cleartext_refusal(
            erlang:element(2, Config),
            Has_credential,
            erlang:element(5, Config)
        ) of
            {some, Refusal} ->
                {error, Refusal};

            none ->
                {ok, nil}
        end,
        fun(_) ->
            gleam@result:'try'(
                begin
                    _pipe = gleam@http@request:to(
                        <<(erlang:element(2, Config))/binary, Path/binary>>
                    ),
                    gleam@result:map_error(
                        _pipe,
                        fun(_) ->
                            <<"fiducia: invalid base url "/utf8,
                                (erlang:element(2, Config))/binary>>
                        end
                    )
                end,
                fun(Req) ->
                    Req@1 = begin
                        _pipe@1 = Req,
                        _pipe@2 = gleam@http@request:set_method(_pipe@1, post),
                        _pipe@3 = gleam@http@request:set_header(
                            _pipe@2,
                            <<"content-type"/utf8>>,
                            <<"application/json"/utf8>>
                        ),
                        gleam@http@request:set_body(
                            _pipe@3,
                            gleam@json:to_string(Body)
                        )
                    end,
                    Req@2 = case erlang:element(3, Config) of
                        {some, {Secret, Org_id}} ->
                            _pipe@4 = Req@1,
                            _pipe@5 = gleam@http@request:set_header(
                                _pipe@4,
                                <<"x-fiducia-internal-auth"/utf8>>,
                                Secret
                            ),
                            gleam@http@request:set_header(
                                _pipe@5,
                                <<"x-fiducia-org-id"/utf8>>,
                                Org_id
                            );

                        none ->
                            Req@1
                    end,
                    Req@3 = case erlang:element(4, Config) of
                        {some, Api_key} ->
                            gleam@http@request:set_header(
                                Req@2,
                                <<"authorization"/utf8>>,
                                <<"Bearer "/utf8, Api_key/binary>>
                            );

                        none ->
                            Req@2
                    end,
                    gleam@result:'try'(
                        begin
                            _pipe@6 = gleam@httpc:send(Req@3),
                            gleam@result:map_error(
                                _pipe@6,
                                fun(Error) ->
                                    <<"fiducia: transport: "/utf8,
                                        (gleam@string:inspect(Error))/binary>>
                                end
                            )
                        end,
                        fun(Resp) -> case erlang:element(2, Resp) >= 300 of
                                true ->
                                    {error,
                                        <<<<<<"fiducia: HTTP "/utf8,
                                                    (erlang:integer_to_binary(
                                                        erlang:element(2, Resp)
                                                    ))/binary>>/binary,
                                                ": "/utf8>>/binary,
                                            (erlang:element(4, Resp))/binary>>};

                                false ->
                                    Decoder = begin
                                        gleam@dynamic@decode:subfield(
                                            [<<"result"/utf8>>,
                                                <<"output"/utf8>>],
                                            {decoder,
                                                fun gleam@dynamic@decode:decode_dynamic/1},
                                            fun(Output) ->
                                                gleam@dynamic@decode:success(
                                                    Output
                                                )
                                            end
                                        )
                                    end,
                                    _pipe@7 = gleam@json:parse(
                                        erlang:element(4, Resp),
                                        Decoder
                                    ),
                                    gleam@result:map_error(
                                        _pipe@7,
                                        fun(Error@1) ->
                                            <<"fiducia: malformed response: "/utf8,
                                                (gleam@string:inspect(Error@1))/binary>>
                                        end
                                    )
                            end end
                    )
                end
            )
        end
    ).

-file("src/ores_locks_and_leases/fiducia.gleam", 305).
-spec release(config(), ores_locks_and_leases:lease_grant()) -> {ok, boolean()} |
    {error, ores_locks_and_leases:lock_error()}.
release(Config, Grant) ->
    Body = gleam@json:object(
        [{<<"key"/utf8>>,
                gleam@json:string(
                    ores_locks_and_leases:key_to_string(
                        erlang:element(2, Grant)
                    )
                )},
            {<<"holder"/utf8>>, gleam@json:string(erlang:element(3, Grant))},
            {<<"fencing_token"/utf8>>, gleam@json:int(erlang:element(4, Grant))}]
    ),
    _pipe = post(Config, <<"/v1/locks/release"/utf8>>, Body),
    _pipe@1 = gleam@result:map(
        _pipe,
        fun(_capture) -> field_bool(_capture, <<"released"/utf8>>) end
    ),
    gleam@result:map_error(
        _pipe@1,
        fun(Message) ->
            ores_locks_and_leases:tag_step(
                ores_locks_and_leases:transport_error(
                    erlang:element(2, Grant),
                    Message
                ),
                fiducia_release
            )
        end
    ).

-file("src/ores_locks_and_leases/fiducia.gleam", 193).
-spec field_int(gleam@dynamic:dynamic_(), binary()) -> gleam@option:option(integer()).
field_int(Output, Name) ->
    _pipe = gleam@dynamic@decode:run(
        Output,
        gleam@dynamic@decode:at(
            [Name],
            {decoder, fun gleam@dynamic@decode:decode_int/1}
        )
    ),
    gleam@option:from_result(_pipe).

-file("src/ores_locks_and_leases/fiducia.gleam", 270).
?DOC(
    " `renewed: false` is lost fenced authority: fiducia has already reaped the\n"
    " grant and may have promoted another holder.\n"
).
-spec renew(config(), ores_locks_and_leases:lease_grant(), integer()) -> {ok,
        ores_locks_and_leases:lease_grant()} |
    {error, ores_locks_and_leases:lock_error()}.
renew(Config, Grant, Ttl_ms) ->
    Body = gleam@json:object(
        [{<<"key"/utf8>>,
                gleam@json:string(
                    ores_locks_and_leases:key_to_string(
                        erlang:element(2, Grant)
                    )
                )},
            {<<"holder"/utf8>>, gleam@json:string(erlang:element(3, Grant))},
            {<<"fencing_token"/utf8>>, gleam@json:int(erlang:element(4, Grant))},
            {<<"ttl_ms"/utf8>>, gleam@json:int(Ttl_ms)}]
    ),
    gleam@result:'try'(
        begin
            _pipe = post(Config, <<"/v1/locks/renew"/utf8>>, Body),
            gleam@result:map_error(
                _pipe,
                fun(_capture) ->
                    ores_locks_and_leases:transport_error(
                        erlang:element(2, Grant),
                        _capture
                    )
                end
            )
        end,
        fun(Output) -> case field_bool(Output, <<"renewed"/utf8>>) of
                false ->
                    {error,
                        {lock_error,
                            lost_lease,
                            erlang:element(2, Grant),
                            none,
                            <<"fiducia: lock renewal lost fenced authority"/utf8>>}};

                true ->
                    {ok,
                        {lease_grant,
                            erlang:element(2, Grant),
                            erlang:element(3, Grant),
                            erlang:element(4, Grant),
                            field_int(Output, <<"lease_expires_ms"/utf8>>),
                            Ttl_ms}}
            end end
    ).

-file("src/ores_locks_and_leases/fiducia.gleam", 204).
-spec erlang_monotonic_ms() -> integer().
erlang_monotonic_ms() ->
    erlang:monotonic_time() div 1000000.

-file("src/ores_locks_and_leases/fiducia.gleam", 197).
-spec now_ms() -> integer().
now_ms() ->
    erlang_monotonic_ms().

-file("src/ores_locks_and_leases/fiducia.gleam", 219).
-spec poll_acquire(
    config(),
    ores_locks_and_leases:lock_key(),
    ores_locks_and_leases:acquire_options(),
    boolean(),
    binary(),
    integer()
) -> {ok, ores_locks_and_leases:lease_grant()} |
    {error, ores_locks_and_leases:lock_error()}.
poll_acquire(Config, Key, Opts, Wait, Holder, Started_ms) ->
    Body = gleam@json:object(
        [{<<"key"/utf8>>,
                gleam@json:string(ores_locks_and_leases:key_to_string(Key))},
            {<<"holder"/utf8>>, gleam@json:string(Holder)},
            {<<"ttl_ms"/utf8>>, gleam@json:int(erlang:element(2, Opts))}]
    ),
    gleam@result:'try'(
        begin
            _pipe = post(Config, <<"/v1/locks/acquire"/utf8>>, Body),
            gleam@result:map_error(
                _pipe,
                fun(_capture) ->
                    ores_locks_and_leases:transport_error(Key, _capture)
                end
            )
        end,
        fun(Output) ->
            case {field_bool(Output, <<"acquired"/utf8>>),
                field_int(Output, <<"fencing_token"/utf8>>)} of
                {true, {some, Fencing_token}} ->
                    {ok,
                        {lease_grant,
                            Key,
                            Holder,
                            Fencing_token,
                            field_int(Output, <<"lease_expires_ms"/utf8>>),
                            erlang:element(2, Opts)}};

                {true, none} ->
                    {error,
                        ores_locks_and_leases:transport_error(
                            Key,
                            <<"fiducia: acquired without a fencing token"/utf8>>
                        )};

                {false, _} ->
                    case Wait of
                        false ->
                            {error,
                                ores_locks_and_leases:contention(
                                    Key,
                                    fiducia_try_acquire
                                )};

                        true ->
                            Waited = now_ms() - Started_ms,
                            case (Waited + erlang:element(4, Opts)) > erlang:element(
                                3,
                                Opts
                            ) of
                                true ->
                                    {error,
                                        ores_locks_and_leases:timeout(
                                            Key,
                                            fiducia_acquire,
                                            Waited
                                        )};

                                false ->
                                    gleam_erlang_ffi:sleep(
                                        erlang:element(4, Opts)
                                    ),
                                    poll_acquire(
                                        Config,
                                        Key,
                                        Opts,
                                        Wait,
                                        Holder,
                                        Started_ms
                                    )
                            end
                    end
            end
        end
    ).

-file("src/ores_locks_and_leases/fiducia.gleam", 209).
-spec acquire(
    config(),
    ores_locks_and_leases:lock_key(),
    ores_locks_and_leases:acquire_options(),
    boolean()
) -> {ok, ores_locks_and_leases:lease_grant()} |
    {error, ores_locks_and_leases:lock_error()}.
acquire(Config, Key, Opts, Wait) ->
    Holder = ores_locks_and_leases:holder_or(Opts, erlang:element(6, Config)),
    poll_acquire(Config, Key, Opts, Wait, Holder, now_ms()).

-file("src/ores_locks_and_leases/fiducia.gleam", 70).
?DOC(" A `Lease` whose three verbs call the node described by `config`.\n").
-spec lease(config()) -> ores_locks_and_leases:lease().
lease(Config) ->
    {lease,
        fun(Key, Opts, Wait) -> acquire(Config, Key, Opts, Wait) end,
        fun(Grant, Ttl_ms) -> renew(Config, Grant, Ttl_ms) end,
        fun(Grant@1) -> release(Config, Grant@1) end}.
