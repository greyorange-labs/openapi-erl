-module(rebar3_openapi).

-export([init/1]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    {ok, State1} = rebar3_openapi_prv_extract:init(State),
    {ok, State2} = rebar3_openapi_prv_generate_handler:init(State1),
    {ok, State2}.
