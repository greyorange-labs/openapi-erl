%%%===================================================================
%%% Unit Tests for rebar3_opapi_parser
%%%===================================================================
%%% This module contains unit tests for the rebar3_opapi_parser module,
%%% focusing on extracting types, routes, and contracts from Erlang handler files.
%%%===================================================================
%%%
%%% Test Progress (REVISED for trails/0):
%%% [✅] Test 1: extract_trails_from_handler_test - PASSED 2025-01-15
%%% [✅] Test 2: extract_types_from_handler_test - PASSED 2025-01-15
%%% [✅] Test 3: extract_metadata_with_type_refs_test - PASSED 2025-01-15
%%%
%%% ALL PARSER TESTS COMPLETE: 3/3 PASSED ✓
%%%===================================================================

%%%===================================================================
%%% Test Cases
%%%===================================================================

-module(rebar3_opapi_parser_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test 1: Extract trails from handler with trails/0 callback
%%%===================================================================

%% Test 1: Extract trails from handler file
extract_trails_from_handler_test() ->
    %% Use the trails_simple_handler fixture
    FixturePath = "test/fixtures/trails_simple_handler.erl",

    %% Execute: Parse the file and extract trails
    {ok, Forms} = epp:parse_file(FixturePath, [{includes, []}, {macros, []}]),
    Trails = rebar3_opapi_parser:extract_trails(Forms),

    %% Assert: Should extract 2 trails
    ?assertEqual(2, length(Trails)),

    %% Check first trail (GET /api/users/:id)
    [Trail1, Trail2] = Trails,

    ?assertEqual(<<"/api/users/:id">>, maps:get(path, Trail1)),
    ?assertEqual(trails_simple_handler, maps:get(handler, Trail1)),

    %% Check metadata exists and has 'get' method
    Metadata1 = maps:get(metadata, Trail1),
    ?assert(maps:is_key(get, Metadata1)),

    GetMetadata = maps:get(get, Metadata1),
    ?assertEqual([<<"users">>], maps:get(tags, GetMetadata)),
    ?assertEqual(<<"Get user by ID">>, maps:get(description, GetMetadata)),

    %% Check parameters
    Parameters = maps:get(parameters, GetMetadata),
    ?assertEqual(1, length(Parameters)),
    [Param1] = Parameters,
    ?assertEqual(<<"id">>, maps:get(name, Param1)),
    ?assertEqual(<<"path">>, maps:get(in, Param1)),
    ?assertEqual(true, maps:get(required, Param1)),
    % Type reference!
    ?assertEqual(user_id, maps:get(schema, Param1)),

    %% Check second trail (POST /api/users)
    ?assertEqual(<<"/api/users">>, maps:get(path, Trail2)),
    ?assertEqual(trails_simple_handler, maps:get(handler, Trail2)),

    Metadata2 = maps:get(metadata, Trail2),
    ?assert(maps:is_key(post, Metadata2)),

    PostMetadata = maps:get(post, Metadata2),
    ?assertEqual([<<"users">>], maps:get(tags, PostMetadata)),

    %% Check requestBody
    RequestBody = maps:get(requestBody, PostMetadata),
    ?assertEqual(true, maps:get(required, RequestBody)),
    Content = maps:get(content, RequestBody),
    JsonContent = maps:get(<<"application/json">>, Content),
    % Type reference!
    ?assertEqual(user, maps:get(schema, JsonContent)).

%%%===================================================================
%%% Test 2: Extract types from handler with -type attributes
%%%===================================================================

%% Test 2: Extract types from handler file (verify with trails fixture)
extract_types_from_handler_test() ->
    %% Use the trails_simple_handler fixture
    FixturePath = "test/fixtures/trails_simple_handler.erl",

    %% Execute: Parse the file and extract types
    {ok, Forms} = epp:parse_file(FixturePath, [{includes, []}, {macros, []}]),
    Types = rebar3_opapi_parser:extract_types(Forms),

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
%%% Test 3: Extract metadata with type references
%%%===================================================================

%% Test 3: Verify that type references in metadata are preserved as atoms
extract_metadata_with_type_refs_test() ->
    %% Use the trails_simple_handler fixture
    FixturePath = "test/fixtures/trails_simple_handler.erl",

    %% Execute: Parse the file and extract trails
    {ok, Forms} = epp:parse_file(FixturePath, [{includes, []}, {macros, []}]),
    Trails = rebar3_opapi_parser:extract_trails(Forms),

    %% Get first trail
    [Trail1 | _] = Trails,
    Metadata = maps:get(metadata, Trail1),
    GetMetadata = maps:get(get, Metadata),

    %% Check that schema field contains atom type reference (not expanded yet)
    Parameters = maps:get(parameters, GetMetadata),
    [Param] = Parameters,
    Schema = maps:get(schema, Param),

    %% Assert: Schema should be an atom (type reference), not a map
    ?assert(is_atom(Schema)),
    ?assertEqual(user_id, Schema),

    %% Check response schema
    Responses = maps:get(responses, GetMetadata),
    Response200 = maps:get(<<"200">>, Responses),
    ResponseContent = maps:get(content, Response200),
    JsonContent = maps:get(<<"application/json">>, ResponseContent),
    ResponseSchema = maps:get(schema, JsonContent),

    %% Assert: Response schema should be an atom (type reference)
    ?assert(is_atom(ResponseSchema)),
    ?assertEqual(user, ResponseSchema).
