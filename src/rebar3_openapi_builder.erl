-module(rebar3_openapi_builder).

%%%===================================================================
%%% OpenAPI Document Builder
%%%===================================================================
%%%
%%% Builds complete OpenAPI 3.0.x document structure from expanded trails.
%%% Updated to work with the new trails-based approach.
%%%
%%%===================================================================

-export([
    build/3,
    build_from_trails/4,
    build_from_trails/5,
    build_paths_from_trails/1,
    build_components/1,
    build_info/3
]).

%%%===================================================================
%%% Public API
%%%===================================================================

%% @doc Build OpenAPI document from expanded trails (new approach)
-spec build_from_trails([expanded_trail()], [type_def()], AppName :: atom() | binary(), AppSrcPath :: string() | undefined) ->
    map().
build_from_trails(Trails, Types, AppName, AppSrcPath) ->
    build_from_trails(Trails, Types, AppName, AppSrcPath, undefined).

-spec build_from_trails(
    [expanded_trail()],
    [type_def()],
    AppName :: atom() | binary(),
    AppSrcPath :: string() | undefined,
    WorkspaceRoot :: string() | undefined
) -> map().
build_from_trails(Trails, Types, AppName, AppSrcPath, WorkspaceRoot) ->
    #{
        <<"openapi">> => <<"3.0.3">>,
        <<"info">> => build_info(AppName, AppSrcPath, WorkspaceRoot),
        <<"servers">> => build_servers(),
        <<"paths">> => build_paths_from_trails(Trails),
        <<"components">> => build_components(Types),
        % Empty array indicates no security required (satisfies security-defined rule)
        <<"security">> => []
    }.

%% @doc Build OpenAPI document from operations (legacy approach)
-spec build([operation()], [type_def()], AppName :: atom() | binary()) -> map().
build(Operations, Types, AppName) ->
    #{
        <<"openapi">> => <<"3.0.3">>,
        <<"info">> => build_info(AppName, undefined, undefined),
        <<"servers">> => build_servers(),
        <<"paths">> => build_paths(Operations),
        <<"components">> => build_components(Types)
    }.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

-spec build_info(atom() | binary(), string() | undefined, string() | undefined) -> map().
build_info(AppName, AppSrcPath, WorkspaceRoot) when is_atom(AppName) ->
    AppNameBin = atom_to_binary(AppName),
    {Version, Description} = read_app_src_info(AppSrcPath, WorkspaceRoot),
    #{
        <<"title">> => AppNameBin,
        <<"version">> => Version,
        <<"description">> => Description
    };
build_info(AppName, AppSrcPath, WorkspaceRoot) when is_binary(AppName) ->
    {Version, Description} = read_app_src_info(AppSrcPath, WorkspaceRoot),
    #{
        <<"title">> => AppName,
        <<"version">> => Version,
        <<"description">> => Description
    }.

-spec read_app_src_info(string() | undefined, string() | undefined) -> {binary(), binary()}.
read_app_src_info(undefined, _WorkspaceRoot) ->
    {<<"1.0.0">>, <<"API documentation generated from Erlang handler modules">>};
read_app_src_info(AppSrcPath, WorkspaceRoot) ->
    case file:consult(AppSrcPath) of
        {ok, [Term]} ->
            case extract_app_info(Term, AppSrcPath, WorkspaceRoot) of
                {ok, Version, Description} ->
                    {Version, Description};
                error ->
                    {<<"1.0.0">>, <<"API documentation generated from Erlang handler modules">>}
            end;
        {error, _Reason} ->
            {<<"1.0.0">>, <<"API documentation generated from Erlang handler modules">>}
    end.

-spec extract_app_info(term(), string(), string() | undefined) -> {ok, binary(), binary()} | error.
extract_app_info({application, _AppName, AppList}, AppSrcPath, WorkspaceRoot) when is_list(AppList) ->
    %% Extract version and description from application list
    Version = extract_version_from_list(AppList, AppSrcPath, WorkspaceRoot),
    Description = extract_description_from_list(AppList),
    {ok, Version, Description};
extract_app_info(_, _, _) ->
    error.

-spec extract_version_from_list([term()], string(), string() | undefined) -> binary().
extract_version_from_list([], _AppSrcPath, _WorkspaceRoot) ->
    <<"1.0.0">>;
extract_version_from_list([{vsn, Version} | _Rest], AppSrcPath, WorkspaceRoot) ->
    case Version of
        {cmd, Cmd} ->
            %% Version is from command, execute it
            CmdStr = case Cmd of
                CmdList when is_list(CmdList) -> CmdList;
                CmdBin when is_binary(CmdBin) -> binary_to_list(CmdBin);
                _ -> ""
            end,
            execute_version_cmd(CmdStr, AppSrcPath, WorkspaceRoot);
        VersionStr when is_list(VersionStr) ->
            list_to_binary(VersionStr);
        VersionBin when is_binary(VersionBin) ->
            VersionBin;
        _ ->
            <<"1.0.0">>
    end;
extract_version_from_list([_ | Rest], AppSrcPath, WorkspaceRoot) ->
    extract_version_from_list(Rest, AppSrcPath, WorkspaceRoot).

-spec execute_version_cmd(string(), string(), string() | undefined) -> binary().
execute_version_cmd(Cmd, AppSrcPath, WorkspaceRoot) ->
    %% Resolve command path relative to app.src file location
    AppSrcDir = filename:dirname(AppSrcPath),
    CmdPath = filename:absname(Cmd, AppSrcDir),

    %% If workspace root is provided and command path is relative, try resolving from workspace root
    FinalCmdPath =
        case WorkspaceRoot of
            undefined ->
                CmdPath;
            Root when is_list(Root) ->
                %% Try workspace root first, then fallback to app.src relative
                WorkspaceCmdPath = filename:absname(Cmd, Root),
                case filelib:is_file(WorkspaceCmdPath) of
                    true -> WorkspaceCmdPath;
                    false -> CmdPath
                end
        end,

    %% Execute the command (try even if file check fails, in case of permission issues)
    case filelib:is_file(FinalCmdPath) of
        true ->
            %% Make script executable and run it
            _ = os:cmd("chmod +x " ++ FinalCmdPath ++ " 2>/dev/null"),
            case os:cmd("bash " ++ FinalCmdPath) of
                [] ->
                    <<"1.0.0">>;
                Output ->
                    %% Trim whitespace and newlines
                    Trimmed = string:trim(Output, both, "\n\r\t "),
                    case Trimmed of
                        [] -> <<"1.0.0">>;
                        _ -> list_to_binary(Trimmed)
                    end
            end;
        false ->
            %% Try executing anyway (might be in PATH or relative path issue)
            case os:cmd("bash " ++ FinalCmdPath) of
                [] ->
                    <<"1.0.0">>;
                Output ->
                    Trimmed = string:trim(Output, both, "\n\r\t "),
                    case Trimmed of
                        [] -> <<"1.0.0">>;
                        _ -> list_to_binary(Trimmed)
                    end
            end
    end.

-spec extract_description_from_list([term()]) -> binary().
extract_description_from_list([]) ->
    <<"API documentation generated from Erlang handler modules">>;
extract_description_from_list([{description, Desc} | _Rest]) ->
    case Desc of
        DescStr when is_list(DescStr) ->
            list_to_binary(DescStr);
        DescBin when is_binary(DescBin) ->
            DescBin;
        _ ->
            <<"API documentation generated from Erlang handler modules">>
    end;
extract_description_from_list([_ | Rest]) ->
    extract_description_from_list(Rest).

-spec build_servers() -> [map()].
build_servers() ->
    [
        #{
            <<"url">> => <<"http://localhost:8181">>,
            <<"description">> => <<"Development server">>
        }
    ].

%% @doc Build paths from trails (new approach)
-spec build_paths_from_trails([expanded_trail()]) -> map().
build_paths_from_trails(Trails) ->
    lists:foldl(
        fun(Trail, Acc) ->
            Path = maps:get(path, Trail),
            Metadata = maps:get(metadata, Trail),

            %% Convert OpenAPI path format (:id -> {id})
            OpenAPIPath = convert_path_params(Path),

            %% Process each method in metadata
            PathMethods = maps:fold(
                fun
                    (Method, OperationMeta, MethodAcc) when is_atom(Method) ->
                        %% Convert metadata to OpenAPI operation object
                        OpObj = operation_meta_to_openapi(OperationMeta),
                        MethodBin = method_to_lowercase(Method),
                        MethodAcc#{MethodBin => OpObj};
                    (_, _, MethodAcc) ->
                        %% Skip non-method keys
                        MethodAcc
                end,
                #{},
                Metadata
            ),

            %% Merge with existing path operations
            ExistingPath = maps:get(OpenAPIPath, Acc, #{}),
            Acc#{OpenAPIPath => maps:merge(ExistingPath, PathMethods)}
        end,
        #{},
        Trails
    ).

%% @doc Convert metadata to OpenAPI operation object
-spec operation_meta_to_openapi(map()) -> map().
operation_meta_to_openapi(Meta) ->
    %% Start with operationId (should already be present from expander)
    BaseOp =
        case maps:get(operationId, Meta, undefined) of
            undefined -> #{};
            OpId -> #{<<"operationId">> => OpId}
        end,

    %% Add optional fields
    Op1 = add_if_present(BaseOp, <<"tags">>, maps:get(tags, Meta, undefined)),
    Op2 = add_if_present(Op1, <<"summary">>, maps:get(summary, Meta, undefined)),
    Op3 = add_if_present(Op2, <<"description">>, maps:get(description, Meta, undefined)),
    Op4 = add_if_present(Op3, <<"parameters">>, maps:get(parameters, Meta, undefined)),
    Op5 = add_if_present(Op4, <<"requestBody">>, maps:get(requestBody, Meta, undefined)),
    Op6 = add_if_present(Op5, <<"responses">>, maps:get(responses, Meta, undefined)),

    Op6.

%% @doc Add field to map if value is not undefined
-spec add_if_present(map(), binary(), term()) -> map().
add_if_present(Map, _Key, undefined) -> Map;
add_if_present(Map, Key, Value) -> Map#{Key => Value}.

%% @doc Convert Cowboy path params to OpenAPI format (:id -> {id})
-spec convert_path_params(binary()) -> binary().
convert_path_params(Path) ->
    %% Replace :param with {param}
    re:replace(Path, <<":([a-zA-Z_][a-zA-Z0-9_]*)">>, <<"{\\1}">>, [global, {return, binary}]).

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
            OpObj1 =
                case maps:get(request_body, Operation, undefined) of
                    undefined ->
                        OpObj;
                    RequestBody ->
                        OpObj#{<<"requestBody">> => RequestBody}
                end,

            %% Add responses
            OpObj2 = OpObj1#{<<"responses">> => maps:get(responses, Operation, #{})},

            %% Add parameters if present
            OpObj3 =
                case maps:get(parameters, Operation, []) of
                    [] ->
                        OpObj2;
                    Params ->
                        OpObj2#{<<"parameters">> => Params}
                end,

            %% Group by path
            PathBin =
                case is_binary(Path) of
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

%% @doc Build components section with schemas
-spec build_components([type_def()]) -> map().
build_components(Types) ->
    %% Convert type definitions to OpenAPI schemas
    Schemas = extract_schemas(Types),
    #{
        <<"schemas">> => Schemas
    }.

-spec extract_schemas([type_def()]) -> map().
extract_schemas(Types) ->
    %% Use schema converter to transform Erlang types to OpenAPI schemas
    rebar3_openapi_schema_converter:types_to_schemas(Types).

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
    MethodBin =
        case is_atom(Method) of
            true -> atom_to_binary(Method, utf8);
            false -> list_to_binary(io_lib:format("~p", [Method]))
        end,
    MethodStr = binary_to_list(MethodBin),
    MethodLower = string:to_lower(MethodStr),
    list_to_binary(MethodLower).

%%%===================================================================
%%% Types
%%%===================================================================

-type expanded_trail() :: #{
    path => binary(),
    handler => atom(),
    options => map() | list(),
    % Expanded metadata with $refs
    metadata => map()
}.

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

-type type_def() :: {atom(), erl_parse:abstract_type()}.
