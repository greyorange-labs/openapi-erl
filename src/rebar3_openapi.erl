%%%-------------------------------------------------------------------
%%% @author amarBitMan <https://github.com/amarBitMan>
%%% @copyright (C) 2025, Grey Orange
%%%-------------------------------------------------------------------
-module(rebar3_openapi).

-moduledoc """
----------------------------------------------------------------------
rebar3 OpenAPI Plugin Entry Point

Registers the `openapi extract` provider with rebar3.
----------------------------------------------------------------------
""".

-export([init/1]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    rebar3_openapi_prv_extract:init(State).
