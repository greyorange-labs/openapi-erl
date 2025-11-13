-module(rebar3_openapi_prv_extract).
-behaviour(provider).

-export([init/1, do/1, format_error/1, write_openapi_file/2]).


-define(PROVIDER, extract).
-define(DEPS, [{default, compile}]).

%%%===================================================================
%%% Public API
%%%===================================================================

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {namespace, openapi},
        {bare, true},
        {deps, ?DEPS},
        {example, "rebar3 openapi extract --handler apps/butler_shared/src/interfaces/in/gm_common_http_handler.erl --output openapi.yaml"},
        {short_desc, "Extract OpenAPI 3.0.x documentation from Erlang handler modules"},
        {desc, "Extract OpenAPI 3.0.x documentation from Erlang handler modules"},
        {opts, [
            {handler, undefined, "handler", string, "Path to handler .erl file (required)"},
            {output, undefined, "output", string, "Output file path (required)"},
            {app, undefined, "app", string, "Application name (required, for metadata)"}
        ]}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    try
        {Args, _} = rebar_state:command_parsed_args(State),

        HandlerPath = proplists:get_value(handler, Args),
        OutputPath = proplists:get_value(output, Args),
        AppName = proplists:get_value(app, Args),

        case validate_args(HandlerPath, OutputPath, AppName) of
            ok ->
                extract_and_generate(State, HandlerPath, OutputPath, AppName);
            {error, Reason} ->
                {error, format_error(Reason)}
        end
    catch
        Class:Err:Stack ->
            rebar_api:error("openapi extract failed: ~p:~p", [Class, Err]),
            rebar_api:error("Stack trace: ~p", [Stack]),
            {error, format_error({internal_error, Class, Err})}
    end.

-spec format_error(any()) -> iolist().
format_error({missing_arg, handler}) ->
    "Missing required argument: --handler <path-to-handler-erl>";
format_error({missing_arg, output}) ->
    "Missing required argument: --output <output-file-path>";
format_error({missing_arg, app}) ->
    "Missing required argument: --app <application-name>";
format_error({file_write_error, Path, Reason}) ->
    io_lib:format("Failed to write file ~s: ~p", [Path, Reason]);
format_error({file_not_found, Path}) ->
    io_lib:format("Handler file not found: ~s", [Path]);
format_error({parse_error, Reason}) ->
    io_lib:format("Failed to parse handler file: ~p", [Reason]);
format_error({internal_error, Class, Err}) ->
    io_lib:format("Internal error: ~p:~p", [Class, Err]);
format_error({extraction_error, Reason}) ->
    io_lib:format("Failed to extract contracts: ~p", [Reason]);
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%%%===================================================================
%%% Internal Functions
%%%===================================================================

-spec validate_args(term(), term(), term()) -> ok | {error, term()}.
validate_args(undefined, _, _) ->
    {error, {missing_arg, handler}};
validate_args(_, undefined, _) ->
    {error, {missing_arg, output}};
validate_args(_, _, undefined) ->
    {error, {missing_arg, app}};
validate_args(_, _, _) ->
    ok.

-spec extract_and_generate(rebar_state:t(), string(), string(), string()) ->
    {ok, rebar_state:t()} | {error, string()}.
extract_and_generate(State, HandlerPath, OutputPath, AppName) ->
    rebar_api:info("Extracting OpenAPI documentation...", []),
    rebar_api:info("  Handler: ~s", [HandlerPath]),
    rebar_api:info("  Output: ~s", [OutputPath]),
    rebar_api:info("  App: ~s", [AppName]),

    %% Validate handler file exists
    case filelib:is_file(HandlerPath) of
        false ->
            {error, {file_not_found, HandlerPath}};
        true ->
            %% Get include paths from rebar state
            IncludePaths = get_include_paths(State, HandlerPath),
            %% Parse handler file using new trails-based approach
            case parse_forms(HandlerPath, IncludePaths) of
                {ok, Forms} ->
                    %% Extract trails and types
                    Trails = try
                        rebar3_openapi_parser:extract_trails(Forms)
                    catch
                        C:E ->
                            rebar_api:warn("Failed to extract trails: ~p:~p", [C, E]),
                            []
                    end,

                    Types = rebar3_openapi_parser:extract_types(Forms),

                    rebar_api:info("Found ~p trail(s), ~p type(s)",
                        [length(Trails), length(Types)]),

                    %% Expand trails metadata (type refs -> $refs)
                    ExpandedTrails = rebar3_openapi_expander:expand_trails(Trails, Types),

                    %% Find app.src file
                    AppSrcPath = find_app_src(HandlerPath, AppName),

                    %% Build OpenAPI document from expanded trails
                    AppNameBin = list_to_binary(AppName),
                    OpenAPIDoc = rebar3_openapi_builder:build_from_trails(ExpandedTrails, Types, AppNameBin, AppSrcPath),

                    %% Write to file
                    case write_openapi_file(OutputPath, OpenAPIDoc) of
                        ok ->
                            rebar_api:info("SUCCESS: OpenAPI documentation written to ~s", [OutputPath]),
                            {ok, State};
                        {error, Reason} ->
                            {error, {file_write_error, OutputPath, Reason}}
                    end;
                {error, Reason} ->
                    {error, {parse_error, Reason}}
            end
    end.

-spec find_app_src(string(), string()) -> string() | undefined.
find_app_src(HandlerPath, AppName) ->
    %% Get app root directory (apps/butler_shared from apps/butler_shared/src/interfaces/in/file.erl)
    AppRoot = filename:dirname(filename:dirname(filename:dirname(HandlerPath))),
    %% Try src/<app_name>.app.src first
    AppSrcPath1 = filename:join([AppRoot, "src", AppName ++ ".app.src"]),
    case filelib:is_file(AppSrcPath1) of
        true ->
            AppSrcPath1;
        false ->
            %% Try <app_name>.app.src in app root
            AppSrcPath2 = filename:join([AppRoot, AppName ++ ".app.src"]),
            case filelib:is_file(AppSrcPath2) of
                true ->
                    AppSrcPath2;
                false ->
                    undefined
            end
    end.

-spec get_include_paths(rebar_state:t(), string()) -> [string()].
get_include_paths(_State, HandlerPath) ->
    %% Get app root directory (apps/butler_shared from apps/butler_shared/src/interfaces/in/file.erl)
    AppRoot = filename:dirname(filename:dirname(filename:dirname(HandlerPath))),
    IncludeDir = filename:join([AppRoot, "include"]),
    SrcDir = filename:dirname(HandlerPath),
    %% Include app root for relative includes like -include("src/gm_common.hrl")
    [AppRoot, IncludeDir, SrcDir].

-spec parse_forms(string(), [string()]) -> {ok, [erl_parse:abstract_form()]} | {error, term()}.
parse_forms(FilePath, IncludePaths) ->
    %% Use epp:parse_file/2 to handle includes and parse forms
    Options = [{includes, IncludePaths}],
    case epp:parse_file(FilePath, Options) of
        {ok, Forms} ->
            {ok, Forms};
        {error, Error} ->
            {error, {parse_error, Error}}
    end.

-spec write_openapi_file(string(), map()) -> ok | {error, term()}.
write_openapi_file(OutputPath, OpenAPIDoc) ->
    %% Determine format from file extension
    case filename:extension(OutputPath) of
        ".yaml" ->
            write_yaml_file(OutputPath, OpenAPIDoc);
        ".yml" ->
            write_yaml_file(OutputPath, OpenAPIDoc);
        ".json" ->
            write_json_file(OutputPath, OpenAPIDoc);
        _ ->
            %% Default to YAML
            write_yaml_file(OutputPath ++ ".yaml", OpenAPIDoc)
    end.

-spec write_yaml_file(string(), map()) -> ok | {error, term()}.
write_yaml_file(FilePath, Doc) ->
    try
        %% Generate JSON first, then convert to YAML using CLI tool
        %% This avoids YAML quoting and formatting issues
        %% Convert map to ordered proplist to preserve field order
        OrderedDoc = map_to_ordered_proplist(Doc),
        JSON = jsx:encode(OrderedDoc),

        %% Write JSON to temporary file
        TmpJSONFile = FilePath ++ ".tmp.json",
        case file:write_file(TmpJSONFile, JSON) of
            ok ->
                %% Convert JSON to YAML using yq or jq
                case convert_json_to_yaml(TmpJSONFile, FilePath) of
                    ok ->
                        %% Clean up temp file
                        file:delete(TmpJSONFile),
                        ok;
                    {error, ConvReason} ->
                        %% Clean up temp file
                        file:delete(TmpJSONFile),
                        {error, {conversion_error, ConvReason}}
                end;
            {error, WriteReason} ->
                {error, {file_write_error, TmpJSONFile, WriteReason}}
        end
    catch
        Class:ErrReason ->
            {error, {Class, ErrReason}}
    end.

-spec convert_json_to_yaml(string(), string()) -> ok | {error, string()}.
convert_json_to_yaml(JSONFile, YAMLFile) ->
    %% Try yq first (better YAML output), then jq as fallback
    case os:find_executable("yq") of
        YqPath when YqPath =/= false ->
            %% Use yq v4: yq -o yaml . json_file > yaml_file
            %% For yq v4, use -o yaml flag for YAML output
            Cmd = io_lib:format("~s -o yaml . ~s > ~s 2>&1", [YqPath, JSONFile, YAMLFile]),
            Output = os:cmd(lists:flatten(Cmd)),
            case filelib:is_file(YAMLFile) of
                true ->
                    ok;
                false ->
                    {error, lists:flatten(io_lib:format("yq failed: ~s", [Output]))}
            end;
        false ->
            {error, "yq not found - please install yq for JSON to YAML conversion"}
    end.

-spec write_json_file(string(), map()) -> ok | {error, term()}.
write_json_file(FilePath, Doc) ->
    try
        %% Convert map to ordered proplist to preserve field order
        OrderedDoc = map_to_ordered_proplist(Doc),
        JSON = jsx:encode(OrderedDoc),
        file:write_file(FilePath, JSON)
    catch
        Class:ErrReason ->
            {error, {Class, ErrReason}}
    end.

%% @doc Convert OpenAPI document map to ordered proplist for JSON encoding
%% OpenAPI 3.0.3 spec requires: openapi, info, servers, paths, components
-spec map_to_ordered_proplist(map()) -> [{binary(), term()}].
map_to_ordered_proplist(Doc) ->
    %% Define the required field order for OpenAPI 3.0.3
    OrderedKeys = [
        <<"openapi">>,
        <<"info">>,
        <<"servers">>,
        <<"paths">>,
        <<"components">>,
        <<"security">>
    ],
    %% Build proplist in order, then add any remaining keys
    %% Fold over reversed keys to build list in correct order (no need to reverse result)
    OrderedPairs = lists:foldl(
        fun(Key, Acc) ->
            case maps:get(Key, Doc, undefined) of
                undefined -> Acc;
                Value -> [{Key, convert_value_to_proplist(Value)} | Acc]
            end
        end,
        [],
        lists:reverse(OrderedKeys)
    ),
    %% Add any remaining keys not in the ordered list
    AllKeys = maps:keys(Doc),
    RemainingKeys = lists:filter(
        fun(K) -> not lists:member(K, OrderedKeys) end,
        AllKeys
    ),
    RemainingPairs = lists:map(
        fun(Key) ->
            Value = maps:get(Key, Doc),
            {Key, convert_value_to_proplist(Value)}
        end,
        RemainingKeys
    ),
    %% OrderedPairs is already in correct order (openapi first), don't reverse it
    OrderedPairs ++ RemainingPairs.

%% @doc Recursively convert map values to proplists to preserve order
-spec convert_value_to_proplist(term()) -> term().
convert_value_to_proplist(Map) when is_map(Map) ->
    %% For nested maps, convert to proplist but don't enforce specific order
    %% (only top-level OpenAPI fields need ordering)
    maps:to_list(Map);
convert_value_to_proplist(List) when is_list(List) ->
    lists:map(fun convert_value_to_proplist/1, List);
convert_value_to_proplist(Value) ->
    Value.
