-module(rebar3_openapi_prv_generate_handler).
-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, generate_handler).
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
        {example, "rebar3 openapi generate_handler --app pick"},
        {short_desc, "Generate a template HTTP handler module with example routes"},
        {desc, "Generate a template HTTP handler module with GET/POST/PUT route examples"},
        {opts, [
            {app, undefined, "app", string, "Application name (required)"}
        ]}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    try
        {Args, _} = rebar_state:command_parsed_args(State),
        AppName = proplists:get_value(app, Args),

        case validate_app_name(AppName) of
            ok ->
                generate_handler(State, AppName);
            {error, Reason} ->
                {error, format_error(Reason)}
        end
    catch
        Class:Err:Stack ->
            rebar_api:error("openapi generate_handler failed: ~p:~p", [Class, Err]),
            rebar_api:error("Stack trace: ~p", [Stack]),
            {error, format_error({internal_error, Class, Err})}
    end.

-spec format_error(any()) -> iolist().
format_error({missing_arg, app}) ->
    "Missing required argument: --app <application-name>";
format_error({invalid_app_name, AppName}) ->
    io_lib:format("Invalid application name: ~s (must be a valid Erlang atom)", [AppName]);
format_error({file_exists, Path}) ->
    io_lib:format("File already exists: ~s (use --force to overwrite)", [Path]);
format_error({file_write_error, Path, Reason}) ->
    io_lib:format("Failed to write file ~s: ~p", [Path, Reason]);
format_error({directory_error, Path, Reason}) ->
    io_lib:format("Failed to create directory ~s: ~p", [Path, Reason]);
format_error({internal_error, Class, Err}) ->
    io_lib:format("Internal error: ~p:~p", [Class, Err]);
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%%%===================================================================
%%% Internal Functions
%%%===================================================================

-spec validate_app_name(term()) -> ok | {error, term()}.
validate_app_name(undefined) ->
    {error, {missing_arg, app}};
validate_app_name(AppName) when is_list(AppName) ->
    %% Validate it's a valid Erlang atom (alphanumeric, underscore, @)
    case re:run(AppName, "^[a-z][a-z0-9_@]*$", [{capture, none}]) of
        match ->
            ok;
        nomatch ->
            {error, {invalid_app_name, AppName}}
    end;
validate_app_name(AppName) ->
    {error, {invalid_app_name, io_lib:format("~p", [AppName])}}.

-spec generate_handler(rebar_state:t(), string()) -> {ok, rebar_state:t()} | {error, string()}.
generate_handler(State, AppName) ->
    rebar_api:info("Generating handler template for app: ~s", [AppName]),

    %% Get workspace root
    WorkspaceRoot = rebar_dir:root_dir(State),

    %% Determine target file path
    HandlerModuleName = AppName ++ "_http_handler",
    TargetPath = filename:join([
        WorkspaceRoot,
        "apps",
        AppName,
        "src",
        "interfaces",
        "in",
        HandlerModuleName ++ ".erl"
    ]),

    %% Check if file already exists
    case filelib:is_file(TargetPath) of
        true ->
            {error, {file_exists, TargetPath}};
        false ->
            %% Ensure directory exists
            TargetDir = filename:dirname(TargetPath),
            case ensure_directory(TargetDir) of
                ok ->
                    %% Generate handler template
                    Template = generate_handler_template(HandlerModuleName),
                    %% Write file
                    case file:write_file(TargetPath, Template) of
                        ok ->
                            rebar_api:info("SUCCESS: Handler template generated at ~s", [TargetPath]),
                            {ok, State};
                        {error, Reason} ->
                            {error, {file_write_error, TargetPath, Reason}}
                    end;
                {error, Reason} ->
                    {error, {directory_error, TargetDir, Reason}}
            end
    end.

-spec ensure_directory(string()) -> ok | {error, term()}.
ensure_directory(Dir) ->
    case filelib:is_dir(Dir) of
        true ->
            ok;
        false ->
            case filelib:ensure_dir(filename:join([Dir, "dummy"])) of
                ok ->
                    ok;
                {error, Reason} ->
                    {error, Reason}
            end
    end.

-spec generate_handler_template(string()) -> iolist().
generate_handler_template(HandlerModuleName) ->
    [
        "-module(", HandlerModuleName, ").\n",
        "-compile(nowarn_unused_type).\n",
        "-compile({parse_transform, gm_schema_extract_pt}).\n",
        "-include(\"src/gm_common.hrl\").\n",
        "\n",
        "%% API exports\n",
        "-export([\n",
        "    start_handlers/0,\n",
        "    trails/0,\n",
        "    handle_request/3\n",
        "]).\n",
        "\n",
        "%%%===================================================================\n",
        "%%% Type Definitions (OpenAPI Schemas)\n",
        "%%%===================================================================\n",
        "%% TODO: Define schema types for the API\n",
        "%% \n",
        "%% Example type definitions:\n",
        "%% -type item_id() :: binary().\n",
        "%% -type item() :: #{\n",
        "%%     id := item_id(),\n",
        "%%     name := binary(),\n",
        "%%     status => binary()\n",
        "%% }.\n",
        "%% -type item_status() :: active | inactive.\n",
        "\n",
        "start_handlers() ->\n",
        "    cowboy_routes_manager:start_handlers([?MODULE]).\n",
        "\n",
        "%%%===================================================================\n",
        "%%% Routes and Trails\n",
        "%%%===================================================================\n",
        "%% \n",
        "%% Define your API routes here using the trails library format.\n",
        "%% Each trail can support multiple HTTP methods (get, put, post, delete).\n",
        "%% \n",
        "%% Route examples:\n",
        "%% - GET: Retrieve a resource\n",
        "%% - POST: Create a new resource\n",
        "%% - PUT: Update an existing resource (full replacement)\n",
        "%% - DELETE: Delete a resource\n",
        "%% \n",
        "%% Type references in metadata (e.g., schema => item_id) will be\n",
        "%% automatically expanded to OpenAPI $ref paths during documentation generation.\n",
        "%%\n",
        "\n",
        "-spec trails() -> trails:trails().\n",
        "trails() ->\n",
        "    [\n",
        "        %% Example GET route - Retrieve resource by ID\n",
        "        trails:trail(\"/api/items/:id\", gm_http_handler, [], #{\n",
        "            get => #{\n",
        "                tags => [<<\"items\">>],\n",
        "                description => <<\"Get item by ID\">>,\n",
        "                summary => <<\"Retrieve a single item\">>,\n",
        "                parameters => [\n",
        "                    #{\n",
        "                        name => <<\"id\">>,\n",
        "                        in => <<\"path\">>,\n",
        "                        required => true,\n",
        "                        description => <<\"Unique identifier for the item\">>,\n",
        "                        schema => binary  % TODO: Replace with your type (e.g., item_id)\n",
        "                    }\n",
        "                ],\n",
        "                responses => #{\n",
        "                    <<\"200\">> => #{\n",
        "                        description => <<\"Successfully retrieved item\">>,\n",
        "                        content => #{\n",
        "                            <<\"application/json\">> => #{\n",
        "                                schema => binary  % TODO: Replace with your type (e.g., item)\n",
        "                            }\n",
        "                        }\n",
        "                    },\n",
        "                    <<\"404\">> => #{\n",
        "                        description => <<\"Item not found\">>\n",
        "                    },\n",
        "                    <<\"500\">> => #{\n",
        "                        description => <<\"Internal server error\">>\n",
        "                    }\n",
        "                }\n",
        "            }\n",
        "        }),\n",
        "\n",
        "        %% Example POST route - Create new resource\n",
        "        trails:trail(\"/api/items\", gm_http_handler, [], #{\n",
        "            post => #{\n",
        "                tags => [<<\"items\">>],\n",
        "                description => <<\"Create a new item\">>,\n",
        "                summary => <<\"Create item\">>,\n",
        "                requestBody => #{\n",
        "                    required => true,\n",
        "                    description => <<\"Item data to create\">>,\n",
        "                    content => #{\n",
        "                        <<\"application/json\">> => #{\n",
        "                            schema => binary  % TODO: Replace with your request type\n",
        "                        }\n",
        "                    }\n",
        "                },\n",
        "                responses => #{\n",
        "                    <<\"201\">> => #{\n",
        "                        description => <<\"Item created successfully\">>,\n",
        "                        content => #{\n",
        "                            <<\"application/json\">> => #{\n",
        "                                schema => binary  % TODO: Replace with your response type\n",
        "                            }\n",
        "                        }\n",
        "                    },\n",
        "                    <<\"400\">> => #{\n",
        "                        description => <<\"Invalid request data\">>\n",
        "                    },\n",
        "                    <<\"500\">> => #{\n",
        "                        description => <<\"Internal server error\">>\n",
        "                    }\n",
        "                }\n",
        "            }\n",
        "        }),\n",
        "\n",
        "        %% Example PUT route - Update existing resource\n",
        "        trails:trail(\"/api/items/:id\", gm_http_handler, [], #{\n",
        "            put => #{\n",
        "                tags => [<<\"items\">>],\n",
        "                description => <<\"Update an existing item\">>,\n",
        "                summary => <<\"Update item\">>,\n",
        "                parameters => [\n",
        "                    #{\n",
        "                        name => <<\"id\">>,\n",
        "                        in => <<\"path\">>,\n",
        "                        required => true,\n",
        "                        description => <<\"Unique identifier for the item\">>,\n",
        "                        schema => binary  % TODO: Replace with your type (e.g., item_id)\n",
        "                    }\n",
        "                ],\n",
        "                requestBody => #{\n",
        "                    required => true,\n",
        "                    description => <<\"Updated item data\">>,\n",
        "                    content => #{\n",
        "                        <<\"application/json\">> => #{\n",
        "                            schema => binary  % TODO: Replace with your request type\n",
        "                        }\n",
        "                    }\n",
        "                },\n",
        "                responses => #{\n",
        "                    <<\"200\">> => #{\n",
        "                        description => <<\"Item updated successfully\">>,\n",
        "                        content => #{\n",
        "                            <<\"application/json\">> => #{\n",
        "                                schema => binary  % TODO: Replace with your response type\n",
        "                            }\n",
        "                        }\n",
        "                    },\n",
        "                    <<\"400\">> => #{\n",
        "                        description => <<\"Invalid request data\">>\n",
        "                    },\n",
        "                    <<\"404\">> => #{\n",
        "                        description => <<\"Item not found\">>\n",
        "                    },\n",
        "                    <<\"500\">> => #{\n",
        "                        description => <<\"Internal server error\">>\n",
        "                    }\n",
        "                }\n",
        "            }\n",
        "        })\n",
        "    ].\n",
        "\n",
        "%%%===================================================================\n",
        "%%% Request Handling\n",
        "%%%===================================================================\n",
        "\n",
        "-doc \"\"\"\n",
        "\n",
        "Function clauses for each operation, call relevant logic/resource controller to handle the request\n",
        "\n",
        "\"\"\".\n",
        "\n",
        "-spec handle_request(\n",
        "    OperationId :: gm_http_handler:operation_id(), \n",
        "    Req :: cowboy_req:req(), \n",
        "    Context :: gm_http_handler:context())\n",
        " ->\n",
        "    gm_http_handler:response().\n",
        "handle_request(OperationId, _Req, Context) ->\n",
        "    ?INFO(\"Received request for operation ~p which is not implemented yet\", [OperationId]),\n",
        "    RespBody = #{message => <<\"Not implemented\">>},\n",
        "    RespHeaders = #{<<\"content-type\">> => <<\"application/json\">>},\n",
        "    {501, RespBody, Context, RespHeaders}.\n"
    ].

