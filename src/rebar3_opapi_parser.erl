-module(rebar3_opapi_parser).

%%%===================================================================
%%% Parser for OpenAPI Contract Extraction
%%%===================================================================
%%%
%%% Parses Erlang source files to extract -opapi_contract attributes
%%% and -type definitions. Used by the plugin for documentation generation.
%%%
%%%===================================================================

-export([
    parse_file/1,
    extract_contracts/1,
    extract_types/1,
    extract_routes/1
]).

-export_type([contract/0, type_def/0, route/0]).

%%%===================================================================
%%% Public API
%%%===================================================================

-spec parse_file(string()) -> {ok, {[contract()], [type_def()]}} | {error, term()}.
-spec parse_file(string(), [string()]) -> {ok, {[contract()], [type_def()]}} | {error, term()}.
parse_file(FilePath) ->
    parse_file(FilePath, []).
parse_file(FilePath, IncludePaths) ->
    %% Use epp to handle includes and macros
    Options = [{includes, IncludePaths}],
    case epp:parse_file(FilePath, Options) of
        {ok, Forms} ->
            Contracts = extract_contracts(Forms),
            Types = extract_types(Forms),
            {ok, {Contracts, Types}};
        {error, Error} ->
            {error, {parse_error, Error}};
        {error, Error, _} ->
            {error, {parse_error, Error}}
    end.

-spec extract_contracts([erl_parse:abstract_form()]) -> [contract()].
extract_contracts(Forms) ->
    lists:foldl(
        fun(Form, Acc) ->
            case Form of
                {attribute, _Line, opapi_contract, {OperationId, ContractMap}} ->
                    [{OperationId, ContractMap} | Acc];
                {attribute, _Line, opapi_contract, _} ->
                    %% Invalid format, skip
                    Acc;
                _ ->
                    Acc
            end
        end,
        [],
        Forms
    ).

-spec extract_types([erl_parse:abstract_form()]) -> [type_def()].
extract_types(Forms) ->
    lists:foldl(
        fun(Form, Acc) ->
            case Form of
                {attribute, _Line, type, {TypeName, TypeDef, []}} ->
                    [{TypeName, TypeDef} | Acc];
                {attribute, _Line, type, {TypeName, TypeDef, _Constraints}} ->
                    [{TypeName, TypeDef} | Acc];
                _ ->
                    Acc
            end
        end,
        [],
        Forms
    ).

-spec extract_routes([erl_parse:abstract_form()]) -> [route()].
extract_routes(Forms) ->
    %% Find routes/0 function
    case find_function(Forms, routes, 0) of
        {ok, Function} ->
            extract_routes_from_function(Function);
        error ->
            []
    end.

-spec find_function([erl_parse:abstract_form()], atom(), non_neg_integer()) ->
    {ok, erl_parse:abstract_form()} | error.
find_function(Forms, FuncName, Arity) ->
    lists:foldl(
        fun(Form, Acc) ->
            case Form of
                {function, _Line, Name, Arity, _Clauses} when Name =:= FuncName ->
                    {ok, Form};
                _ ->
                    Acc
            end
        end,
        error,
        Forms
    ).

-spec extract_routes_from_function(erl_parse:abstract_form()) -> [route()].
extract_routes_from_function({function, _Line1, routes, 0, [Clause]}) ->
    {clause, _Line2, [], [], [Body]} = Clause,
    extract_routes_from_body(Body);
extract_routes_from_function(_) ->
    [].

-spec extract_routes_from_body(erl_parse:abstract_expr()) -> [route()].
extract_routes_from_body({cons, _Line, MapExpr, Tail}) ->
    Route = extract_route_from_map(MapExpr),
    Rest = extract_routes_from_body(Tail),
    case Route of
        undefined -> Rest;
        _ -> [Route | Rest]
    end;
extract_routes_from_body({nil, _Line}) ->
    [];
extract_routes_from_body(_) ->
    [].

-spec extract_route_from_map(erl_parse:abstract_expr()) -> route() | undefined.
extract_route_from_map({map, _Line, Fields}) ->
    Path = extract_map_field(Fields, path),
    Methods = extract_map_field(Fields, allowed_methods),
    case {Path, Methods} of
        {undefined, _} -> undefined;
        {_, undefined} -> undefined;
        {PathBin, MethodsMap} ->
            extract_routes_from_methods(PathBin, MethodsMap)
    end;
extract_route_from_map(_) ->
    undefined.

-spec extract_routes_from_methods(binary(), map()) -> route() | undefined.
extract_routes_from_methods(Path, MethodsMap) when is_map(MethodsMap) ->
    %% Extract first method and operation_id from map
    case maps:to_list(MethodsMap) of
        [{Method, #{operation_id := OpId}} | _] ->
            #{path => Path, method => Method, operation_id => OpId};
        _ ->
            undefined
    end;
extract_routes_from_methods(_Path, _) ->
    undefined.

-spec extract_map_field([erl_parse:abstract_expr()], atom()) -> term() | undefined.
extract_map_field(Fields, Key) ->
    lists:foldl(
        fun(Field, Acc) ->
            case Field of
                {map_field_assoc, _Line1, {atom, _Line2, Key}, Value} ->
                    extract_value(Value);
                {map_field_exact, _Line1, {atom, _Line2, Key}, Value} ->
                    extract_value(Value);
                _ ->
                    Acc
            end
        end,
        undefined,
        Fields
    ).

-spec extract_value(erl_parse:abstract_expr()) -> term().
extract_value({string, _Line, String}) ->
    list_to_binary(String);
extract_value({atom, _Line, Atom}) ->
    Atom;
extract_value({integer, _Line, Int}) ->
    Int;
extract_value({float, _Line, Float}) ->
    Float;
extract_value({nil, _Line}) ->
    [];
extract_value({cons, _Line, Head, Tail}) ->
    [extract_value(Head) | extract_value(Tail)];
extract_value({map, _Line1, Fields}) ->
    maps:from_list(
        lists:map(
            fun({map_field_assoc, _Line2, KeyExpr, ValueExpr}) ->
                {extract_value(KeyExpr), extract_value(ValueExpr)};
            ({map_field_exact, _Line2, KeyExpr, ValueExpr}) ->
                {extract_value(KeyExpr), extract_value(ValueExpr)}
            end,
            Fields
        )
    );
extract_value(_) ->
    undefined.

%%%===================================================================
%%% Types
%%%===================================================================

-type contract() :: {atom(), map()}.
-type type_def() :: {atom(), erl_parse:abstract_type()}.
-type route() :: #{path => binary(), method => binary(), operation_id => atom()}.

