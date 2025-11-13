-module(rebar3_opapi).
-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, extract).
-define(DEPS, [compile]).

%%%===================================================================
%%% Provider Callbacks
%%%===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {bare, true},
        {deps, ?DEPS},
        {example, "rebar3 opapi extract --handler gm_common_http_handler --app butler_shared --output openapi.yaml"},
        {short_desc, "Extract OpenAPI 3.0.x documentation from Erlang handler modules"},
        {desc, "Extract OpenAPI 3.0.x documentation from Erlang handler modules"},
        {opts, [
            {handler, undefined, "handler", string, "Handler module name (required)"},
            {app, undefined, "app", string, "Application name (required)"},
            {output, undefined, "output", string, "Output file path (required)"}
        ]}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    rebar3_opapi_prv_extract:do(State).

-spec format_error(term()) -> iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

