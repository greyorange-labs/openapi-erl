%%%-------------------------------------------------------------------
%%% @author amarBitMan <https://github.com/amarBitMan>
%%% @copyright (C) 2025, Grey Orange
%%%-------------------------------------------------------------------
-module(rebar3_openapi_builder_tests).

-moduledoc """
----------------------------------------------------------------------
Unit Tests for rebar3_openapi_builder

Tests building complete OpenAPI 3.0.x document structure from expanded
trails, including paths, components, info sections, and app.src reading.
----------------------------------------------------------------------
""".
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test 1: Build paths from trails
%%%===================================================================

%% Test 1: Build paths section from expanded trails
build_paths_from_trails_test() ->
    %% Input: Expanded trails with full metadata
    Trails = [
        #{
            path => <<"/api/users/:id">>,
            handler => user_handler,
            options => #{},
            metadata => #{
                get => #{
                    operationId => <<"getUserById">>,
                    tags => [<<"users">>],
                    description => <<"Get user by ID">>,
                    parameters => [
                        #{
                            name => <<"id">>,
                            in => <<"path">>,
                            required => true,
                            schema => #{<<"$ref">> => <<"#/components/schemas/UserId">>}
                        }
                    ],
                    responses => #{
                        <<"200">> => #{
                            description => <<"Success">>,
                            content => #{
                                <<"application/json">> => #{
                                    schema => #{<<"$ref">> => <<"#/components/schemas/User">>}
                                }
                            }
                        }
                    }
                }
            }
        }
    ],

    %% Execute
    Paths = rebar3_openapi_builder:build_paths_from_trails(Trails),

    %% Assert: Should have one path with converted format
    ?assertEqual(1, maps:size(Paths)),
    ?assert(maps:is_key(<<"/api/users/{id}">>, Paths)),

    %% Check path operations
    PathOps = maps:get(<<"/api/users/{id}">>, Paths),
    ?assert(maps:is_key(<<"get">>, PathOps)),

    %% Check GET operation
    GetOp = maps:get(<<"get">>, PathOps),
    ?assertEqual(<<"getUserById">>, maps:get(<<"operationId">>, GetOp)),
    ?assertEqual([<<"users">>], maps:get(<<"tags">>, GetOp)),
    ?assertEqual(<<"Get user by ID">>, maps:get(<<"description">>, GetOp)),

    %% Check parameters
    Params = maps:get(<<"parameters">>, GetOp),
    ?assertEqual(1, length(Params)),
    [Param] = Params,
    ?assertEqual(<<"id">>, maps:get(name, Param)),

    %% Check responses
    Responses = maps:get(<<"responses">>, GetOp),
    ?assert(maps:is_key(<<"200">>, Responses)).

%%%===================================================================
%%% Test 2: Build components with schemas
%%%===================================================================

%% Test 2: Build components section with schemas from types
build_components_with_schemas_test() ->
    %% Input: Type definitions
    Types = [
        {user_id, {type, 1, binary, []}},
        {user,
            {type, 1, map, [
                {type, 1, map_field_exact, [{atom, 1, id}, {user_type, 1, user_id, []}]},
                {type, 1, map_field_exact, [{atom, 1, name}, {type, 1, binary, []}]}
            ]}}
    ],

    %% Execute
    Components = rebar3_openapi_builder:build_components(Types),

    %% Assert: Should have schemas section
    ?assert(maps:is_key(<<"schemas">>, Components)),

    Schemas = maps:get(<<"schemas">>, Components),
    ?assertEqual(2, maps:size(Schemas)),

    %% Check UserId schema
    ?assert(maps:is_key(<<"UserId">>, Schemas)),
    UserIdSchema = maps:get(<<"UserId">>, Schemas),
    ?assertEqual(<<"string">>, maps:get(<<"type">>, UserIdSchema)),

    %% Check User schema
    ?assert(maps:is_key(<<"User">>, Schemas)),
    UserSchema = maps:get(<<"User">>, Schemas),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, UserSchema)),

    %% Check User properties
    Properties = maps:get(<<"properties">>, UserSchema),
    ?assert(maps:is_key(<<"id">>, Properties)),
    ?assert(maps:is_key(<<"name">>, Properties)).

%%%===================================================================
%%% Test 3: Build complete OpenAPI document
%%%===================================================================

%% Test 3: Build complete OpenAPI document from trails and types
build_complete_openapi_doc_test() ->
    %% Input: Expanded trails and types
    Trails = [
        #{
            path => <<"/api/users">>,
            handler => user_handler,
            options => #{},
            metadata => #{
                get => #{
                    operationId => <<"listUsers">>,
                    tags => [<<"users">>],
                    description => <<"List all users">>,
                    responses => #{
                        <<"200">> => #{
                            description => <<"Success">>,
                            content => #{
                                <<"application/json">> => #{
                                    schema => #{
                                        <<"type">> => <<"array">>,
                                        <<"items">> => #{<<"$ref">> => <<"#/components/schemas/User">>}
                                    }
                                }
                            }
                        }
                    }
                },
                post => #{
                    operationId => <<"createUser">>,
                    tags => [<<"users">>],
                    description => <<"Create a new user">>,
                    requestBody => #{
                        required => true,
                        content => #{
                            <<"application/json">> => #{
                                schema => #{<<"$ref">> => <<"#/components/schemas/User">>}
                            }
                        }
                    },
                    responses => #{
                        <<"201">> => #{description => <<"Created">>}
                    }
                }
            }
        }
    ],

    Types = [
        {user,
            {type, 1, map, [
                {type, 1, map_field_exact, [{atom, 1, name}, {type, 1, binary, []}]}
            ]}}
    ],

    AppName = <<"TestAPI">>,

    %% Execute
    Doc = rebar3_openapi_builder:build_from_trails(Trails, Types, AppName, undefined, undefined),

    %% Assert: Check top-level structure
    ?assertEqual(<<"3.0.3">>, maps:get(<<"openapi">>, Doc)),
    ?assert(maps:is_key(<<"info">>, Doc)),
    ?assert(maps:is_key(<<"servers">>, Doc)),
    ?assert(maps:is_key(<<"paths">>, Doc)),
    ?assert(maps:is_key(<<"components">>, Doc)),

    %% Check info section
    Info = maps:get(<<"info">>, Doc),
    ?assertEqual(<<"TestAPI">>, maps:get(<<"title">>, Info)),
    ?assertEqual(<<"1.0.0">>, maps:get(<<"version">>, Info)),

    %% Check paths section
    Paths = maps:get(<<"paths">>, Doc),
    ?assertEqual(1, maps:size(Paths)),
    ?assert(maps:is_key(<<"/api/users">>, Paths)),

    PathOps = maps:get(<<"/api/users">>, Paths),
    ?assert(maps:is_key(<<"get">>, PathOps)),
    ?assert(maps:is_key(<<"post">>, PathOps)),

    %% Check GET operation
    GetOp = maps:get(<<"get">>, PathOps),
    ?assertEqual(<<"listUsers">>, maps:get(<<"operationId">>, GetOp)),

    %% Check POST operation
    PostOp = maps:get(<<"post">>, PathOps),
    ?assertEqual(<<"createUser">>, maps:get(<<"operationId">>, PostOp)),
    ?assert(maps:is_key(<<"requestBody">>, PostOp)),

    %% Check components section
    Components = maps:get(<<"components">>, Doc),
    ?assert(maps:is_key(<<"schemas">>, Components)),
    Schemas = maps:get(<<"schemas">>, Components),
    ?assert(maps:is_key(<<"User">>, Schemas)).

%%%===================================================================
%%% Test 4: Build info from app.src file
%%%===================================================================

%% Test 4: Build info section with app.src file
build_info_from_app_src_test() ->
    %% Create a temporary app.src file for testing
    TestAppSrcPath = "test/fixtures/test_app.app.src",

    %% Verify the test file exists
    ?assert(filelib:is_file(TestAppSrcPath), "Test app.src file should exist"),

    %% Execute: Build info with app.src path
    AppName = <<"test_app">>,
    Info = rebar3_openapi_builder:build_info(AppName, TestAppSrcPath, undefined),

    %% Assert: Should extract version and description from app.src
    ?assertEqual(<<"test_app">>, maps:get(<<"title">>, Info)),
    ?assertEqual(<<"2.5.0">>, maps:get(<<"version">>, Info)),
    ?assertEqual(<<"Test application for OpenAPI plugin testing">>, maps:get(<<"description">>, Info)).

%% Test 5: Build info without app.src file (should use defaults)
build_info_without_app_src_test() ->
    %% Execute: Build info without app.src path
    AppName = <<"TestAPI">>,
    Info = rebar3_openapi_builder:build_info(AppName, undefined, undefined),

    %% Assert: Should use default values
    ?assertEqual(<<"TestAPI">>, maps:get(<<"title">>, Info)),
    ?assertEqual(<<"1.0.0">>, maps:get(<<"version">>, Info)),
    ?assertEqual(<<"API documentation generated from Erlang handler modules">>, maps:get(<<"description">>, Info)).

%% Test 6: Build complete document with app.src
build_complete_doc_with_app_src_test() ->
    %% Input: Simple trail
    Trails = [
        #{
            path => <<"/api/test">>,
            handler => test_handler,
            options => #{},
            metadata => #{
                get => #{
                    operationId => <<"testEndpoint">>,
                    tags => [<<"test">>],
                    responses => #{
                        <<"200">> => #{description => <<"Success">>}
                    }
                }
            }
        }
    ],

    Types = [],
    AppName = <<"test_app">>,
    TestAppSrcPath = "test/fixtures/test_app.app.src",

    %% Execute
    Doc = rebar3_openapi_builder:build_from_trails(Trails, Types, AppName, TestAppSrcPath, undefined),

    %% Assert: Check info section has values from app.src
    Info = maps:get(<<"info">>, Doc),
    ?assertEqual(<<"test_app">>, maps:get(<<"title">>, Info)),
    ?assertEqual(<<"2.5.0">>, maps:get(<<"version">>, Info)),
    ?assertEqual(<<"Test application for OpenAPI plugin testing">>, maps:get(<<"description">>, Info)),

    %% Check other sections still work
    ?assertEqual(<<"3.0.3">>, maps:get(<<"openapi">>, Doc)),
    ?assert(maps:is_key(<<"paths">>, Doc)),
    ?assert(maps:is_key(<<"components">>, Doc)).

%%%===================================================================
%%% Test 7: Operation-level metadata passthrough
%%%===================================================================

build_paths_deprecated_operation_test() ->
    Trails = [
        #{
            path => <<"/api/old">>,
            handler => old_handler,
            options => #{},
            metadata => #{
                get => #{
                    operationId => <<"getOld">>,
                    deprecated => true,
                    responses => #{
                        <<"200">> => #{description => <<"Success">>}
                    }
                }
            }
        }
    ],
    Paths = rebar3_openapi_builder:build_paths_from_trails(Trails),
    GetOp = maps:get(<<"get">>, maps:get(<<"/api/old">>, Paths)),
    ?assertEqual(true, maps:get(<<"deprecated">>, GetOp)).

build_paths_security_operation_test() ->
    Trails = [
        #{
            path => <<"/api/secure">>,
            handler => secure_handler,
            options => #{},
            metadata => #{
                get => #{
                    operationId => <<"getSecure">>,
                    security => [#{<<"bearerAuth">> => []}],
                    responses => #{
                        <<"200">> => #{description => <<"Success">>}
                    }
                }
            }
        }
    ],
    Paths = rebar3_openapi_builder:build_paths_from_trails(Trails),
    GetOp = maps:get(<<"get">>, maps:get(<<"/api/secure">>, Paths)),
    ?assertEqual([#{<<"bearerAuth">> => []}], maps:get(<<"security">>, GetOp)).

build_paths_external_docs_operation_test() ->
    Trails = [
        #{
            path => <<"/api/docs">>,
            handler => docs_handler,
            options => #{},
            metadata => #{
                get => #{
                    operationId => <<"getDocs">>,
                    externalDocs => #{
                        <<"description">> => <<"More info">>,
                        <<"url">> => <<"https://example.com/docs">>
                    },
                    responses => #{
                        <<"200">> => #{description => <<"Success">>}
                    }
                }
            }
        }
    ],
    Paths = rebar3_openapi_builder:build_paths_from_trails(Trails),
    GetOp = maps:get(<<"get">>, maps:get(<<"/api/docs">>, Paths)),
    ExternalDocs = maps:get(<<"externalDocs">>, GetOp),
    ?assertEqual(<<"More info">>, maps:get(<<"description">>, ExternalDocs)).

%%%===================================================================
%%% Test 8-12: -type_meta merging into components
%%%===================================================================

%% Test 8: build_components/2 merges type_meta descriptions into schemas
build_components_with_type_meta_test() ->
    Types = [
        {user_id, {type, 1, binary, []}},
        {user_role, {type, 1, union, [{atom, 1, admin}, {atom, 1, viewer}]}}
    ],
    TypeMeta = #{
        user_id => #{description => <<"Unique user identifier">>, example => <<"usr_123">>},
        user_role => #{description => <<"Role assigned to a user">>, deprecated => true}
    },

    Components = rebar3_openapi_builder:build_components(Types, TypeMeta),
    Schemas = maps:get(<<"schemas">>, Components),

    %% UserId schema should have description and example
    UserIdSchema = maps:get(<<"UserId">>, Schemas),
    ?assertEqual(<<"string">>, maps:get(<<"type">>, UserIdSchema)),
    ?assertEqual(<<"Unique user identifier">>, maps:get(<<"description">>, UserIdSchema)),
    ?assertEqual(<<"usr_123">>, maps:get(<<"example">>, UserIdSchema)),

    %% UserRole schema should have description and deprecated
    UserRoleSchema = maps:get(<<"UserRole">>, Schemas),
    ?assertEqual(<<"Role assigned to a user">>, maps:get(<<"description">>, UserRoleSchema)),
    ?assertEqual(true, maps:get(<<"deprecated">>, UserRoleSchema)).

%% Test 9: Empty type_meta should not change schemas
build_components_empty_type_meta_test() ->
    Types = [
        {user_id, {type, 1, binary, []}}
    ],

    %% With empty TypeMeta
    Components = rebar3_openapi_builder:build_components(Types, #{}),
    Schemas = maps:get(<<"schemas">>, Components),
    UserIdSchema = maps:get(<<"UserId">>, Schemas),

    %% Should have type but no description
    ?assertEqual(<<"string">>, maps:get(<<"type">>, UserIdSchema)),
    ?assertEqual(error, maps:find(<<"description">>, UserIdSchema)).

%% Test 10: type_meta for non-existent type is silently ignored
build_components_type_meta_nonexistent_type_test() ->
    Types = [
        {user_id, {type, 1, binary, []}}
    ],
    TypeMeta = #{
        nonexistent_type => #{description => <<"Should be ignored">>}
    },

    Components = rebar3_openapi_builder:build_components(Types, TypeMeta),
    Schemas = maps:get(<<"schemas">>, Components),

    %% Only UserId should exist, no NonexistentType
    ?assertEqual(1, maps:size(Schemas)),
    ?assert(maps:is_key(<<"UserId">>, Schemas)),
    %% UserId should NOT have the description (it was for nonexistent_type)
    ?assertEqual(error, maps:find(<<"description">>, maps:get(<<"UserId">>, Schemas))).

%% Test 11: build_from_trails/6 passes type_meta through to components
build_from_trails_with_type_meta_test() ->
    Trails = [
        #{
            path => <<"/api/test">>,
            handler => test_handler,
            options => #{},
            metadata => #{
                get => #{
                    operationId => <<"getTest">>,
                    tags => [<<"test">>],
                    responses => #{
                        <<"200">> => #{description => <<"Success">>}
                    }
                }
            }
        }
    ],
    Types = [
        {my_type, {type, 1, binary, []}}
    ],
    TypeMeta = #{
        my_type => #{description => <<"A test type">>, title => <<"MyType Title">>}
    },

    Doc = rebar3_openapi_builder:build_from_trails(Trails, Types, <<"TestApp">>, undefined, undefined, TypeMeta),

    %% Check components have the merged metadata
    Components = maps:get(<<"components">>, Doc),
    Schemas = maps:get(<<"schemas">>, Components),
    MyTypeSchema = maps:get(<<"MyType">>, Schemas),
    ?assertEqual(<<"A test type">>, maps:get(<<"description">>, MyTypeSchema)),
    ?assertEqual(<<"MyType Title">>, maps:get(<<"title">>, MyTypeSchema)).

%% Test 12: All supported metadata keys are applied correctly
build_components_all_metadata_keys_test() ->
    Types = [
        {config_type, {type, 1, binary, []}}
    ],
    TypeMeta = #{
        config_type => #{
            description => <<"A configuration value">>,
            title => <<"Config">>,
            example => <<"my-config">>,
            default => <<"default-val">>,
            deprecated => true,
            read_only => true,
            write_only => false
        }
    },

    Components = rebar3_openapi_builder:build_components(Types, TypeMeta),
    Schema = maps:get(<<"ConfigType">>, maps:get(<<"schemas">>, Components)),

    ?assertEqual(<<"A configuration value">>, maps:get(<<"description">>, Schema)),
    ?assertEqual(<<"Config">>, maps:get(<<"title">>, Schema)),
    ?assertEqual(<<"my-config">>, maps:get(<<"example">>, Schema)),
    ?assertEqual(<<"default-val">>, maps:get(<<"default">>, Schema)),
    ?assertEqual(true, maps:get(<<"deprecated">>, Schema)),
    ?assertEqual(true, maps:get(<<"readOnly">>, Schema)),
    ?assertEqual(false, maps:get(<<"writeOnly">>, Schema)).
