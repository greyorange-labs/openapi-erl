-module(rebar3_openapi_parser).

%%%===================================================================
%%% Parser for OpenAPI Documentation Extraction
%%%===================================================================
%%%
%%% Parses Erlang source files to extract -type definitions.
%%% Note: trails/0 is now called directly at runtime instead of parsing.
%%% Used by the plugin for OpenAPI 3.0.x documentation generation.
%%%
%%%===================================================================

-export([
    extract_types/1
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

%%%===================================================================
%%% Types
%%%===================================================================

-type type_def() :: {atom(), erl_parse:abstract_type()}.
