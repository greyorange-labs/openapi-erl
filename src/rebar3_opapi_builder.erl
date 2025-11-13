-module(rebar3_opapi_builder).

%%%===================================================================
%%% OpenAPI Document Builder
%%%===================================================================
%%%
%%% Builds complete OpenAPI 3.0.x document structure from extracted
%%% operations.
%%%
%%%===================================================================

-export([build/2]).

%%%===================================================================
%%% Public API
%%%===================================================================

-spec build([operation()], AppName :: atom() | binary()) -> map().
build(Operations, AppName) ->
    #{
        <<"openapi">> => <<"3.0.3">>,
        <<"info">> => build_info(AppName),
        <<"servers">> => build_servers(),
        <<"paths">> => build_paths(Operations),
        <<"components">> => build_components(Operations, AppName)
    }.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

-spec build_info(atom() | binary()) -> map().
build_info(AppName) when is_atom(AppName) ->
    #{
        <<"title">> => atom_to_binary(AppName),
        <<"version">> => <<"1.0.0">>,
        <<"description">> => <<"API documentation generated from Erlang handler modules">>
    };
build_info(AppName) when is_binary(AppName) ->
    #{
        <<"title">> => AppName,
        <<"version">> => <<"1.0.0">>,
        <<"description">> => <<"API documentation generated from Erlang handler modules">>
    }.

-spec build_servers() -> [map()].
build_servers() ->
    [
        #{
            <<"url">> => <<"http://localhost:8181">>,
            <<"description">> => <<"Development server">>
        }
    ].

-spec build_paths([operation()]) -> map().
build_paths(Operations) ->
    lists:foldl(
        fun(Operation, Acc) ->
            Path = maps:get(path, Operation),
            Method = maps:get(method, Operation),
            OperationId = maps:get(operation_id, Operation),

            %% Build operation object
            OpObj = #{
                <<"operationId">> => atom_to_binary(OperationId),
                <<"summary">> => maps:get(summary, Operation, <<>>),
                <<"description">> => maps:get(description, Operation, <<>>),
                <<"tags">> => maps:get(tags, Operation, [])
            },

            %% Add request body if present
            OpObj1 = case maps:get(request_body, Operation, undefined) of
                undefined ->
                    OpObj;
                RequestBody ->
                    OpObj#{<<"requestBody">> => RequestBody}
            end,

            %% Add responses
            OpObj2 = OpObj1#{<<"responses">> => maps:get(responses, Operation, #{})},

            %% Add parameters if present
            OpObj3 = case maps:get(parameters, Operation, []) of
                [] ->
                    OpObj2;
                Params ->
                    OpObj2#{<<"parameters">> => Params}
            end,

            %% Group by path
            PathBin = case is_binary(Path) of
                true -> Path;
                false -> list_to_binary(Path)
            end,
            MethodBin = method_to_lowercase(Method),
            ExistingPath = maps:get(PathBin, Acc, #{}),
            Acc#{PathBin => ExistingPath#{MethodBin => OpObj3}}
        end,
        #{},
        Operations
    ).

-spec build_components([operation()], atom() | binary()) -> map().
build_components(Operations, AppName) ->
    %% Extract all schemas from operations
    Schemas = extract_schemas(Operations, AppName),
    #{
        <<"schemas">> => Schemas
    }.

-spec extract_schemas([operation()], atom() | binary()) -> map().
extract_schemas(_Operations, _AppName) ->
    %% For now, return empty schemas
    %% Schemas will be extracted from type definitions in future enhancement
    #{}.

-spec method_to_lowercase(binary() | list()) -> binary().
method_to_lowercase(Method) when is_binary(Method) ->
    MethodStr = binary_to_list(Method),
    MethodLower = string:to_lower(MethodStr),
    list_to_binary(MethodLower);
method_to_lowercase(Method) when is_list(Method) ->
    MethodLower = string:to_lower(Method),
    list_to_binary(MethodLower);
method_to_lowercase(Method) ->
    %% Handle other types (atom, etc.) by converting to binary first
    MethodBin = case is_atom(Method) of
        true -> atom_to_binary(Method, utf8);
        false -> list_to_binary(io_lib:format("~p", [Method]))
    end,
    MethodStr = binary_to_list(MethodBin),
    MethodLower = string:to_lower(MethodStr),
    list_to_binary(MethodLower).

%%%===================================================================
%%% Types
%%%===================================================================

-type operation() :: #{
    operation_id => atom(),
    method => binary(),
    path => binary(),
    summary => binary(),
    description => binary(),
    tags => [binary()],
    request_body => map() | undefined,
    responses => map(),
    parameters => [map()]
}.

