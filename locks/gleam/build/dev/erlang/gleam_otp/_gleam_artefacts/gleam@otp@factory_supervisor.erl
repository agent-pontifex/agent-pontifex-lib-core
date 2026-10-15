-module(gleam@otp@factory_supervisor).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/gleam/otp/factory_supervisor.gleam").
-export([get_by_name/1, worker_child/1, supervisor_child/1, named/2, restart_tolerance/3, timeout/2, restart_strategy/2, start/1, supervised/1, start_child/2, count_children/1, init/1, start_child_callback/2]).
-export_type([supervisor/2, supervisor_handle/0, message/2, builder/2, erlang_start_flags/0, erlang_supervisor_name/2, strategy/0, erlang_start_flag/1, erlang_child_spec/0, erlang_child_spec_property/2, timeout_/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

?MODULEDOC(
    " A supervisor where child processes are started dynamically from a\n"
    " pre-specified template, so new processes can be created as needed\n"
    " while the program is running.\n"
    "\n"
    " When the supervisor is shut down it shuts down all its children\n"
    " concurrently and in no specified order.\n"
    "\n"
    " For further detail see the Erlang documentation, particularly the parts\n"
    " about the `simple_one_for_one` restart strategy, which is the Erlang\n"
    " equivilent of the factory supervisor.\n"
    " <https://www.erlang.org/doc/apps/stdlib/supervisor.html>.\n"
    "\n"
    " ## Usage\n"
    "\n"
    " Add the factory supervisor to your supervision tree using the `supervised`\n"
    " function and a name created at the start of the program. The `new`\n"
    " function takes a \"template function\", which is a function that takes one\n"
    " argument and starts a linked child process.\n"
    "\n"
    " You most likely want to give the factory supervisor a name, and to pass\n"
    " that name to any other processes that will want to cause new child\n"
    " processes to be started under the factory supervisor. In this example a\n"
    " web server is used.\n"
    "\n"
    " ```gleam\n"
    " import gleam/erlang/process.{type Name}\n"
    " import gleam/otp/actor.{type StartResult}\n"
    " import gleam/otp/factory_supervisor as factory\n"
    " import gleam/otp/static_supervisor as supervisor\n"
    " import my_app\n"
    " \n"
    " /// This function starts the application's supervision tree.\n"
    " ///\n"
    " /// It takes a name as an argument that is used by the factory supervisor.\n"
    " ///\n"
    " pub fn start_supervision_tree(reporters_name: Name(_)) -> StartResult(_) {\n"
    "   // Define a named factory supervisor that can create new child processes\n"
    "   // using the `my_app.start_reporter_actor` function, which is defined\n"
    "   // elsewhere in the program.\n"
    "   let reporter_factory_supervisor =\n"
    "     factory.worker_child(my_app.start_reporter_actor)\n"
    "     |> factory.named(reporters_name)\n"
    "     |> factory.supervised\n"
    " \n"
    "   // This web server process takes the name, so it can contact the factory\n"
    "   // supervisor to command it to start new processes as needed.\n"
    "   let web_server = my_app.supervised_web_server(reporters_name)\n"
    " \n"
    "   // Create the top-level static supervisor with the supervisor and web\n"
    "   // server as its children\n"
    "   supervisor.new(supervisor.RestForOne)\n"
    "   |> supervisor.add(reporter_factory_supervisor)\n"
    "   |> supervisor.add(web_server)\n"
    "   |> supervisor.start\n"
    " }\n"
    " ```\n"
    "\n"
    " Any process with the name of the factory supervisor can use the\n"
    " `get_by_name` function to get a reference to the supervisor, and then use\n"
    " the `start_child` function to have it start new child processes.\n"
    "\n"
    " Remember! Each process name created with `process.new_name` is unique.\n"
    " Two names created by calling the function twice are different names, even\n"
    " if the same string is given as an argument. You must create the name value\n"
    " at the start of your program and then pass it down into application code\n"
    " and library code that uses names.\n"
    "\n"
    " ```gleam\n"
    " import gleam/http/request.{type Request}\n"
    " import gleam/http/response.{type Response}\n"
    " import gleam/otp/factory_supervisor\n"
    " import my_app\n"
    " \n"
    " /// In our example this function is called each time a HTTP request is \n"
    " /// received by the web server.\n"
    " pub fn handle_request(req: Request(_), reporters: Name(_)) -> Response(_) {\n"
    "   // Get a reference to the supervisor using the name\n"
    "   let supervisor = factory_supervisor.get_by_name(reporters)\n"
    " \n"
    "   // Start a new child process under the supervisor, passing the request path \n"
    "   // to use as the argument for the child-starting template function.\n"
    "   let start_result = factory_supervisor.start_child(supervisor, request.path)\n"
    " \n"
    "   // A response is sent to the HTTP client.\n"
    "   // The child starting template function returns a result, with the error case\n"
    "   // being used when children fail to start. Because of this the `start_child`\n"
    "   // function also returns a result, so it must be handled too.\n"
    "   case start_result {\n"
    "     Ok(_) -> response.new(200)\n"
    "     Error(_) -> response.new(500)\n"
    "   }\n"
    " }\n"
    " ```\n"
).

-opaque supervisor(FZZ, GAA) :: {supervisor, supervisor_handle()} |
    {gleam_phantom, FZZ, GAA}.

-type supervisor_handle() :: any().

-type message(GAB, GAC) :: any() | {gleam_phantom, GAB, GAC}.

-opaque builder(GAD, GAE) :: {builder,
        gleam@otp@supervision:child_type(),
        fun((GAD) -> {ok, gleam@otp@actor:started(GAE)} |
            {error, gleam@otp@actor:start_error()}),
        gleam@otp@supervision:restart(),
        integer(),
        integer(),
        gleam@option:option(gleam@erlang@process:name(message(GAD, GAE)))}.

-type erlang_start_flags() :: any().

-type erlang_supervisor_name(GAF, GAG) :: {local,
        gleam@erlang@process:name(message(GAF, GAG))}.

-type strategy() :: simple_one_for_one.

-type erlang_start_flag(GAH) :: {strategy, strategy()} |
    {intensity, integer()} |
    {period, integer()} |
    {gleam_phantom, GAH}.

-type erlang_child_spec() :: any().

-type erlang_child_spec_property(GAI, GAJ) :: {id, integer()} |
    {start,
        {gleam@erlang@atom:atom_(),
            gleam@erlang@atom:atom_(),
            list(fun((GAI) -> {ok, gleam@otp@actor:started(GAJ)} |
                {error, gleam@otp@actor:start_error()}))}} |
    {restart, gleam@otp@supervision:restart()} |
    {type, gleam@erlang@atom:atom_()} |
    {shutdown, timeout_()}.

-type timeout_() :: any().

-file("src/gleam/otp/factory_supervisor.gleam", 151).
?DOC(
    " Get a reference to a supervisor using its registered name.\n"
    "\n"
    " If no supervisor has been started using this name then functions\n"
    " using this reference will fail.\n"
    "\n"
    " # Panics\n"
    "\n"
    " Functions using the `Supervisor` reference returned by this function\n"
    " will panic if there is no factory supervisor registered with the name\n"
    " when they are called. Always make sure your supervisors are themselves\n"
    " supervised.\n"
).
-spec get_by_name(gleam@erlang@process:name(message(GAP, GAQ))) -> supervisor(GAP, GAQ).
get_by_name(Name) ->
    {supervisor, gleam_otp_external:identity(Name)}.

-file("src/gleam/otp/factory_supervisor.gleam", 178).
?DOC(
    " Configure a supervisor with a child-starting template function.\n"
    "\n"
    " You should use this unless the child processes are also supervisors.\n"
    "\n"
    " The default shutdown timeout is 5000ms. This can be changed with the\n"
    " `timeout` function.\n"
).
-spec worker_child(
    fun((GAW) -> {ok, gleam@otp@actor:started(GAX)} |
        {error, gleam@otp@actor:start_error()})
) -> builder(GAW, GAX).
worker_child(Template) ->
    {builder, {worker, 5000}, Template, transient, 2, 5, none}.

-file("src/gleam/otp/factory_supervisor.gleam", 199).
?DOC(
    " Configure a supervisor with a template that will start children that are\n"
    " also supervisors.\n"
    "\n"
    " You should only use this if the child processes are also supervisors.\n"
    "\n"
    " Supervisor children have an unlimited amount of time to shutdown, there is\n"
    " no timeout.\n"
).
-spec supervisor_child(
    fun((GBB) -> {ok, gleam@otp@actor:started(GBC)} |
        {error, gleam@otp@actor:start_error()})
) -> builder(GBB, GBC).
supervisor_child(Template) ->
    {builder, supervisor, Template, transient, 2, 5, none}.

-file("src/gleam/otp/factory_supervisor.gleam", 220).
?DOC(
    " Provide a name for the supervisor to be registered with when started,\n"
    " enabling it be more easily contacted by other processes. This is useful for\n"
    " enabling processes that can take over from an older one that has exited due\n"
    " to a failure.\n"
    "\n"
    " If the name is already registered to another process then the factory\n"
    " supervisor will fail to start.\n"
).
-spec named(builder(GBG, GBH), gleam@erlang@process:name(message(GBG, GBH))) -> builder(GBG, GBH).
named(Builder, Name) ->
    {builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        erlang:element(5, Builder),
        erlang:element(6, Builder),
        {some, Name}}.

-file("src/gleam/otp/factory_supervisor.gleam", 238).
?DOC(
    " To prevent a supervisor from getting into an infinite loop of child\n"
    " process terminations and restarts, a maximum restart tolerance is\n"
    " defined using two integer values specified with keys intensity and\n"
    " period in the above map. Assuming the values MaxR for intensity and MaxT\n"
    " for period, then, if more than MaxR restarts occur within MaxT seconds,\n"
    " the supervisor terminates all child processes and then itself. The\n"
    " termination reason for the supervisor itself in that case will be\n"
    " shutdown. \n"
    "\n"
    " Intensity defaults to 2 and period defaults to 5.\n"
).
-spec restart_tolerance(builder(GBP, GBQ), integer(), integer()) -> builder(GBP, GBQ).
restart_tolerance(Builder, Intensity, Period) ->
    {builder,
        erlang:element(2, Builder),
        erlang:element(3, Builder),
        erlang:element(4, Builder),
        Intensity,
        Period,
        erlang:element(7, Builder)}.

-file("src/gleam/otp/factory_supervisor.gleam", 253).
?DOC(
    " Configure the amount of milliseconds a child has to shut down before\n"
    " being brutal killed by the supervisor.\n"
    "\n"
    " If not set the default for a child is 5000ms.\n"
    "\n"
    " This will be ignored if the child is a supervisor itself.\n"
).
-spec timeout(builder(GBV, GBW), integer()) -> builder(GBV, GBW).
timeout(Builder, Ms) ->
    case erlang:element(2, Builder) of
        {worker, _} ->
            {builder,
                {worker, Ms},
                erlang:element(3, Builder),
                erlang:element(4, Builder),
                erlang:element(5, Builder),
                erlang:element(6, Builder),
                erlang:element(7, Builder)};

        _ ->
            Builder
    end.

-file("src/gleam/otp/factory_supervisor.gleam", 270).
?DOC(
    " Configure the strategy for restarting children when they exit. See the\n"
    " documentation for the `supervision.Restart` for details.\n"
    "\n"
    " If not set the default strategy is `supervision.Transient`, so children\n"
    " will be restarted if they terminate abnormally.\n"
).
-spec restart_strategy(builder(GCB, GCC), gleam@otp@supervision:restart()) -> builder(GCB, GCC).
restart_strategy(Builder, Restart_strategy) ->
    case erlang:element(2, Builder) of
        {worker, _} ->
            {builder,
                erlang:element(2, Builder),
                erlang:element(3, Builder),
                Restart_strategy,
                erlang:element(5, Builder),
                erlang:element(6, Builder),
                erlang:element(7, Builder)};

        _ ->
            Builder
    end.

-file("src/gleam/otp/factory_supervisor.gleam", 289).
?DOC(
    " Start a new supervisor process with the configuration and child template\n"
    " specified within the builder.\n"
    "\n"
    " Typically you would use the `supervised` function to add your supervisor to\n"
    " a supervision tree instead of using this function directly.\n"
    "\n"
    " The supervisor will be linked to the parent process that calls this\n"
    " function.\n"
).
-spec start(builder(GCH, GCI)) -> {ok,
        gleam@otp@actor:started(supervisor(GCH, GCI))} |
    {error, gleam@otp@actor:start_error()}.
start(Builder) ->
    Flags = maps:from_list(
        [{strategy, simple_one_for_one},
            {intensity, erlang:element(5, Builder)},
            {period, erlang:element(6, Builder)}]
    ),
    Module_atom = erlang:binary_to_atom(<<"gleam@otp@factory_supervisor"/utf8>>),
    Function_atom = erlang:binary_to_atom(<<"start_child_callback"/utf8>>),
    Mfa = {Module_atom, Function_atom, [erlang:element(3, Builder)]},
    {Type_, Shutdown} = case erlang:element(2, Builder) of
        supervisor ->
            {erlang:binary_to_atom(<<"supervisor"/utf8>>),
                gleam_otp_external:make_timeout(-1)};

        {worker, Ms} ->
            {erlang:binary_to_atom(<<"worker"/utf8>>),
                gleam_otp_external:make_timeout(Ms)}
    end,
    Child = maps:from_list(
        [{id, 0},
            {start, Mfa},
            {restart, erlang:element(4, Builder)},
            {type, Type_},
            {shutdown, Shutdown}]
    ),
    Configuration = {Flags, [Child]},
    Start_result = case erlang:element(7, Builder) of
        none ->
            supervisor:start_link(Module_atom, Configuration);

        {some, Name} ->
            supervisor:start_link({local, Name}, Module_atom, Configuration)
    end,
    case Start_result of
        {ok, Pid} ->
            Supervisor = {supervisor, gleam_otp_external:identity(Pid)},
            {ok, {started, Pid, Supervisor}};

        {error, Error} ->
            {error, gleam_otp_external:convert_erlang_start_error(Error)}
    end.

-file("src/gleam/otp/factory_supervisor.gleam", 405).
?DOC(
    " Create a `ChildSpecification` that adds this supervisor as the child of\n"
    " another, making it fault tolerant and part of the application's supervision\n"
    " tree. You should prefer this to starting unsupervised supervisors with the\n"
    " `start` function.\n"
    "\n"
    " If any child fails to start the supervisor first terminates all already\n"
    " started child processes with reason shutdown and then terminate itself and\n"
    " returns an error.\n"
).
-spec supervised(builder(GDG, GDH)) -> gleam@otp@supervision:child_specification(supervisor(GDG, GDH)).
supervised(Builder) ->
    gleam@otp@supervision:supervisor(fun() -> start(Builder) end).

-file("src/gleam/otp/factory_supervisor.gleam", 414).
?DOC(
    " Start a new child using the supervisor's child template and the given\n"
    " argument. The start result of the child is returned.\n"
).
-spec start_child(supervisor(GDN, GDO), GDN) -> {ok,
        gleam@otp@actor:started(GDO)} |
    {error, gleam@otp@actor:start_error()}.
start_child(Supervisor, Argument) ->
    case supervisor:start_child(erlang:element(2, Supervisor), [Argument]) of
        {ok, Pid, Data} ->
            {ok, {started, Pid, Data}};

        {error, Reason} ->
            {error, Reason}
    end.

-file("src/gleam/otp/factory_supervisor.gleam", 432).
?DOC(
    " Returns the number of children under the supervisor.\n"
    "\n"
    " This function runs the same speed regardless of how many children the\n"
    " supervisor has.\n"
    "\n"
    " If the supervisor is heavily overloaded this number could be inaccurate due\n"
    " to the supervisor still processing the termination of some of its children.\n"
).
-spec count_children(supervisor(any(), any())) -> integer().
count_children(Factory) ->
    _pipe = supervisor:count_children(erlang:element(2, Factory)),
    _pipe@1 = gleam@list:key_find(
        _pipe,
        erlang:binary_to_atom(<<"active"/utf8>>)
    ),
    gleam@result:unwrap(_pipe@1, 0).

-file("src/gleam/otp/factory_supervisor.gleam", 449).
?DOC(false).
-spec init(gleam@dynamic:dynamic_()) -> {ok, gleam@dynamic:dynamic_()} |
    {error, any()}.
init(Start_data) ->
    {ok, Start_data}.

-file("src/gleam/otp/factory_supervisor.gleam", 455).
?DOC(false).
-spec start_child_callback(
    fun((GEG) -> {ok, gleam@otp@actor:started(GEH)} |
        {error, gleam@otp@actor:start_error()}),
    GEG
) -> gleam@otp@internal@result2:result2(gleam@erlang@process:pid_(), GEH, gleam@otp@actor:start_error()).
start_child_callback(Start, Argument) ->
    case Start(Argument) of
        {ok, Started} ->
            {ok, erlang:element(2, Started), erlang:element(3, Started)};

        {error, Error} ->
            {error, Error}
    end.
