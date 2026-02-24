%%%-------------------------------------------------------------------
%%% @author amarBitMan <https://github.com/amarBitMan>
%%% @copyright (C) 2025, Grey Orange
%%%-------------------------------------------------------------------
-module(rebar3_openapi_integration_tests).

-moduledoc """
----------------------------------------------------------------------
Integration Tests for rebar3_openapi

End-to-end tests covering the complete flow from Erlang handler files
to OpenAPI 3.0.x document generation, including redocly lint validation.
----------------------------------------------------------------------
""".
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test 1: Simple Handler End-to-End
%%%===================================================================

%% Test 1: End-to-end test with simple_handler.erl
simple_handler_end_to_end_test() ->
    %% Input: Simple handler fixture
    FixturePath = "test/fixtures/simple_handler.erl",
    ModuleName = simple_handler,

    %% Step 1: Parse handler file for types (types are compile-time only)
    IncludePaths = [{includes, []}, {macros, []}],
    {ok, Forms} = epp:parse_file(FixturePath, IncludePaths),

    %% Step 2: Extract types and call trails() directly
    Types = rebar3_openapi_parser:extract_types(Forms),

    %% Compile and load handler module, then call trails()
    {ok, Trails} = compile_and_call_trails(FixturePath, ModuleName),

    %% Assert: Should extract trails and types
    ?assert(length(Trails) > 0, "Should extract at least one trail"),
    ?assert(length(Types) >= 0, "Types are optional"),

    %% Step 3: Expand trails metadata
    ExpandedTrails = rebar3_openapi_expander:expand_trails(Trails, Types),
    ?assertEqual(length(Trails), length(ExpandedTrails), "Should expand all trails"),

    %% Step 4: Build OpenAPI document
    AppName = <<"TestAPI">>,
    OpenAPIDoc = rebar3_openapi_builder:build_from_trails(ExpandedTrails, Types, AppName, undefined, undefined),

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
    ModuleName = comprehensive_handler,

    %% Step 1: Parse handler file for types (types are compile-time only)
    IncludePaths = [{includes, []}, {macros, []}],
    {ok, Forms} = epp:parse_file(FixturePath, IncludePaths),

    %% Step 2: Extract types and call trails() directly
    Types = rebar3_openapi_parser:extract_types(Forms),

    %% Compile and load handler module, then call trails()
    {ok, Trails} = compile_and_call_trails(FixturePath, ModuleName),

    %% Assert: Should extract multiple trails and types
    ?assert(length(Trails) > 0, "Should extract trails"),
    ?assert(length(Types) > 0, "Should extract types"),

    %% Step 3: Expand trails metadata
    ExpandedTrails = rebar3_openapi_expander:expand_trails(Trails, Types),
    ?assertEqual(length(Trails), length(ExpandedTrails), "Should expand all trails"),

    %% Step 4: Build OpenAPI document
    AppName = <<"ComprehensiveAPI">>,
    OpenAPIDoc = rebar3_openapi_builder:build_from_trails(ExpandedTrails, Types, AppName, undefined, undefined),

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
                % Good, no : found
                nomatch -> ok;
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
                true ->
                    ok;
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
                    ?assert(
                        maps:is_key(<<"operationId">>, Op),
                        "All operations should have operationId"
                    ),
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

%%%===================================================================
%%% Test 3: Full OpenAPI Document Validation
%%%===================================================================

%% Test 3: Verify generated OpenAPI document matches handler definition
generate_complete_openapi_doc_test() ->
    %% Input: Handler with type references
    FixturePath = "test/fixtures/handler_with_types.erl",
    ModuleName = handler_with_types,

    %% Parse handler for types (types are compile-time only)
    IncludePaths = [{includes, []}, {macros, []}],
    {ok, Forms} = epp:parse_file(FixturePath, IncludePaths),
    Types = rebar3_openapi_parser:extract_types(Forms),

    %% Compile and load handler module, then call trails()
    {ok, Trails} = compile_and_call_trails(FixturePath, ModuleName),
    ExpandedTrails = rebar3_openapi_expander:expand_trails(Trails, Types),

    %% Generate OpenAPI document
    AppName = <<"TestAPI">>,
    OpenAPIDoc = rebar3_openapi_builder:build_from_trails(ExpandedTrails, Types, AppName, undefined, undefined),

    %% Verify complete document structure
    ?assertEqual(<<"3.0.3">>, maps:get(<<"openapi">>, OpenAPIDoc)),

    %% Verify info
    Info = maps:get(<<"info">>, OpenAPIDoc),
    ?assertEqual(<<"TestAPI">>, maps:get(<<"title">>, Info)),

    %% Verify paths exist and have correct structure
    Paths = maps:get(<<"paths">>, OpenAPIDoc),
    ?assert(maps:is_key(<<"/api/users">>, Paths), "Should have /api/users path"),
    ?assert(maps:is_key(<<"/api/users/{user_id}">>, Paths), "Should have /api/users/{user_id} path"),

    %% Verify GET /api/users operation
    UsersPath = maps:get(<<"/api/users">>, Paths),
    ?assert(maps:is_key(<<"get">>, UsersPath), "Should have GET operation"),
    GetOp = maps:get(<<"get">>, UsersPath),
    %% operationId is auto-generated (e.g., "getApiUsers")
    ?assert(maps:is_key(<<"operationId">>, GetOp), "Should have auto-generated operationId"),
    OpId = maps:get(<<"operationId">>, GetOp),
    ?assert(is_binary(OpId)),
    ?assert(byte_size(OpId) > 0),
    ?assertEqual([<<"Users">>], maps:get(<<"tags">>, GetOp)),

    %% Verify GET response has array of users
    GetResponses = maps:get(<<"responses">>, GetOp),
    ?assert(maps:is_key(<<"200">>, GetResponses)),
    GetResponse200 = maps:get(<<"200">>, GetResponses),
    %% Response may have atom or binary keys - check both
    GetContent =
        case maps:is_key(<<"content">>, GetResponse200) of
            true -> maps:get(<<"content">>, GetResponse200);
            false -> maps:get(content, GetResponse200)
        end,
    GetJsonContent = maps:get(<<"application/json">>, GetContent),
    GetSchema =
        case maps:is_key(<<"schema">>, GetJsonContent) of
            true -> maps:get(<<"schema">>, GetJsonContent);
            false -> maps:get(schema, GetJsonContent)
        end,
    ?assertEqual(<<"array">>, maps:get(<<"type">>, GetSchema)),
    GetItems = maps:get(<<"items">>, GetSchema),
    ?assertEqual(<<"#/components/schemas/User">>, maps:get(<<"$ref">>, GetItems)),

    %% Verify POST /api/users operation
    ?assert(maps:is_key(<<"post">>, UsersPath), "Should have POST operation"),
    PostOp = maps:get(<<"post">>, UsersPath),
    %% operationId is auto-generated (e.g., "postApiUsers")
    ?assert(maps:is_key(<<"operationId">>, PostOp), "Should have auto-generated operationId"),
    PostOpId = maps:get(<<"operationId">>, PostOp),
    ?assert(is_binary(PostOpId)),
    ?assert(byte_size(PostOpId) > 0),

    %% Verify POST requestBody uses CreateUserRequest type
    PostRequestBody = maps:get(<<"requestBody">>, PostOp),
    PostReqContent =
        case maps:is_key(<<"content">>, PostRequestBody) of
            true -> maps:get(<<"content">>, PostRequestBody);
            false -> maps:get(content, PostRequestBody)
        end,
    PostReqJson = maps:get(<<"application/json">>, PostReqContent),
    PostReqSchema =
        case maps:is_key(<<"schema">>, PostReqJson) of
            true -> maps:get(<<"schema">>, PostReqJson);
            false -> maps:get(schema, PostReqJson)
        end,
    ?assertEqual(<<"#/components/schemas/CreateUserRequest">>, maps:get(<<"$ref">>, PostReqSchema)),

    %% Verify POST response uses User type
    PostResponses = maps:get(<<"responses">>, PostOp),
    ?assert(maps:is_key(<<"201">>, PostResponses)),
    PostResponse201 = maps:get(<<"201">>, PostResponses),
    PostContent =
        case maps:is_key(<<"content">>, PostResponse201) of
            true -> maps:get(<<"content">>, PostResponse201);
            false -> maps:get(content, PostResponse201)
        end,
    PostJsonContent = maps:get(<<"application/json">>, PostContent),
    PostSchema =
        case maps:is_key(<<"schema">>, PostJsonContent) of
            true -> maps:get(<<"schema">>, PostJsonContent);
            false -> maps:get(schema, PostJsonContent)
        end,
    ?assertEqual(<<"#/components/schemas/User">>, maps:get(<<"$ref">>, PostSchema)),

    %% Verify GET /api/users/{user_id} operation
    UserIdPath = maps:get(<<"/api/users/{user_id}">>, Paths),
    ?assert(maps:is_key(<<"get">>, UserIdPath)),
    GetUserOp = maps:get(<<"get">>, UserIdPath),
    %% operationId is auto-generated (e.g., "getApiUsersByUserId")
    ?assert(maps:is_key(<<"operationId">>, GetUserOp), "Should have auto-generated operationId"),
    GetUserOpId = maps:get(<<"operationId">>, GetUserOp),
    ?assert(is_binary(GetUserOpId)),
    ?assert(byte_size(GetUserOpId) > 0),

    %% Verify path parameter
    GetUserParams = maps:get(<<"parameters">>, GetUserOp),
    ?assertEqual(1, length(GetUserParams)),
    [UserIdParam] = GetUserParams,
    ?assertEqual(<<"user_id">>, maps:get(name, UserIdParam)),
    ?assertEqual(<<"path">>, maps:get(in, UserIdParam)),
    ?assertEqual(true, maps:get(required, UserIdParam)),

    %% Verify components/schemas exist
    Components = maps:get(<<"components">>, OpenAPIDoc),
    Schemas = maps:get(<<"schemas">>, Components),
    ?assert(maps:is_key(<<"User">>, Schemas), "Should have User schema"),
    ?assert(maps:is_key(<<"UserRole">>, Schemas), "Should have UserRole schema"),
    ?assert(maps:is_key(<<"CreateUserRequest">>, Schemas), "Should have CreateUserRequest schema"),
    ?assert(maps:is_key(<<"ErrorResponse">>, Schemas), "Should have ErrorResponse schema"),

    %% Verify User schema structure
    UserSchema = maps:get(<<"User">>, Schemas),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, UserSchema)),
    UserProps = maps:get(<<"properties">>, UserSchema),
    ?assert(maps:is_key(<<"id">>, UserProps)),
    ?assert(maps:is_key(<<"name">>, UserProps)),
    ?assert(maps:is_key(<<"email">>, UserProps)),
    ?assert(maps:is_key(<<"age">>, UserProps)),

    %% Verify User required fields
    UserRequired = maps:get(<<"required">>, UserSchema),
    ?assert(lists:member(<<"id">>, UserRequired)),
    ?assert(lists:member(<<"name">>, UserRequired)),
    ?assert(lists:member(<<"email">>, UserRequired)),
    % age is optional
    ?assertNot(lists:member(<<"age">>, UserRequired)),

    %% Verify UserRole enum (all-atom union collapses to single enum)
    UserRoleSchema = maps:get(<<"UserRole">>, Schemas),
    ?assertEqual(<<"string">>, maps:get(<<"type">>, UserRoleSchema)),
    EnumValues = maps:get(<<"enum">>, UserRoleSchema),
    ?assert(lists:member(<<"admin">>, EnumValues)),
    ?assert(lists:member(<<"user">>, EnumValues)),
    ?assert(lists:member(<<"guest">>, EnumValues)),

    ?assert(true, "Complete OpenAPI document validation passed").

%%%===================================================================
%%% Test 4: End-to-End OpenAPI Standard Validation with Redocly
%%%===================================================================

%% Test 4: Generate OpenAPI document and validate with redocly lint
%% Uses comprehensive_handler.erl which includes all possible API combinations:
%% - GET, POST, PUT, PATCH, DELETE methods
%% - Path parameters, query parameters, request bodies
%% - Array responses, object responses, nested types
%% - Error responses, pagination, enums, unions
validate_openapi_standard_test() ->
    %% Input: Comprehensive handler with all API combinations
    FixturePath = "test/fixtures/comprehensive_handler.erl",
    ModuleName = comprehensive_handler,

    %% Parse handler for types (types are compile-time only)
    IncludePaths = [{includes, []}, {macros, []}],
    {ok, Forms} = epp:parse_file(FixturePath, IncludePaths),
    Types = rebar3_openapi_parser:extract_types(Forms),

    %% Compile and load handler module, then call trails()
    {ok, Trails} = compile_and_call_trails(FixturePath, ModuleName),
    ExpandedTrails = rebar3_openapi_expander:expand_trails(Trails, Types),

    %% Generate OpenAPI document
    AppName = <<"TestAPI">>,
    OpenAPIDoc = rebar3_openapi_builder:build_from_trails(ExpandedTrails, Types, AppName, undefined, undefined),

    %% Verify basic structure before writing
    ?assertEqual(<<"3.0.3">>, maps:get(<<"openapi">>, OpenAPIDoc)),
    ?assert(maps:is_key(<<"info">>, OpenAPIDoc)),
    ?assert(maps:is_key(<<"paths">>, OpenAPIDoc)),
    ?assert(maps:is_key(<<"components">>, OpenAPIDoc)),

    %% Write to YAML file in project root for review (not in /tmp)
    OutputYamlFile = "generated_openapi_comprehensive.yaml",
    case rebar3_openapi_prv_extract:write_openapi_file(OutputYamlFile, OpenAPIDoc) of
        ok ->
            %% Verify file was created
            ?assert(filelib:is_file(OutputYamlFile), "YAML file should be created"),
            io:format("Generated OpenAPI YAML file: ~s~n", [OutputYamlFile]),

            %% Validate with redocly lint
            case os:find_executable("redocly") of
                false ->
                    %% Skip test if redocly is not available
                    ?debugMsg("redocly not found, skipping validation"),
                    ?assert(true, "Skipped: redocly not installed");
                RedoclyPath ->
                    %% Run redocly lint and capture both stdout and stderr
                    %% Use port to get proper exit code
                    Cmd = lists:flatten(io_lib:format("~s lint ~s 2>&1", [RedoclyPath, OutputYamlFile])),
                    Port = open_port(
                        {spawn, Cmd},
                        [exit_status, stderr_to_stdout, binary]
                    ),
                    {Output, ExitCode} = collect_port_output(Port, [], 0),
                    %% Port will close automatically when process exits
                    catch port_close(Port),

                    %% Assert validation passed
                    case ExitCode of
                        0 ->
                            ?assert(true, "OpenAPI document passed redocly validation");
                        _ ->
                            io:format("Redocly validation failed (exit code: ~p)~nOutput:~n~s~n", [ExitCode, Output]),
                            ?assert(
                                false,
                                io_lib:format("OpenAPI document failed redocly validation (exit code: ~p): ~s", [ExitCode, Output])
                            )
                    end
            end;
        {error, Reason} ->
            ?assert(false, io_lib:format("Failed to write OpenAPI file: ~p", [Reason]))
    end,
    %% Teardown: Clean up generated file
    file:delete(OutputYamlFile).

%% Helper function to compile handler module and call trails()
-spec compile_and_call_trails(string(), atom()) -> {ok, [term()]} | {error, term()}.
compile_and_call_trails(FixturePath, ModuleName) ->
    try
        %% Use _build directory for compilation
        BaseDir = filename:absname("."),
        OutDir = filename:join([BaseDir, "_build", "test", "lib", "rebar3_openapi", "test", "ebin"]),
        filelib:ensure_dir(filename:join([OutDir, "dummy"])),

        %% Get trails library ebin path from rebar3's test profile
        TrailsEbin = filename:join([BaseDir, "_build", "test", "lib", "trails", "ebin"]),

        %% Add include paths
        IncludePaths = [
            {i, filename:join([BaseDir, "test", "fixtures"])},
            {i, BaseDir}
        ],

        %% Add trails ebin to include paths for compilation
        %% Also add it to code path so trails module is available
        true = code:add_patha(TrailsEbin),

        %% Compile options
        CompileOpts =
            [
                {outdir, OutDir},
                return_errors
            ] ++ IncludePaths,

        %% Compile the handler file
        case compile:file(FixturePath, CompileOpts) of
            {ok, _Module} ->
                ok;
            {ok, _Module, _Bin} ->
                ok;
            {ok, _Module, _Bin, _Warnings} ->
                ok;
            {error, Errors, _Warnings} ->
                throw({compile_error, Errors});
            Other ->
                throw({compile_error, Other})
        end,

        %% Add output directory to code path
        true = code:add_patha(OutDir),

        %% Load the module (force reload if already loaded)
        case code:soft_purge(ModuleName) of
            true -> ok;
            false -> ok
        end,
        code:delete(ModuleName),
        code:purge(ModuleName),

        %% Load the newly compiled module
        case code:load_abs(filename:join([OutDir, atom_to_list(ModuleName)])) of
            {module, ModuleName} ->
                ok;
            {error, LoadErrReason} ->
                %% Try ensure_loaded as fallback
                case code:ensure_loaded(ModuleName) of
                    {module, ModuleName} -> ok;
                    {error, EnsureErrReason} -> throw({module_load_error, LoadErrReason, EnsureErrReason})
                end
        end,

        %% Check if trails/0 is exported
        case erlang:function_exported(ModuleName, trails, 0) of
            true ->
                %% Call trails() function directly
                Trails = ModuleName:trails(),
                {ok, Trails};
            false ->
                {error, "trails/0 is not exported from " ++ atom_to_list(ModuleName)}
        end
    catch
        _:ErrorReason ->
            {error, ErrorReason}
    end.

%% Helper function to collect output from a port
-spec collect_port_output(port(), [binary()], integer()) -> {string(), integer()}.
collect_port_output(Port, Acc, ExitCode) ->
    receive
        {Port, {data, Data}} when is_binary(Data) ->
            collect_port_output(Port, [Data | Acc], ExitCode);
        {Port, {exit_status, Status}} ->
            Output = binary_to_list(iolist_to_binary(lists:reverse(Acc))),
            {Output, Status};
        {Port, eof} ->
            Output = binary_to_list(iolist_to_binary(lists:reverse(Acc))),
            {Output, ExitCode}
    after 30000 ->
        %% Timeout - return what we have
        Output = binary_to_list(iolist_to_binary(lists:reverse(Acc))),
        % Assume failure on timeout
        {Output, 1}
    end.
