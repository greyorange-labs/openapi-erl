-module(rebar3_opapi_schema_converter_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Progress Tracking
%%%===================================================================
%% [✅] Test 1: convert_binary_type_test - PASSED 2025-01-15
%% [✅] Test 2: convert_integer_type_test - PASSED 2025-01-15
%% [✅] Test 3: convert_float_type_test - PASSED 2025-01-15
%% [✅] Test 4: convert_boolean_type_test - PASSED 2025-01-15
%% [✅] Test 5: convert_map_all_required_fields_test - PASSED 2025-01-15
%% [✅] Test 6: convert_map_with_optional_fields_test - PASSED 2025-01-15
%% [✅] Test 7: convert_union_type_to_oneof_test - PASSED 2025-01-15
%% [✅] Test 8: convert_list_type_to_array_test - PASSED 2025-01-15
%% [✅] Test 9: convert_nested_map_test - PASSED 2025-01-15
%% [✅] Test 10: convert_user_type_reference_test - PASSED 2025-01-15
%% [✅] Test 11: convert_circular_reference_test - PASSED 2025-01-15
%%
%% ALL SCHEMA CONVERTER TESTS COMPLETE: 11/11 PASSED ✓
%%%===================================================================

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% Test 1: Convert binary() type to OpenAPI string schema
convert_binary_type_test() ->
    %% Input: Erlang binary() type as AST
    %% Testing via types_to_schemas which processes all types
    Types = [{my_string, {type, 1, binary, []}}],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create a schema named "MyString" with type string
    ?assertMatch(#{<<"MyString">> := _}, Schemas),
    MyStringSchema = maps:get(<<"MyString">>, Schemas),
    ?assertEqual(#{<<"type">> => <<"string">>}, MyStringSchema).

%% Test 2: Convert integer() type to OpenAPI integer schema
convert_integer_type_test() ->
    %% Input: Erlang integer() type as AST
    Types = [{my_int, {type, 1, integer, []}}],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create a schema named "MyInt" with type integer
    ?assertMatch(#{<<"MyInt">> := _}, Schemas),
    MyIntSchema = maps:get(<<"MyInt">>, Schemas),
    ?assertEqual(#{<<"type">> => <<"integer">>}, MyIntSchema).

%% Test 3: Convert float() type to OpenAPI number schema
convert_float_type_test() ->
    %% Input: Erlang float() type as AST
    Types = [{my_float, {type, 1, float, []}}],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create a schema named "MyFloat" with type number
    ?assertMatch(#{<<"MyFloat">> := _}, Schemas),
    MyFloatSchema = maps:get(<<"MyFloat">>, Schemas),
    ?assertEqual(#{<<"type">> => <<"number">>}, MyFloatSchema).

%% Test 4: Convert boolean() type to OpenAPI boolean schema
convert_boolean_type_test() ->
    %% Input: Erlang boolean() type as AST
    Types = [{my_bool, {type, 1, boolean, []}}],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create a schema named "MyBool" with type boolean
    ?assertMatch(#{<<"MyBool">> := _}, Schemas),
    MyBoolSchema = maps:get(<<"MyBool">>, Schemas),
    ?assertEqual(#{<<"type">> => <<"boolean">>}, MyBoolSchema).

%% Test 5: Convert map with all required fields to OpenAPI object
convert_map_all_required_fields_test() ->
    %% Input: Erlang map #{name := binary(), age := integer()}
    Types = [
        {person,
            {type, 1, map, [
                {type, 1, map_field_exact, [{atom, 1, name}, {type, 1, binary, []}]},
                {type, 1, map_field_exact, [{atom, 1, age}, {type, 1, integer, []}]}
            ]}}
    ],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create an object schema with required fields
    ?assertMatch(#{<<"Person">> := _}, Schemas),
    PersonSchema = maps:get(<<"Person">>, Schemas),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, PersonSchema)),

    %% Check properties
    Properties = maps:get(<<"properties">>, PersonSchema),
    ?assertMatch(#{<<"name">> := _, <<"age">> := _}, Properties),
    ?assertEqual(#{<<"type">> => <<"string">>}, maps:get(<<"name">>, Properties)),
    ?assertEqual(#{<<"type">> => <<"integer">>}, maps:get(<<"age">>, Properties)),

    %% Check required array contains both fields
    Required = maps:get(<<"required">>, PersonSchema),
    ?assertEqual(2, length(Required)),
    ?assert(lists:member(<<"name">>, Required)),
    ?assert(lists:member(<<"age">>, Required)).

%% Test 6: Convert map with optional fields to OpenAPI object
convert_map_with_optional_fields_test() ->
    %% Input: Erlang map #{name := binary(), age => integer()}
    %% name is required (:=), age is optional (=>)
    Types = [
        {user,
            {type, 1, map, [
                {type, 1, map_field_exact, [{atom, 1, name}, {type, 1, binary, []}]},
                {type, 1, map_field_assoc, [{atom, 1, age}, {type, 1, integer, []}]}
            ]}}
    ],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create an object schema with only name in required
    ?assertMatch(#{<<"User">> := _}, Schemas),
    UserSchema = maps:get(<<"User">>, Schemas),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, UserSchema)),

    %% Check properties - both should be present
    Properties = maps:get(<<"properties">>, UserSchema),
    ?assertMatch(#{<<"name">> := _, <<"age">> := _}, Properties),
    ?assertEqual(#{<<"type">> => <<"string">>}, maps:get(<<"name">>, Properties)),
    ?assertEqual(#{<<"type">> => <<"integer">>}, maps:get(<<"age">>, Properties)),

    %% Check required array contains only name, not age
    Required = maps:get(<<"required">>, UserSchema),
    ?assertEqual(1, length(Required)),
    ?assert(lists:member(<<"name">>, Required)),
    ?assertNot(lists:member(<<"age">>, Required)).

%% Test 7: Convert union type to OpenAPI oneOf
convert_union_type_to_oneof_test() ->
    %% Input: Erlang union type: admin | user | guest
    Types = [
        {role,
            {type, 1, union, [
                {atom, 1, admin},
                {atom, 1, user},
                {atom, 1, guest}
            ]}}
    ],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create a oneOf schema
    ?assertMatch(#{<<"Role">> := _}, Schemas),
    RoleSchema = maps:get(<<"Role">>, Schemas),
    ?assertMatch(#{<<"oneOf">> := _}, RoleSchema),

    %% Check oneOf contains all three options
    OneOf = maps:get(<<"oneOf">>, RoleSchema),
    ?assertEqual(3, length(OneOf)),

    %% Check each option is a string enum with one value
    lists:foreach(
        fun(Option) ->
            ?assertEqual(<<"string">>, maps:get(<<"type">>, Option)),
            ?assertMatch(#{<<"enum">> := [_]}, Option)
        end,
        OneOf
    ).

%% Test 8: Convert list type to OpenAPI array
convert_list_type_to_array_test() ->
    %% Input: Erlang list type [binary()]
    Types = [{tags, {type, 1, list, [{type, 1, binary, []}]}}],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create an array schema with string items
    ?assertMatch(#{<<"Tags">> := _}, Schemas),
    TagsSchema = maps:get(<<"Tags">>, Schemas),
    ?assertEqual(<<"array">>, maps:get(<<"type">>, TagsSchema)),
    ?assertMatch(#{<<"items">> := _}, TagsSchema),

    %% Check items schema
    Items = maps:get(<<"items">>, TagsSchema),
    ?assertEqual(#{<<"type">> => <<"string">>}, Items).

%% Test 9: Convert nested map to OpenAPI nested object
convert_nested_map_test() ->
    %% Input: Erlang nested map #{name := binary(), address := #{city := binary(), zip := binary()}}
    Types = [
        {user_profile,
            {type, 1, map, [
                {type, 1, map_field_exact, [{atom, 1, name}, {type, 1, binary, []}]},
                {type, 1, map_field_exact, [
                    {atom, 1, address},
                    {type, 1, map, [
                        {type, 1, map_field_exact, [{atom, 1, city}, {type, 1, binary, []}]},
                        {type, 1, map_field_exact, [{atom, 1, zip}, {type, 1, binary, []}]}
                    ]}
                ]}
            ]}}
    ],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create nested object schema
    ?assertMatch(#{<<"UserProfile">> := _}, Schemas),
    ProfileSchema = maps:get(<<"UserProfile">>, Schemas),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, ProfileSchema)),

    %% Check top-level properties
    Properties = maps:get(<<"properties">>, ProfileSchema),
    ?assertMatch(#{<<"name">> := _, <<"address">> := _}, Properties),
    ?assertEqual(#{<<"type">> => <<"string">>}, maps:get(<<"name">>, Properties)),

    %% Check nested address object
    AddressSchema = maps:get(<<"address">>, Properties),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, AddressSchema)),

    %% Check nested address properties
    AddressProps = maps:get(<<"properties">>, AddressSchema),
    ?assertMatch(#{<<"city">> := _, <<"zip">> := _}, AddressProps),
    ?assertEqual(#{<<"type">> => <<"string">>}, maps:get(<<"city">>, AddressProps)),
    ?assertEqual(#{<<"type">> => <<"string">>}, maps:get(<<"zip">>, AddressProps)).

%% Test 10: Convert user type reference to OpenAPI $ref
convert_user_type_reference_test() ->
    %% Input: Two types where one references the other
    %% user_id is binary(), user has field of type user_id
    Types = [
        {user_id, {type, 1, binary, []}},
        {user,
            {type, 1, map, [
                {type, 1, map_field_exact, [{atom, 1, id}, {user_type, 1, user_id, []}]},
                {type, 1, map_field_exact, [{atom, 1, name}, {type, 1, binary, []}]}
            ]}}
    ],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create both schemas
    ?assertMatch(#{<<"UserId">> := _, <<"User">> := _}, Schemas),

    %% Check UserId schema - should be a simple string
    UserIdSchema = maps:get(<<"UserId">>, Schemas),
    ?assertEqual(#{<<"type">> => <<"string">>}, UserIdSchema),

    %% Check User schema
    UserSchema = maps:get(<<"User">>, Schemas),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, UserSchema)),

    %% Check properties
    Properties = maps:get(<<"properties">>, UserSchema),
    ?assertMatch(#{<<"id">> := _, <<"name">> := _}, Properties),

    %% id field should be a reference to UserId
    IdSchema = maps:get(<<"id">>, Properties),
    ?assertMatch(#{<<"$ref">> := _}, IdSchema),
    ?assertEqual(<<"#/components/schemas/UserId">>, maps:get(<<"$ref">>, IdSchema)),

    %% name field should be a direct string
    NameSchema = maps:get(<<"name">>, Properties),
    ?assertEqual(#{<<"type">> => <<"string">>}, NameSchema).

%% Test 11: Convert circular reference (node referencing itself)
convert_circular_reference_test() ->
    %% Input: Tree node type with circular reference
    %% node = #{value := binary(), children := [node()]}
    Types = [
        {node,
            {type, 1, map, [
                {type, 1, map_field_exact, [{atom, 1, value}, {type, 1, binary, []}]},
                {type, 1, map_field_exact, [
                    {atom, 1, children},
                    {type, 1, list, [{user_type, 1, node, []}]}
                ]}
            ]}}
    ],

    %% Execute conversion
    Schemas = rebar3_opapi_schema_converter:types_to_schemas(Types),

    %% Assert: Should create node schema without infinite recursion
    ?assertMatch(#{<<"Node">> := _}, Schemas),
    NodeSchema = maps:get(<<"Node">>, Schemas),
    ?assertEqual(<<"object">>, maps:get(<<"type">>, NodeSchema)),

    %% Check properties
    Properties = maps:get(<<"properties">>, NodeSchema),
    ?assertMatch(#{<<"value">> := _, <<"children">> := _}, Properties),

    %% Check value is a string
    ValueSchema = maps:get(<<"value">>, Properties),
    ?assertEqual(#{<<"type">> => <<"string">>}, ValueSchema),

    %% Check children is an array
    ChildrenSchema = maps:get(<<"children">>, Properties),
    ?assertEqual(<<"array">>, maps:get(<<"type">>, ChildrenSchema)),

    %% Check children items is a $ref back to Node (breaks circular reference)
    Items = maps:get(<<"items">>, ChildrenSchema),
    ?assertMatch(#{<<"$ref">> := _}, Items),
    ?assertEqual(<<"#/components/schemas/Node">>, maps:get(<<"$ref">>, Items)).
