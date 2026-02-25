%%%-------------------------------------------------------------------
%%% @author amarBitMan <https://github.com/amarBitMan>
%%% @copyright (C) 2025, Grey Orange
%%%-------------------------------------------------------------------
-module(rebar3_openapi_parser_tests).

-moduledoc """
----------------------------------------------------------------------
Unit Tests for rebar3_openapi_parser

Tests extraction of -type definitions, -type_meta attributes,
and remote type references from Erlang handler source files.
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

%%%===================================================================
%%% Test: Extract -type_meta attributes from parsed forms
%%%===================================================================

extract_type_meta_empty_test() ->
    %% No type_meta attributes → empty map
    Forms = [
        {attribute, 1, module, my_module},
        {attribute, 2, type, {user_id, {type, 2, binary, []}, []}}
    ],
    Result = rebar3_openapi_parser:extract_type_meta(Forms),
    ?assertEqual(#{}, Result).

extract_type_meta_single_test() ->
    %% Single -type_meta with description
    Forms = [
        {attribute, 1, module, my_module},
        {attribute, 2, type_meta, {user_id, #{description => <<"Unique user identifier">>}}},
        {attribute, 3, type, {user_id, {type, 3, binary, []}, []}}
    ],
    Result = rebar3_openapi_parser:extract_type_meta(Forms),
    ?assertEqual(#{user_id => #{description => <<"Unique user identifier">>}}, Result).

extract_type_meta_multiple_test() ->
    %% Multiple -type_meta attributes
    Forms = [
        {attribute, 1, module, my_module},
        {attribute, 2, type_meta, {user_id, #{description => <<"User ID">>, example => <<"usr_123">>}}},
        {attribute, 3, type, {user_id, {type, 3, binary, []}, []}},
        {attribute, 4, type_meta, {user_role, #{description => <<"Role">>, deprecated => true}}},
        {attribute, 5, type, {user_role, {type, 5, union, [{atom, 5, admin}, {atom, 5, user}]}, []}}
    ],
    Result = rebar3_openapi_parser:extract_type_meta(Forms),
    ?assertEqual(2, maps:size(Result)),
    ?assertEqual(#{description => <<"User ID">>, example => <<"usr_123">>}, maps:get(user_id, Result)),
    ?assertEqual(#{description => <<"Role">>, deprecated => true}, maps:get(user_role, Result)).

extract_type_meta_ignores_invalid_test() ->
    %% Non-matching forms should be ignored
    Forms = [
        {attribute, 1, module, my_module},
        %% Invalid: not a {TypeName, Map} tuple
        {attribute, 2, type_meta, just_an_atom},
        %% Invalid: metadata is not a map
        {attribute, 3, type_meta, {some_type, not_a_map}},
        %% Valid
        {attribute, 4, type_meta, {valid_type, #{description => <<"Valid">>}}}
    ],
    Result = rebar3_openapi_parser:extract_type_meta(Forms),
    ?assertEqual(1, maps:size(Result)),
    ?assertEqual(#{description => <<"Valid">>}, maps:get(valid_type, Result)).

extract_type_meta_from_handler_test() ->
    %% Parse actual fixture file with -type_meta attributes
    FixturePath = "test/fixtures/handler_with_type_meta.erl",
    {ok, Forms} = epp:parse_file(FixturePath, [{includes, []}, {macros, []}]),
    TypeMeta = rebar3_openapi_parser:extract_type_meta(Forms),

    %% Should extract 3 type_meta entries (user_id, user, user_role)
    ?assertEqual(3, maps:size(TypeMeta)),

    %% Check user_id metadata
    ?assert(maps:is_key(user_id, TypeMeta)),
    UserIdMeta = maps:get(user_id, TypeMeta),
    ?assertEqual(<<"Unique user identifier">>, maps:get(description, UserIdMeta)),
    ?assertEqual(<<"usr_abc123">>, maps:get(example, UserIdMeta)),

    %% Check user metadata
    ?assert(maps:is_key(user, TypeMeta)),
    UserMeta = maps:get(user, TypeMeta),
    ?assertEqual(<<"A user in the system">>, maps:get(description, UserMeta)),

    %% Check user_role metadata (deprecated)
    ?assert(maps:is_key(user_role, TypeMeta)),
    RoleMeta = maps:get(user_role, TypeMeta),
    ?assertEqual(<<"Role assigned to a user">>, maps:get(description, RoleMeta)),
    ?assertEqual(true, maps:get(deprecated, RoleMeta)),

    %% error_response has no -type_meta, should NOT be in the map
    ?assertNot(maps:is_key(error_response, TypeMeta)).
