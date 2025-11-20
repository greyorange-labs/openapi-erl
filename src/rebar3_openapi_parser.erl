-module(rebar3_openapi_parser).

%%%===================================================================
%%% Parser for OpenAPI Documentation Extraction
%%%===================================================================
%%%
%%% Parses Erlang source files to extract trails/0 callbacks and -type
%%% definitions. Used by the plugin for OpenAPI 3.0.x documentation generation.
%%%
%%%===================================================================

-export([
    extract_types/1,
    extract_trails/1
]).

-export_type([type_def/0, trail/0]).

%%%===================================================================
%%% Public API
%%%===================================================================

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

%% Helper function for finding functions (used by extract_trails)
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

-spec extract_value(erl_parse:abstract_expr()) -> term().
extract_value({string, _Line, String}) ->
    list_to_binary(String);
extract_value({bin, _Line, Elements}) ->
    %% Binary literal like <<"hello">>
    extract_binary(Elements);
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
extract_value({tuple, _Line, Elements}) ->
    %% Tuple literal like {array, user}
    list_to_tuple([extract_value(Elem) || Elem <- Elements]);
extract_value({map, _Line1, Fields}) ->
    maps:from_list(
        lists:map(
            fun
                ({map_field_assoc, _Line2, KeyExpr, ValueExpr}) ->
                    {extract_value(KeyExpr), extract_value(ValueExpr)};
                ({map_field_exact, _Line2, KeyExpr, ValueExpr}) ->
                    {extract_value(KeyExpr), extract_value(ValueExpr)}
            end,
            Fields
        )
    );
extract_value(_) ->
    undefined.

-spec extract_binary([erl_parse:abstract_expr()]) -> binary().
extract_binary(Elements) ->
    list_to_binary(
        lists:map(
            fun
                ({bin_element, _Line, {string, _Line2, String}, default, default}) ->
                    String;
                ({bin_element, _Line, {integer, _Line2, Int}, default, default}) ->
                    Int
            end,
            Elements
        )
    ).

%%%===================================================================
%%% New API for trails extraction
%%%===================================================================

-spec extract_trails([erl_parse:abstract_form()]) -> [trail()].
extract_trails(Forms) ->
    %% Find trails/0 function
    case find_function(Forms, trails, 0) of
        {ok, Function} ->
            extract_trails_from_function(Function);
        error ->
            []
    end.

-spec extract_trails_from_function(erl_parse:abstract_form()) -> [trail()].
extract_trails_from_function({function, _Line1, trails, 0, [Clause]}) ->
    {clause, _Line2, [], [], [Body]} = Clause,
    extract_trails_from_body(Body);
extract_trails_from_function(_) ->
    [].

-spec extract_trails_from_body(erl_parse:abstract_expr()) -> [trail()].
extract_trails_from_body({cons, _Line, TrailExpr, Tail}) ->
    Trail = extract_single_trail(TrailExpr),
    Rest = extract_trails_from_body(Tail),
    case Trail of
        undefined -> Rest;
        _ -> [Trail | Rest]
    end;
extract_trails_from_body({nil, _Line}) ->
    [];
extract_trails_from_body(_) ->
    [].

-spec extract_single_trail(erl_parse:abstract_expr()) -> trail() | undefined.
extract_single_trail({call, _Line1, {remote, _Line2, {atom, _Line3, trails}, {atom, _Line4, trail}}, Args}) ->
    %% trails:trail(Path, Handler, Options, Metadata)
    case Args of
        [PathExpr, HandlerExpr, OptionsExpr, MetadataExpr] ->
            Path = extract_value(PathExpr),
            Handler = extract_value(HandlerExpr),
            Options = extract_value(OptionsExpr),
            Metadata = extract_value(MetadataExpr),
            case {Path, Handler} of
                {undefined, _} ->
                    undefined;
                {_, undefined} ->
                    undefined;
                {PathBin, HandlerAtom} ->
                    #{
                        path => PathBin,
                        handler => HandlerAtom,
                        options => Options,
                        metadata => Metadata
                    }
            end;
        _ ->
            undefined
    end;
extract_single_trail(_) ->
    undefined.

%%%===================================================================
%%% Types
%%%===================================================================

-type type_def() :: {atom(), erl_parse:abstract_type()}.
-type trail() :: #{
    path => binary(),
    handler => atom(),
    options => map() | list(),
    metadata => map()
}.
