%%%===================================================================
%%% Unit Tests for rebar3_openapi_parser
%%%===================================================================
%%% This module contains unit tests for the rebar3_openapi_parser module,
%%% focusing on extracting types, routes, and contracts from Erlang handler files.
%%%===================================================================
%%%
%%% Test Progress:
%%% [✅] Test 1: extract_types_from_handler_test - PASSED
%%%
%%% Note: trails/0 is now called directly at runtime instead of parsing,
%%% so extract_trails tests have been removed.
%%%
%%% ALL PARSER TESTS COMPLETE: 1/1 PASSED ✓
%%%===================================================================

%%%===================================================================
%%% Test Cases
%%%===================================================================

-module(rebar3_openapi_parser_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test: Extract types from handler with -type attributes
%%%===================================================================

%% Test: Extract types from handler file
extract_types_from_handler_test() ->
    %% Use the trails_simple_handler fixture
    FixturePath = "test/fixtures/trails_simple_handler.erl",

    %% Execute: Parse the file and extract types
    {ok, Forms} = epp:parse_file(FixturePath, [{includes, []}, {macros, []}]),
    Types = rebar3_openapi_parser:extract_types(Forms),

    %% Assert: Should extract 2 types (user_id, user)
    ?assertEqual(2, length(Types)),

    %% Should have correct type names
    TypeNames = [Name || {Name, _} <- Types],
    ?assert(lists:member(user_id, TypeNames)),
    ?assert(lists:member(user, TypeNames)),

    %% Check user_id type is binary
    {user_id, UserIdType} = lists:keyfind(user_id, 1, Types),
    ?assertMatch({type, _, binary, []}, UserIdType),

    %% Check user is a map
    {user, UserType} = lists:keyfind(user, 1, Types),
    ?assertMatch({type, _, map, _}, UserType).
