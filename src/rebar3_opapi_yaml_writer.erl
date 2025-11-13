-module(rebar3_opapi_yaml_writer).

-export([write/1, needs_quoting/2]).

%% Simple YAML writer for OpenAPI documents
%% yamerl doesn't have a good encoder, so we use a custom writer

-spec write(map()) -> iolist().
write(Map) ->
    %% OpenAPI 3.0.3 spec requires specific field order
    %% Order: openapi, info, servers, paths, components, security, tags, externalDocs
    OrderedKeys = [
        <<"openapi">>,
        <<"info">>,
        <<"servers">>,
        <<"paths">>,
        <<"components">>,
        <<"security">>,
        <<"tags">>,
        <<"externalDocs">>
    ],
    map_to_yaml_ordered(Map, OrderedKeys, 0).

-spec map_to_yaml_ordered(map(), [binary()], integer()) -> iolist().
map_to_yaml_ordered(Map, OrderedKeys, Indent) ->
    IndentStr = lists:duplicate(Indent, $\s),
    %% Get keys in order, then any remaining keys
    OrderedPairs = lists:filter(
        fun({K, _}) -> lists:member(K, OrderedKeys) end,
        maps:to_list(Map)
    ),
    %% Sort ordered pairs by their position in OrderedKeys
    SortedOrdered = lists:sort(
        fun({K1, _}, {K2, _}) ->
            Pos1 = index_of(K1, OrderedKeys, 0),
            Pos2 = index_of(K2, OrderedKeys, 0),
            Pos1 =< Pos2
        end,
        OrderedPairs
    ),
    %% Get remaining keys (not in OrderedKeys)
    OrderedKeysSet = sets:from_list(OrderedKeys),
    RemainingPairs = lists:filter(
        fun({K, _}) -> not sets:is_element(K, OrderedKeysSet) end,
        maps:to_list(Map)
    ),
    SortedRemaining = lists:sort(RemainingPairs),
    AllPairs = SortedOrdered ++ SortedRemaining,

    Lines = lists:map(
        fun({K, V}) ->
            KeyStr = key_to_string(K),
            case V of
                SubMap when is_map(SubMap) ->
                    SubYaml = map_to_yaml(SubMap, Indent + 2),
                    io_lib:format("~s~s:~n~s", [IndentStr, KeyStr, SubYaml]);
                SubList when is_list(SubList) ->
                    SubYaml = list_to_yaml(SubList, Indent + 2),
                    io_lib:format("~s~s:~n~s", [IndentStr, KeyStr, SubYaml]);
                _ ->
                    ValueStr = value_to_string(K, V),
                    %% Flatten iolist to string
                    ValueStrFlat = lists:flatten(io_lib:format("~s", [ValueStr])),
                    io_lib:format("~s~s: ~s", [IndentStr, KeyStr, ValueStrFlat])
            end
        end,
        AllPairs
    ),
    LinesFlat = lists:map(fun(Line) -> lists:flatten(io_lib:format("~s", [Line])) end, Lines),
    string:join(LinesFlat, "\n").

-spec index_of(term(), [term()], integer()) -> integer().
% Put unknown keys at end
index_of(_Item, [], _Default) -> 999999;
index_of(Item, [Item | _], Pos) -> Pos;
index_of(Item, [_ | Rest], Pos) -> index_of(Item, Rest, Pos + 1).

-spec map_to_yaml(map(), integer()) -> iolist().
map_to_yaml(Map, Indent) when is_map(Map) ->
    IndentStr = lists:duplicate(Indent, $\s),
    Lines = lists:map(
        fun({K, V}) ->
            KeyStr = key_to_string(K),
            case V of
                SubMap when is_map(SubMap) ->
                    SubYaml = map_to_yaml(SubMap, Indent + 2),
                    io_lib:format("~s~s:~n~s", [IndentStr, KeyStr, SubYaml]);
                SubList when is_list(SubList) ->
                    SubYaml = list_to_yaml(SubList, Indent + 2),
                    io_lib:format("~s~s:~n~s", [IndentStr, KeyStr, SubYaml]);
                _ ->
                    ValueStr = value_to_string(K, V),
                    %% Flatten iolist to string
                    ValueStrFlat = lists:flatten(io_lib:format("~s", [ValueStr])),
                    io_lib:format("~s~s: ~s", [IndentStr, KeyStr, ValueStrFlat])
            end
        end,
        % No sorting for nested maps - preserve order
        maps:to_list(Map)
    ),
    LinesFlat = lists:map(fun(Line) -> lists:flatten(io_lib:format("~s", [Line])) end, Lines),
    string:join(LinesFlat, "\n").

-spec list_to_yaml(list(), integer()) -> iolist().
list_to_yaml([], _Indent) ->
    "[]";
list_to_yaml(List, Indent) ->
    IndentStr = lists:duplicate(Indent, $\s),
    Lines = lists:map(
        fun
            (Item) when is_map(Item) ->
                ItemYaml = map_to_yaml(Item, Indent + 2),
                io_lib:format("~s-~n~s", [IndentStr, ItemYaml]);
            (Item) when is_list(Item) ->
                ItemYaml = list_to_yaml(Item, Indent + 2),
                io_lib:format("~s-~n~s", [IndentStr, ItemYaml]);
            (Item) ->
                ItemStr = value_to_string(Item),
                io_lib:format("~s- ~s", [IndentStr, ItemStr])
        end,
        List
    ),
    string:join(Lines, "\n").

-spec value_to_string(term(), term()) -> string().
value_to_string(Key, Bin) when is_binary(Bin) ->
    %% Check if this is a $ref value or other special strings that need quoting
    BinStr = binary_to_list(Bin),
    NeedsQuote = needs_quoting(Key, BinStr),
    case NeedsQuote of
        true ->
            %% Quote the value - escape any single quotes in the string
            Escaped = escape_quotes(BinStr),
            %% Ensure we return a flattened string, not iolist
            lists:flatten(io_lib:format("'~s'", [Escaped]));
        false ->
            BinStr
    end;
value_to_string(_Key, true) ->
    "true";
value_to_string(_Key, false) ->
    "false";
value_to_string(_Key, null) ->
    "null";
value_to_string(_Key, Num) when is_number(Num) ->
    integer_to_list(Num);
value_to_string(_Key, Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
value_to_string(_Key, Other) ->
    io_lib:format("~p", [Other]).

%% Legacy function for backward compatibility
-spec value_to_string(term()) -> string().
value_to_string(Value) ->
    value_to_string(undefined, Value).

%% Check if a string value needs YAML quoting
-spec needs_quoting(term(), string()) -> boolean().
needs_quoting(Key, Str) ->
    %% Always quote $ref values - they must be strings in OpenAPI
    case Key of
        % $ref values must be quoted strings
        <<"$ref">> ->
            true;
        _ ->
            %% Always quote values starting with # (like $ref paths)
            %% Use integer 35 (ASCII code for #) instead of $# for pattern matching
            case Str of
                % Values starting with # MUST be quoted
                [35 | _] ->
                    true;
                _ ->
                    %% Quote if contains characters that need quoting in YAML
                    lists:any(
                        fun(Char) ->
                            lists:member(Char, [$,, $:, $[, $], ${, $}, $&, $*, $!, $|, $>, $<, $@, $`, $"])
                        end,
                        Str
                    )
            end
    end.

%% Escape single quotes in a string
-spec escape_quotes(string()) -> string().
escape_quotes(Str) ->
    lists:foldr(
        % Double single quote to escape
        fun
            ($', Acc) -> [$', $' | Acc];
            (Char, Acc) -> [Char | Acc]
        end,
        [],
        Str
    ).

-spec key_to_string(term()) -> string().
key_to_string(Bin) when is_binary(Bin) ->
    binary_to_list(Bin);
key_to_string(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
key_to_string(Other) ->
    io_lib:format("~p", [Other]).
