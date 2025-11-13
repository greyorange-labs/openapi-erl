-module(rebar3_opapi_prv_extract).
-behaviour(provider).

-export([init/1, do/1, format_error/1]).


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
        {namespace, opapi},
        {bare, true},
        {deps, ?DEPS},
        {example, "rebar3 opapi extract --handler apps/butler_shared/src/interfaces/in/gm_common_http_handler.erl --output openapi.yaml"},
        {short_desc, "Extract OpenAPI 3.0.x documentation from Erlang handler modules"},
        {desc, "Extract OpenAPI 3.0.x documentation from Erlang handler modules"},
        {opts, [
            {handler, undefined, "handler", string, "Path to handler .erl file (required)"},
            {output, undefined, "output", string, "Output file path (required)"},
            {app, undefined, "app", string, "Application name (optional, for metadata)"}
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

        case validate_args(HandlerPath, OutputPath) of
            ok ->
                extract_and_generate(State, HandlerPath, OutputPath, AppName);
            {error, Reason} ->
                {error, format_error(Reason)}
        end
    catch
        Class:Err:Stack ->
            rebar_api:error("opapi extract failed: ~p:~p", [Class, Err]),
            rebar_api:error("Stack trace: ~p", [Stack]),
            {error, format_error({internal_error, Class, Err})}
    end.

-spec format_error(any()) -> iolist().
format_error({missing_arg, handler}) ->
    "Missing required argument: --handler <path-to-handler-erl>";
format_error({missing_arg, output}) ->
    "Missing required argument: --output <output-file-path>";
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

-spec validate_args(term(), term()) -> ok | {error, term()}.
validate_args(undefined, _) ->
    {error, {missing_arg, handler}};
validate_args(_, undefined) ->
    {error, {missing_arg, output}};
validate_args(_, _) ->
    ok.

-spec extract_and_generate(rebar_state:t(), string(), string(), string() | undefined) ->
    {ok, rebar_state:t()} | {error, string()}.
extract_and_generate(State, HandlerPath, OutputPath, AppNameOpt) ->
    rebar_api:info("Extracting OpenAPI documentation...", []),
    rebar_api:info("  Handler: ~s", [HandlerPath]),
    rebar_api:info("  Output: ~s", [OutputPath]),
    case AppNameOpt of
        undefined -> ok;
        AppName -> rebar_api:info("  App: ~s", [AppName])
    end,

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
                        rebar3_opapi_parser:extract_trails(Forms)
                    catch
                        C:E ->
                            rebar_api:warn("Failed to extract trails: ~p:~p", [C, E]),
                            []
                    end,

                    Types = rebar3_opapi_parser:extract_types(Forms),

                    rebar_api:info("Found ~p trail(s), ~p type(s)",
                        [length(Trails), length(Types)]),

                    %% Expand trails metadata (type refs -> $refs)
                    ExpandedTrails = rebar3_opapi_expander:expand_trails(Trails, Types),

                    %% Build OpenAPI document from expanded trails
                    AppNameBin = case AppNameOpt of
                        undefined -> <<"API">>;
                        AppNameStr -> list_to_binary(AppNameStr)
                    end,
                    OpenAPIDoc = rebar3_opapi_builder:build_from_trails(ExpandedTrails, Types, AppNameBin),

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
        %% Use simple YAML writer (yamerl doesn't have encoder)
        YAML = rebar3_opapi_yaml_writer:write(Doc),
        file:write_file(FilePath, YAML)
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    end.

-spec write_json_file(string(), map()) -> ok | {error, term()}.
write_json_file(FilePath, Doc) ->
    try
        JSON = jsx:encode(Doc, [pretty]),
        file:write_file(FilePath, JSON)
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    end.
