-module(rebar3_opapi_prv_extract).

-export([do/1, format_error/1]).

%%%===================================================================
%%% Provider Implementation
%%%===================================================================

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    try
        {Args, _} = rebar_state:command_parsed_args(State),

        Handler = proplists:get_value(handler, Args),
        App = proplists:get_value(app, Args),
        Output = proplists:get_value(output, Args),

        case validate_args(Handler, App, Output) of
            ok ->
                extract_and_generate(State, Handler, App, Output);
            {error, Reason} ->
                {error, format_error(Reason)}
        end
    catch
        Class:Err:Stack ->
            rebar_api:error("opapi extract failed: ~p:~p~n~p", [Class, Err, Stack]),
            {error, "Internal error during extraction"}
    end.

-spec validate_args(term(), term(), term()) -> ok | {error, term()}.
validate_args(undefined, _, _) ->
    {error, {missing_arg, handler}};
validate_args(_, undefined, _) ->
    {error, {missing_arg, app}};
validate_args(_, _, undefined) ->
    {error, {missing_arg, output}};
validate_args(_, _, _) ->
    ok.

-spec extract_and_generate(rebar_state:t(), string(), string(), string()) ->
    {ok, rebar_state:t()} | {error, string()}.
extract_and_generate(State, HandlerStr, AppStr, OutputPath) ->
    HandlerModule = list_to_atom(HandlerStr),
    AppName = list_to_atom(AppStr),

    rebar_api:info("Extracting OpenAPI documentation...", []),
    rebar_api:info("  Handler: ~s", [HandlerStr]),
    rebar_api:info("  App: ~s", [AppStr]),
    rebar_api:info("  Output: ~s", [OutputPath]),

    %% Extract operations from handler
    case gm_opapi_extractor:extract_handler(HandlerModule) of
        {ok, Operations} ->
            %% Build OpenAPI document
            OpenAPIDoc = rebar3_opapi_builder:build(Operations, AppName),

            %% Write to file
            case write_openapi_file(OutputPath, OpenAPIDoc) of
                ok ->
                    rebar_api:info("SUCCESS: OpenAPI documentation written to ~s", [OutputPath]),
                    {ok, State};
                {error, Reason} ->
                    {error, {file_write_error, OutputPath, Reason}}
            end;
        {error, Reason} ->
            {error, {extraction_error, Reason}}
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

-spec format_error(term()) -> iolist().
format_error({missing_arg, handler}) ->
    "Missing required argument: --handler <handler-module-name>";
format_error({missing_arg, app}) ->
    "Missing required argument: --app <app-name>";
format_error({missing_arg, output}) ->
    "Missing required argument: --output <output-file-path>";
format_error({file_write_error, Path, Reason}) ->
    io_lib:format("Failed to write file ~s: ~p", [Path, Reason]);
format_error({extraction_error, Reason}) ->
    io_lib:format("Failed to extract contracts: ~p", [Reason]);
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

