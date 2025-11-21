-module(rebar3_openapi).

-export([init/1]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    rebar3_openapi_prv_extract:init(State).
