%%%-------------------------------------------------------------------
%%% @author amarBitMan <https://github.com/amarBitMan>
%%% @copyright (C) 2025, Grey Orange
%%%-------------------------------------------------------------------
-module(rebar3_openapi_expander).

-moduledoc """
----------------------------------------------------------------------
Metadata Expander for OpenAPI 3.0.x

Expands type references in trails metadata to full OpenAPI 3.0.x
compliant structures with $ref paths.

Key responsibilities:
1. Generate unique operationId for each operation
2. Expand type references (atoms) to $ref paths
3. Ensure OpenAPI 3.0.x structure compliance
4. Validate metadata structure
----------------------------------------------------------------------
""".

-export([
    expand_trails/2,
    expand_trail/2,
    expand_operation/4,
    generate_operation_id/2,
    expand_parameters/2,
    expand_request_body/2,
    expand_responses/2,
    type_ref_to_schema_ref/1
]).

-export_type([trail/0, expanded_trail/0]).

%%%===================================================================
%%% Types
%%%===================================================================

-type trail() :: #{
    path => binary(),
    handler => atom(),
    options => map() | list(),
    % Map of method => operation_metadata
    metadata => map()
}.

-type expanded_trail() :: #{
    path => binary(),
    handler => atom(),
    options => map() | list(),
    % Expanded metadata with $refs
    metadata => map()
}.

-type type_def() :: {atom(), erl_parse:abstract_type()}.

%%%===================================================================
%%% Public API
%%%===================================================================

-doc """
----------------------------------------------------------------------
Expand all trails with type references
----------------------------------------------------------------------
""".
-spec expand_trails([trail()], [type_def()]) -> [expanded_trail()].
expand_trails(Trails, Types) ->
    lists:map(fun(Trail) -> expand_trail(Trail, Types) end, Trails).

-doc """
----------------------------------------------------------------------
Expand a single trail
----------------------------------------------------------------------
""".
-spec expand_trail(trail(), [type_def()]) -> expanded_trail().
expand_trail(Trail, Types) ->
    %% trails:trail() returns a map with path_match or path key
    Path =
        case maps:find(path, Trail) of
            {ok, P} ->
                P;
            error ->
                case maps:find(path_match, Trail) of
                    {ok, PM} -> list_to_binary(PM);
                    error -> throw({missing_path_key, Trail})
                end
        end,
    Metadata = maps:get(metadata, Trail),
    ExpandedMetadata = expand_metadata(Path, Metadata, Types),
    Trail#{metadata => ExpandedMetadata, path => Path}.

-doc false.
-spec expand_metadata(binary(), map(), [type_def()]) -> map().
expand_metadata(Path, Metadata, Types) ->
    maps:map(
        fun
            (Method, OperationMeta) when is_atom(Method) ->
                expand_operation(Path, Method, OperationMeta, Types);
            (_, Value) ->
                Value
        end,
        Metadata
    ).

-doc """
----------------------------------------------------------------------
Expand a single operation (method) metadata
----------------------------------------------------------------------
""".
-spec expand_operation(binary(), atom(), map(), [type_def()]) -> map().
expand_operation(Path, Method, OperationMeta, Types) ->
    %% 1. Generate operationId if not present
    OperationId =
        case maps:get(operationId, OperationMeta, undefined) of
            undefined -> generate_operation_id(Path, Method);
            ExistingId -> ExistingId
        end,

    %% 2. Start with existing metadata + operationId
    BaseMeta = OperationMeta#{operationId => OperationId},

    %% 3. Expand parameters if present
    Meta1 =
        case maps:get(parameters, BaseMeta, undefined) of
            undefined -> BaseMeta;
            Params -> BaseMeta#{parameters => expand_parameters(Params, Types)}
        end,

    %% 4. Expand requestBody if present
    Meta2 =
        case maps:get(requestBody, Meta1, undefined) of
            undefined -> Meta1;
            ReqBody -> Meta1#{requestBody => expand_request_body(ReqBody, Types)}
        end,

    %% 5. Expand responses if present
    Meta3 =
        case maps:get(responses, Meta2, undefined) of
            undefined -> Meta2;
            Responses -> Meta2#{responses => expand_responses(Responses, Types)}
        end,

    Meta3.

-doc """
----------------------------------------------------------------------
Generate unique operationId from path and method
----------------------------------------------------------------------
""".
-spec generate_operation_id(binary(), atom()) -> binary().
generate_operation_id(Path, Method) ->
    %% Convert method to string
    MethodStr = atom_to_list(Method),
    MethodBin = list_to_binary(MethodStr),

    %% Clean up path: remove leading slash, replace special chars
    CleanPath = clean_path_for_id(Path),

    %% Combine: methodPath (e.g., "getUserById", "createUser")
    <<MethodBin/binary, CleanPath/binary>>.

-doc false.
-spec clean_path_for_id(binary()) -> binary().
clean_path_for_id(Path) ->
    %% Split by / and process each segment
    Segments = binary:split(Path, <<"/">>, [global, trim_all]),

    %% Process each segment
    ProcessedSegments = lists:map(fun process_path_segment/1, Segments),

    %% Join all segments
    list_to_binary(ProcessedSegments).

-doc false.
-spec process_path_segment(binary()) -> binary().
process_path_segment(<<":"/utf8, Rest/binary>>) ->
    %% Path parameter like ":id" -> "ById"
    <<"By", (capitalize_first(Rest))/binary>>;
process_path_segment(Segment) ->
    %% Regular segment - capitalize first letter
    capitalize_first(Segment).

-doc false.
-spec capitalize_first(binary()) -> binary().
capitalize_first(<<>>) ->
    <<>>;
capitalize_first(<<First:8, Rest/binary>>) when First >= $a, First =< $z ->
    <<(First - 32):8, Rest/binary>>;
capitalize_first(Bin) ->
    Bin.

-doc """
----------------------------------------------------------------------
Expand parameters list
----------------------------------------------------------------------
""".
-spec expand_parameters([map()], [type_def()]) -> [map()].
expand_parameters(Parameters, Types) ->
    lists:map(fun(Param) -> expand_parameter(Param, Types) end, Parameters).

-doc false.
-spec expand_parameter(map(), [type_def()]) -> map().
expand_parameter(#{schema := {nullable, TypeRef}} = Param, Types) when is_atom(TypeRef) ->
    %% Nullable type reference -> oneOf: [inner_schema, {type: null}]
    InnerSchema = resolve_type_to_schema(TypeRef, Types),
    NullableSchema = #{<<"oneOf">> => [InnerSchema, #{<<"type">> => <<"null">>}]},
    Param#{schema => NullableSchema};
expand_parameter(#{schema := TypeRef} = Param, Types) when is_atom(TypeRef) ->
    %% Check if it's a primitive type or a user-defined type
    Param#{schema => resolve_type_to_schema(TypeRef, Types)};
expand_parameter(Param, _Types) ->
    %% No type reference or already expanded
    Param.

-doc """
----------------------------------------------------------------------
Expand requestBody
----------------------------------------------------------------------
""".
-spec expand_request_body(map(), [type_def()]) -> map().
expand_request_body(#{content := Content} = ReqBody, Types) ->
    ExpandedContent = maps:map(
        fun(_MediaType, MediaTypeMeta) ->
            expand_media_type_schema(MediaTypeMeta, Types)
        end,
        Content
    ),
    ReqBody#{content => ExpandedContent};
expand_request_body(ReqBody, _Types) ->
    ReqBody.

-doc """
----------------------------------------------------------------------
Expand responses map
----------------------------------------------------------------------
""".
-spec expand_responses(map(), [type_def()]) -> map().
expand_responses(Responses, Types) ->
    maps:map(
        fun(_StatusCode, ResponseMeta) ->
            expand_response(ResponseMeta, Types)
        end,
        Responses
    ).

-doc false.
-spec expand_response(map(), [type_def()]) -> map().
expand_response(#{content := Content} = Response, Types) ->
    ExpandedContent = maps:map(
        fun(_MediaType, MediaTypeMeta) ->
            expand_media_type_schema(MediaTypeMeta, Types)
        end,
        Content
    ),
    Response#{content => ExpandedContent};
expand_response(Response, _Types) ->
    Response.

-doc false.
-spec expand_media_type_schema(map(), [type_def()]) -> map().
expand_media_type_schema(#{schema := {array, ItemType}} = MediaTypeMeta, Types) when is_atom(ItemType) ->
    %% Array type reference - expand to OpenAPI array schema
    ItemsSchema = resolve_type_to_schema(ItemType, Types),
    MediaTypeMeta#{
        schema => #{
            <<"type">> => <<"array">>,
            <<"items">> => ItemsSchema
        }
    };
expand_media_type_schema(#{schema := {nullable, TypeRef}} = MediaTypeMeta, Types) when is_atom(TypeRef) ->
    %% Nullable type reference -> oneOf: [inner_schema, {type: null}]
    InnerSchema = resolve_type_to_schema(TypeRef, Types),
    NullableSchema = #{<<"oneOf">> => [InnerSchema, #{<<"type">> => <<"null">>}]},
    MediaTypeMeta#{schema => NullableSchema};
expand_media_type_schema(#{schema := {nullable, {array, ItemType}}} = MediaTypeMeta, Types) when is_atom(ItemType) ->
    %% Nullable array -> oneOf: [{type: array, items: ...}, {type: null}]
    ItemsSchema = resolve_type_to_schema(ItemType, Types),
    ArraySchema = #{<<"type">> => <<"array">>, <<"items">> => ItemsSchema},
    NullableSchema = #{<<"oneOf">> => [ArraySchema, #{<<"type">> => <<"null">>}]},
    MediaTypeMeta#{schema => NullableSchema};
expand_media_type_schema(#{schema := TypeRef} = MediaTypeMeta, Types) when is_atom(TypeRef) ->
    MediaTypeMeta#{schema => resolve_type_to_schema(TypeRef, Types)};
expand_media_type_schema(MediaTypeMeta, _Types) ->
    MediaTypeMeta.

-doc """
----------------------------------------------------------------------
Convert type atom to OpenAPI $ref path
----------------------------------------------------------------------
""".
-spec type_ref_to_schema_ref(atom()) -> binary().
type_ref_to_schema_ref(TypeName) ->
    %% Capitalize type name (user_id -> UserId)
    CapitalizedName = gm_type_schema_converter:capitalize_type_name(TypeName),
    <<"#/components/schemas/", CapitalizedName/binary>>.

-doc false.
-spec resolve_type_to_schema(atom(), [type_def()]) -> map().
resolve_type_to_schema(TypeRef, _Types) ->
    case is_primitive_type(TypeRef) of
        true ->
            primitive_type_to_schema(TypeRef);
        false ->
            SchemaRef = type_ref_to_schema_ref(TypeRef),
            #{<<"$ref">> => SchemaRef}
    end.

-doc false.
-spec is_primitive_type(atom()) -> boolean().
is_primitive_type(binary) -> true;
is_primitive_type(integer) -> true;
is_primitive_type(float) -> true;
is_primitive_type(boolean) -> true;
is_primitive_type(non_neg_integer) -> true;
is_primitive_type(pos_integer) -> true;
is_primitive_type(neg_integer) -> true;
is_primitive_type(number) -> true;
is_primitive_type(string) -> true;
is_primitive_type(atom) -> true;
is_primitive_type(term) -> true;
is_primitive_type(any) -> true;
is_primitive_type(timeout) -> true;
is_primitive_type(byte) -> true;
is_primitive_type(char) -> true;
is_primitive_type(arity) -> true;
is_primitive_type(Binary) when Binary =:= <<"binary">> -> true;
is_primitive_type(Integer) when Integer =:= <<"integer">> -> true;
is_primitive_type(Float) when Float =:= <<"float">> -> true;
is_primitive_type(Boolean) when Boolean =:= <<"boolean">> -> true;
is_primitive_type(_) -> false.

-doc false.
-spec primitive_type_to_schema(atom()) -> map().
primitive_type_to_schema(binary) ->
    #{<<"type">> => <<"string">>};
primitive_type_to_schema(integer) ->
    #{<<"type">> => <<"integer">>};
primitive_type_to_schema(float) ->
    #{<<"type">> => <<"number">>};
primitive_type_to_schema(boolean) ->
    #{<<"type">> => <<"boolean">>};
primitive_type_to_schema(non_neg_integer) ->
    #{<<"type">> => <<"integer">>, <<"minimum">> => 0};
primitive_type_to_schema(pos_integer) ->
    #{<<"type">> => <<"integer">>, <<"minimum">> => 1};
primitive_type_to_schema(neg_integer) ->
    #{<<"type">> => <<"integer">>, <<"maximum">> => -1};
primitive_type_to_schema(number) ->
    #{<<"type">> => <<"number">>};
primitive_type_to_schema(string) ->
    #{<<"type">> => <<"string">>};
primitive_type_to_schema(atom) ->
    #{<<"type">> => <<"string">>};
primitive_type_to_schema(term) ->
    #{};
primitive_type_to_schema(any) ->
    #{};
primitive_type_to_schema(timeout) ->
    #{
        <<"oneOf">> => [
            #{<<"type">> => <<"integer">>, <<"minimum">> => 0},
            #{<<"type">> => <<"string">>, <<"enum">> => [<<"infinity">>]}
        ]
    };
primitive_type_to_schema(byte) ->
    #{<<"type">> => <<"integer">>, <<"minimum">> => 0, <<"maximum">> => 255};
primitive_type_to_schema(char) ->
    #{<<"type">> => <<"integer">>, <<"minimum">> => 0, <<"maximum">> => 1114111};
primitive_type_to_schema(arity) ->
    #{<<"type">> => <<"integer">>, <<"minimum">> => 0, <<"maximum">> => 255};
primitive_type_to_schema(_) ->
    %% Fallback for unknown primitive types
    #{<<"type">> => <<"string">>}.
