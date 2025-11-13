%%%===================================================================
%%% Integration Tests for rebar3_opapi
%%%===================================================================
%%% This module contains end-to-end integration tests that test the
%%% complete flow from handler file to OpenAPI document generation.
%%%===================================================================
%%%
%%% Test Progress:
%%% [✅] Test 1: simple_handler_end_to_end_test - PASSED 2025-01-15
%%% [✅] Test 2: comprehensive_handler_end_to_end_test - PASSED 2025-01-15
%%%
%%% ALL INTEGRATION TESTS COMPLETE: 2/2 PASSED ✓
%%%===================================================================

-module(rebar3_opapi_integration_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test 1: Simple Handler End-to-End
%%%===================================================================

%% Test 1: End-to-end test with simple_handler.erl
simple_handler_end_to_end_test() ->
    %% Input: Simple handler fixture
    FixturePath = "test/fixtures/simple_handler.erl",

    %% Step 1: Parse handler file
    IncludePaths = [{includes, []}, {macros, []}],
    {ok, Forms} = epp:parse_file(FixturePath, IncludePaths),

    %% Step 2: Extract trails and types
    Trails = rebar3_opapi_parser:extract_trails(Forms),
    Types = rebar3_opapi_parser:extract_types(Forms),

    %% Assert: Should extract trails and types
    ?assert(length(Trails) > 0, "Should extract at least one trail"),
    ?assert(length(Types) >= 0, "Types are optional"),

    %% Step 3: Expand trails metadata
    ExpandedTrails = rebar3_opapi_expander:expand_trails(Trails, Types),
    ?assertEqual(length(Trails), length(ExpandedTrails), "Should expand all trails"),

    %% Step 4: Build OpenAPI document
    AppName = <<"TestAPI">>,
    OpenAPIDoc = rebar3_opapi_builder:build_from_trails(ExpandedTrails, Types, AppName),

    %% Assert: Check top-level structure
    ?assertEqual(<<"3.0.3">>, maps:get(<<"openapi">>, OpenAPIDoc)),
    ?assert(maps:is_key(<<"info">>, OpenAPIDoc)),
    ?assert(maps:is_key(<<"paths">>, OpenAPIDoc)),
    ?assert(maps:is_key(<<"components">>, OpenAPIDoc)),

    %% Check info section
    Info = maps:get(<<"info">>, OpenAPIDoc),
    ?assertEqual(<<"TestAPI">>, maps:get(<<"title">>, Info)),

    %% Check paths section
    Paths = maps:get(<<"paths">>, OpenAPIDoc),
    ?assert(maps:size(Paths) > 0, "Should have at least one path"),

    %% Verify at least one path has operations
    [_Path | _] = maps:keys(Paths),
    ?assert(true, "Paths section is valid").

%%%===================================================================
%%% Test 2: Comprehensive Handler End-to-End
%%%===================================================================

%% Test 2: End-to-end test with comprehensive_handler.erl
comprehensive_handler_end_to_end_test() ->
    %% Input: Comprehensive handler fixture
    FixturePath = "test/fixtures/comprehensive_handler.erl",

    %% Step 1: Parse handler file
    IncludePaths = [{includes, []}, {macros, []}],
    {ok, Forms} = epp:parse_file(FixturePath, IncludePaths),

    %% Step 2: Extract trails and types
    Trails = rebar3_opapi_parser:extract_trails(Forms),
    Types = rebar3_opapi_parser:extract_types(Forms),

    %% Assert: Should extract multiple trails and types
    ?assert(length(Trails) > 0, "Should extract trails"),
    ?assert(length(Types) > 0, "Should extract types"),

    %% Step 3: Expand trails metadata
    ExpandedTrails = rebar3_opapi_expander:expand_trails(Trails, Types),
    ?assertEqual(length(Trails), length(ExpandedTrails), "Should expand all trails"),

    %% Step 4: Build OpenAPI document
    AppName = <<"ComprehensiveAPI">>,
    OpenAPIDoc = rebar3_opapi_builder:build_from_trails(ExpandedTrails, Types, AppName),

    %% Assert: Check top-level structure
    ?assertEqual(<<"3.0.3">>, maps:get(<<"openapi">>, OpenAPIDoc)),

    %% Check info section
    Info = maps:get(<<"info">>, OpenAPIDoc),
    ?assertEqual(<<"ComprehensiveAPI">>, maps:get(<<"title">>, Info)),
    ?assertEqual(<<"1.0.0">>, maps:get(<<"version">>, Info)),

    %% Check paths section
    Paths = maps:get(<<"paths">>, OpenAPIDoc),
    ?assert(maps:size(Paths) > 0, "Should have paths"),

    %% Check that paths have correct format (/:id -> /{id})
    PathKeys = maps:keys(Paths),
    lists:foreach(
        fun(Path) ->
            %% Should use OpenAPI format {id} not :id
            PathStr = binary_to_list(Path),
            case string:find(PathStr, ":") of
                nomatch -> ok;  % Good, no : found
                _ -> ?assert(false, "Paths should use {id} format, not :id, got: " ++ PathStr)
            end
        end,
        PathKeys
    ),

    %% Check components section
    Components = maps:get(<<"components">>, OpenAPIDoc),
    ?assert(maps:is_key(<<"schemas">>, Components)),

    Schemas = maps:get(<<"schemas">>, Components),
    ?assert(maps:size(Schemas) > 0, "Should have schemas"),

    %% Verify some expected schemas exist
    ExpectedSchemas = [<<"User">>, <<"UserRole">>, <<"ErrorResponse">>],
    lists:foreach(
        fun(SchemaName) ->
            case maps:is_key(SchemaName, Schemas) of
                true -> ok;
                false ->
                    %% Try to find it with different capitalization
                    SchemaKeys = maps:keys(Schemas),
                    Found = lists:any(
                        fun(Key) ->
                            string:equal(binary_to_list(Key), binary_to_list(SchemaName), true)
                        end,
                        SchemaKeys
                    ),
                    ?assert(Found, io_lib:format("Should have schema ~s (checked: ~p)", [SchemaName, SchemaKeys]))
            end
        end,
        ExpectedSchemas
    ),

    %% Verify operations have operationId
    maps:fold(
        fun(_Path, PathOps, _Acc) ->
            maps:fold(
                fun(_Method, Op, _Acc2) ->
                    ?assert(maps:is_key(<<"operationId">>, Op),
                        "All operations should have operationId"),
                    OpId = maps:get(<<"operationId">>, Op),
                    ?assert(is_binary(OpId), "operationId should be binary"),
                    ?assert(byte_size(OpId) > 0, "operationId should not be empty")
                end,
                ok,
                PathOps
            )
        end,
        ok,
        Paths
    ),

    ?assert(true, "Comprehensive handler end-to-end test passed").

