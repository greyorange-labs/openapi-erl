-module(rebar3_opapi).

-export([init/1]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    {ok, State1} = rebar3_opapi_prv_extract:init(State),
    {ok, State1}.
