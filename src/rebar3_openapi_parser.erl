%%%-------------------------------------------------------------------
%%% @author amarBitMan <https://github.com/amarBitMan>
%%% @copyright (C) 2025, Grey Orange
%%%-------------------------------------------------------------------
-module(rebar3_openapi_parser).

-moduledoc """
----------------------------------------------------------------------
Parser for OpenAPI Documentation Extraction

Parses Erlang source files to extract -type definitions.
Note: trails/0 is now called directly at runtime instead of parsing.
Used by the plugin for OpenAPI 3.0.x documentation generation.
----------------------------------------------------------------------
""".

-export([
    extract_types/1,
    extract_remote_type_refs/1
]).

-export_type([type_def/0]).

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

-doc """
Extract remote type references from a list of type definitions.
Walks the type ASTs and collects {Module, TypeName} pairs for remote_type nodes.
Excludes gm_type references (handled inline by the converter).
""".
-spec extract_remote_type_refs([type_def()]) -> [{Module :: atom(), TypeName :: atom()}].
extract_remote_type_refs(Types) ->
    Refs = lists:foldl(
        fun({_TypeName, TypeAST}, Acc) ->
            collect_remote_refs(TypeAST, Acc)
        end,
        [],
        Types
    ),
    lists:usort(Refs).

%%%===================================================================
%%% Internal Functions
%%%===================================================================

-doc false.
-spec collect_remote_refs(term(), [{atom(), atom()}]) -> [{atom(), atom()}].
collect_remote_refs({remote_type, _, [{atom, _, gm_type}, {atom, _, _TypeName}, _Args]}, Acc) ->
    %% Skip gm_type refs — handled inline by the converter
    Acc;
collect_remote_refs({remote_type, _, [{atom, _, Module}, {atom, _, TypeName}, Args]}, Acc) ->
    %% Found a remote type reference
    NewAcc = [{Module, TypeName} | Acc],
    %% Also walk any type arguments
    lists:foldl(fun(Arg, A) -> collect_remote_refs(Arg, A) end, NewAcc, Args);
collect_remote_refs({type, _, _Name, Args}, Acc) when is_list(Args) ->
    lists:foldl(fun(Arg, A) -> collect_remote_refs(Arg, A) end, Acc, Args);
collect_remote_refs({type, _, tuple, Args}, Acc) when is_list(Args) ->
    lists:foldl(fun(Arg, A) -> collect_remote_refs(Arg, A) end, Acc, Args);
collect_remote_refs({user_type, _, _TypeName, Args}, Acc) ->
    lists:foldl(fun(Arg, A) -> collect_remote_refs(Arg, A) end, Acc, Args);
collect_remote_refs(_Other, Acc) ->
    Acc.

%%%===================================================================
%%% Types
%%%===================================================================

-type type_def() :: {atom(), erl_parse:abstract_type()}.
