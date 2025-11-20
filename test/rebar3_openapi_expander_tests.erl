%%%===================================================================
%%% Unit Tests for rebar3_openapi_expander
%%%===================================================================
%%% This module contains unit tests for the rebar3_openapi_expander module,
%%% focusing on expanding type references in trails metadata to OpenAPI 3.0.x $refs.
%%%===================================================================
%%%
%%% Test Progress:
%%% [✅] Test 1: generate_unique_operation_id_test - PASSED 2025-01-15
%%% [✅] Test 2: expand_parameter_with_type_ref_test - PASSED 2025-01-15
%%% [✅] Test 3: expand_request_body_with_type_ref_test - PASSED 2025-01-15
%%% [✅] Test 4: expand_response_with_type_ref_test - PASSED 2025-01-15
%%% [✅] Test 5: expand_complete_trail_test - PASSED 2025-01-15
%%%
%%% ALL EXPANDER TESTS COMPLETE: 5/5 PASSED ✓
%%%===================================================================

%%%===================================================================
%%% Test Cases
%%%===================================================================

-module(rebar3_openapi_expander_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test 1: Generate unique operationId
%%%===================================================================

%% Test 1: Generate unique operationId from path and method
generate_unique_operation_id_test() ->
    %% Test simple path
    OpId1 = rebar3_openapi_expander:generate_operation_id(<<"/users">>, get),
    ?assertEqual(<<"getUsers">>, OpId1),

    %% Test path with parameter
    OpId2 = rebar3_openapi_expander:generate_operation_id(<<"/users/:id">>, get),
    ?assertEqual(<<"getUsersById">>, OpId2),

    %% Test POST method
    OpId3 = rebar3_openapi_expander:generate_operation_id(<<"/users">>, post),
    ?assertEqual(<<"postUsers">>, OpId3),

    %% Test nested path
    OpId4 = rebar3_openapi_expander:generate_operation_id(<<"/api/users/:id/profile">>, put),
    ?assertEqual(<<"putApiUsersByIdProfile">>, OpId4),

    %% Test DELETE method
    OpId5 = rebar3_openapi_expander:generate_operation_id(<<"/users/:id">>, delete),
    ?assertEqual(<<"deleteUsersById">>, OpId5).

%%%===================================================================
%%% Test 2: Expand parameter with type reference
%%%===================================================================

%% Test 2: Expand parameter with type reference to $ref
expand_parameter_with_type_ref_test() ->
    %% Input: Parameter with type reference (atom)
    Param = #{
        name => <<"id">>,
        in => <<"path">>,
        required => true,
        % Type reference as atom
        schema => user_id
    },

    Types = [{user_id, {type, 1, binary, []}}],

    %% Execute expansion
    Expanded = rebar3_openapi_expander:expand_parameters([Param], Types),

    %% Assert: Should have one parameter
    ?assertEqual(1, length(Expanded)),
    [ExpandedParam] = Expanded,

    %% Check that schema is now a $ref map
    Schema = maps:get(schema, ExpandedParam),
    ?assertMatch(#{<<"$ref">> := _}, Schema),
    ?assertEqual(<<"#/components/schemas/UserId">>, maps:get(<<"$ref">>, Schema)),

    %% Other fields should remain unchanged
    ?assertEqual(<<"id">>, maps:get(name, ExpandedParam)),
    ?assertEqual(<<"path">>, maps:get(in, ExpandedParam)),
    ?assertEqual(true, maps:get(required, ExpandedParam)).

%%%===================================================================
%%% Test 3: Expand requestBody with type reference
%%%===================================================================

%% Test 3: Expand requestBody with type reference
expand_request_body_with_type_ref_test() ->
    %% Input: RequestBody with type reference
    RequestBody = #{
        required => true,
        content => #{
            <<"application/json">> => #{
                % Type reference
                schema => user
            }
        }
    },

    Types = [{user, {type, 1, map, []}}],

    %% Execute expansion
    Expanded = rebar3_openapi_expander:expand_request_body(RequestBody, Types),

    %% Assert: required field unchanged
    ?assertEqual(true, maps:get(required, Expanded)),

    %% Check content expansion
    Content = maps:get(content, Expanded),
    JsonContent = maps:get(<<"application/json">>, Content),
    Schema = maps:get(schema, JsonContent),

    %% Schema should be a $ref
    ?assertMatch(#{<<"$ref">> := _}, Schema),
    ?assertEqual(<<"#/components/schemas/User">>, maps:get(<<"$ref">>, Schema)).

%%%===================================================================
%%% Test 4: Expand response with type reference
%%%===================================================================

%% Test 4: Expand responses with type references
expand_response_with_type_ref_test() ->
    %% Input: Responses with type references
    Responses = #{
        <<"200">> => #{
            description => <<"Success">>,
            content => #{
                <<"application/json">> => #{
                    schema => user
                }
            }
        },
        <<"404">> => #{
            description => <<"Not found">>
        }
    },

    Types = [{user, {type, 1, map, []}}],

    %% Execute expansion
    Expanded = rebar3_openapi_expander:expand_responses(Responses, Types),

    %% Check 200 response
    Response200 = maps:get(<<"200">>, Expanded),
    ?assertEqual(<<"Success">>, maps:get(description, Response200)),

    Content200 = maps:get(content, Response200),
    JsonContent = maps:get(<<"application/json">>, Content200),
    Schema = maps:get(schema, JsonContent),

    %% Schema should be a $ref
    ?assertMatch(#{<<"$ref">> := _}, Schema),
    ?assertEqual(<<"#/components/schemas/User">>, maps:get(<<"$ref">>, Schema)),

    %% Check 404 response (no content, should be unchanged)
    Response404 = maps:get(<<"404">>, Expanded),
    ?assertEqual(<<"Not found">>, maps:get(description, Response404)),
    ?assertEqual(false, maps:is_key(content, Response404)).

%%%===================================================================
%%% Test 5: Expand complete trail
%%%===================================================================

%% Test 5: Expand complete trail with all features
expand_complete_trail_test() ->
    %% Input: Complete trail with type references
    Trail = #{
        path => <<"/api/users/:id">>,
        handler => user_handler,
        options => #{},
        metadata => #{
            get => #{
                tags => [<<"users">>],
                description => <<"Get user by ID">>,
                parameters => [
                    #{
                        name => <<"id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id
                    }
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Success">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => user
                            }
                        }
                    }
                }
            },
            put => #{
                tags => [<<"users">>],
                description => <<"Update user">>,
                requestBody => #{
                    required => true,
                    content => #{
                        <<"application/json">> => #{
                            schema => user
                        }
                    }
                },
                responses => #{
                    <<"200">> => #{description => <<"Updated">>}
                }
            }
        }
    },

    Types = [
        {user_id, {type, 1, binary, []}},
        {user, {type, 1, map, []}}
    ],

    %% Execute expansion
    Expanded = rebar3_openapi_expander:expand_trail(Trail, Types),

    %% Check path and handler unchanged
    ?assertEqual(<<"/api/users/:id">>, maps:get(path, Expanded)),
    ?assertEqual(user_handler, maps:get(handler, Expanded)),

    %% Check GET operation
    ExpandedMetadata = maps:get(metadata, Expanded),
    GetOp = maps:get(get, ExpandedMetadata),

    %% Should have auto-generated operationId
    ?assert(maps:is_key(operationId, GetOp)),
    OpId = maps:get(operationId, GetOp),
    ?assertEqual(<<"getApiUsersById">>, OpId),

    %% Check parameter expansion
    GetParams = maps:get(parameters, GetOp),
    [GetParam] = GetParams,
    GetParamSchema = maps:get(schema, GetParam),
    ?assertEqual(<<"#/components/schemas/UserId">>, maps:get(<<"$ref">>, GetParamSchema)),

    %% Check response expansion
    GetResponses = maps:get(responses, GetOp),
    GetResponse200 = maps:get(<<"200">>, GetResponses),
    GetContent = maps:get(content, GetResponse200),
    GetJsonContent = maps:get(<<"application/json">>, GetContent),
    GetResponseSchema = maps:get(schema, GetJsonContent),
    ?assertEqual(<<"#/components/schemas/User">>, maps:get(<<"$ref">>, GetResponseSchema)),

    %% Check PUT operation
    PutOp = maps:get(put, ExpandedMetadata),

    %% Should have auto-generated operationId
    ?assert(maps:is_key(operationId, PutOp)),
    PutOpId = maps:get(operationId, PutOp),
    ?assertEqual(<<"putApiUsersById">>, PutOpId),

    %% Check requestBody expansion
    PutReqBody = maps:get(requestBody, PutOp),
    PutContent = maps:get(content, PutReqBody),
    PutJsonContent = maps:get(<<"application/json">>, PutContent),
    PutReqSchema = maps:get(schema, PutJsonContent),
    ?assertEqual(<<"#/components/schemas/User">>, maps:get(<<"$ref">>, PutReqSchema)).
