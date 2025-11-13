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
            %% Parse handler file to extract contracts, types, and routes
            case rebar3_opapi_parser:parse_file(HandlerPath, IncludePaths) of
                {ok, {Contracts, Types}} ->
                    %% Also extract routes from the parsed forms
                    case parse_forms(HandlerPath, IncludePaths) of
                        {ok, Forms} ->
                            Routes = rebar3_opapi_parser:extract_routes(Forms),
                            rebar_api:info("Found ~p contract(s), ~p type(s), ~p route(s)", 
                                [length(Contracts), length(Types), length(Routes)]),
                            
                            %% Convert contracts and routes to operations
                            Operations = convert_contracts_to_operations(Contracts, Routes, Types),
                            
                            %% Build OpenAPI document
                            AppNameBin = case AppNameOpt of
                                undefined -> <<"API">>;
                                AppNameStr -> list_to_binary(AppNameStr)
                            end,
                            OpenAPIDoc = rebar3_opapi_builder:build(Operations, AppNameBin),
                            
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
    %% Use epp to handle includes and macros
    Options = [{includes, IncludePaths}],
    case epp:parse_file(FilePath, Options) of
        {ok, Forms} ->
            {ok, Forms};
        {error, Error} ->
            {error, {parse_error, Error}};
        {error, Error, _} ->
            {error, {parse_error, Error}}
    end.

-spec convert_contracts_to_operations([rebar3_opapi_parser:contract()], [rebar3_opapi_parser:route()], [rebar3_opapi_parser:type_def()]) -> [map()].
convert_contracts_to_operations(Contracts, Routes, _Types) ->
    %% Match contracts with routes by operation_id
    ContractMap = maps:from_list(Contracts),
    lists:foldl(
        fun(Route, Acc) ->
            OpId = maps:get(operation_id, Route),
            case maps:get(OpId, ContractMap, undefined) of
                undefined ->
                    %% Route without contract - create basic operation
                    Operation = #{
                        operation_id => OpId,
                        method => maps:get(method, Route),
                        path => maps:get(path, Route),
                        summary => <<>>,
                        description => <<>>,
                        tags => [],
                        responses => #{<<"200">> => #{<<"description">> => <<"Success">>}}
                    },
                    [Operation | Acc];
                ContractData ->
                    %% Route with contract - build full operation
                    Operation = build_operation_from_contract(Route, ContractData),
                    [Operation | Acc]
            end
        end,
        [],
        Routes
    ).

-spec build_operation_from_contract(rebar3_opapi_parser:route(), map()) -> map().
build_operation_from_contract(Route, Contract) ->
    OpId = maps:get(operation_id, Route),
    Method = maps:get(method, Route),
    Path = maps:get(path, Route),
    
    %% Extract request body if present
    RequestBody = case maps:get(request_body, Contract, undefined) of
        undefined -> undefined;
        ReqBody -> #{<<"content">> => #{
            <<"application/json">> => #{
                <<"schema">> => ReqBody
            }
        }}
    end,
    
    %% Extract responses
    Responses = case maps:get(responses, Contract, undefined) of
        undefined -> #{<<"200">> => #{<<"description">> => <<"Success">>}};
        RespMap -> RespMap
    end,
    
    #{
        operation_id => OpId,
        method => Method,
        path => Path,
        summary => maps:get(summary, Contract, <<>>),
        description => maps:get(description, Contract, <<>>),
        tags => maps:get(tags, Contract, []),
        request_body => RequestBody,
        responses => Responses,
        parameters => maps:get(parameters, Contract, [])
    }.

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
