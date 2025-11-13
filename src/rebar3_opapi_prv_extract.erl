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
            rebar_api:error("opapi extract failed: ~p:~p~n~p", [Class, Err, Stack]),
            {error, "Internal error during extraction"}
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
            %% For Phase 1: Stub implementation - just create empty OpenAPI doc
            AppNameBin = case AppNameOpt of
                undefined -> <<"API">>;
                AppNameStr -> list_to_binary(AppNameStr)
            end,
            OpenAPIDoc = rebar3_opapi_builder:build([], AppNameBin),
            
            %% Write to file
            case write_openapi_file(OutputPath, OpenAPIDoc) of
                ok ->
                    rebar_api:info("SUCCESS: OpenAPI documentation written to ~s", [OutputPath]),
                    {ok, State};
                {error, Reason} ->
                    {error, {file_write_error, OutputPath, Reason}}
            end
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
