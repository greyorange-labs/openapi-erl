%%%-------------------------------------------------------------------
%%% @author amarBitMan <https://github.com/amarBitMan>
%%% @copyright (C) 2025, Grey Orange
%%%-------------------------------------------------------------------
-module(rebar3_openapi_parser_tests).

-moduledoc """
----------------------------------------------------------------------
Unit Tests for rebar3_openapi_parser

Tests extraction of -type definitions and remote type references
from Erlang handler source files.
----------------------------------------------------------------------
""".
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

%%%===================================================================
%%% Test: Extract remote type references from type ASTs
%%%===================================================================

extract_remote_type_refs_empty_test() ->
    Types = [{my_type, {type, 1, binary, []}}],
    Refs = rebar3_openapi_parser:extract_remote_type_refs(Types),
    ?assertEqual([], Refs).

extract_remote_type_refs_basic_test() ->
    %% Type with a remote type reference: common_types:user_id()
    Types = [
        {my_type,
            {type, 1, map, [
                {type, 1, map_field_exact, [
                    {atom, 1, id},
                    {remote_type, 1, [{atom, 1, common_types}, {atom, 1, user_id}, []]}
                ]}
            ]}}
    ],
    Refs = rebar3_openapi_parser:extract_remote_type_refs(Types),
    ?assertEqual([{common_types, user_id}], Refs).

extract_remote_type_refs_skips_gm_type_test() ->
    %% gm_type references should be excluded
    Types = [
        {my_type,
            {type, 1, map, [
                {type, 1, map_field_exact, [
                    {atom, 1, email},
                    {remote_type, 1, [{atom, 1, gm_type}, {atom, 1, email}, []]}
                ]},
                {type, 1, map_field_exact, [
                    {atom, 1, id},
                    {remote_type, 1, [{atom, 1, shared_types}, {atom, 1, entity_id}, []]}
                ]}
            ]}}
    ],
    Refs = rebar3_openapi_parser:extract_remote_type_refs(Types),
    ?assertEqual([{shared_types, entity_id}], Refs).

extract_remote_type_refs_deduplicates_test() ->
    %% Same remote ref used in two types should appear once
    Types = [
        {type_a, {remote_type, 1, [{atom, 1, common}, {atom, 1, id}, []]}},
        {type_b, {remote_type, 1, [{atom, 1, common}, {atom, 1, id}, []]}}
    ],
    Refs = rebar3_openapi_parser:extract_remote_type_refs(Types),
    ?assertEqual([{common, id}], Refs).

extract_remote_type_refs_in_union_test() ->
    %% Remote refs inside union types
    Types = [
        {my_type,
            {type, 1, union, [
                {remote_type, 1, [{atom, 1, mod_a}, {atom, 1, type_a}, []]},
                {remote_type, 1, [{atom, 1, mod_b}, {atom, 1, type_b}, []]}
            ]}}
    ],
    Refs = rebar3_openapi_parser:extract_remote_type_refs(Types),
    ?assertEqual([{mod_a, type_a}, {mod_b, type_b}], Refs).
