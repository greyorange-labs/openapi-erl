-module(rebar3_opapi_yaml_writer).

-export([write/1]).

%% Simple YAML writer for OpenAPI documents
%% yamerl doesn't have a good encoder, so we use a custom writer

-spec write(map()) -> iolist().
write(Map) ->
    map_to_yaml(Map, 0).

-spec map_to_yaml(map(), integer()) -> iolist().
map_to_yaml(Map, Indent) when is_map(Map) ->
    IndentStr = lists:duplicate(Indent, $ ),
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
                    ValueStr = value_to_string(V),
                    io_lib:format("~s~s: ~s", [IndentStr, KeyStr, ValueStr])
            end
        end,
        lists:sort(maps:to_list(Map))
    ),
    string:join(Lines, "\n").

-spec list_to_yaml(list(), integer()) -> iolist().
list_to_yaml([], _Indent) ->
    "[]";
list_to_yaml(List, Indent) ->
    IndentStr = lists:duplicate(Indent, $ ),
    Lines = lists:map(
        fun(Item) when is_map(Item) ->
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

-spec value_to_string(term()) -> string().
value_to_string(Bin) when is_binary(Bin) ->
    binary_to_list(Bin);
value_to_string(true) ->
    "true";
value_to_string(false) ->
    "false";
value_to_string(null) ->
    "null";
value_to_string(Num) when is_number(Num) ->
    integer_to_list(Num);
value_to_string(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
value_to_string(Other) ->
    io_lib:format("~p", [Other]).

-spec key_to_string(term()) -> string().
key_to_string(Bin) when is_binary(Bin) ->
    binary_to_list(Bin);
key_to_string(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
key_to_string(Other) ->
    io_lib:format("~p", [Other]).

