-module(handler_with_type_meta).
-compile(nowarn_unused_type).

-export([
    routes/0,
    trails/0
]).

%%%===================================================================
%%% Type Definitions with -type_meta annotations
%%%===================================================================

%% Simple type with description
-type_meta({user_id, #{
    description => <<"Unique user identifier">>,
    example => <<"usr_abc123">>
}}).
-type user_id() :: binary().

%% Object type with description
-type_meta({user, #{
    description => <<"A user in the system">>
}}).
-type user() :: #{
    id := user_id(),
    name := binary(),
    email := binary()
}.

%% Enum type with deprecated flag
-type_meta({user_role, #{
    description => <<"Role assigned to a user">>,
    deprecated => true
}}).
-type user_role() :: admin | editor | viewer.

%% Type WITHOUT -type_meta (should not get metadata)
-type error_response() :: #{
    code := integer(),
    message := binary()
}.

%%%===================================================================
%%% Routes Definition
%%%===================================================================

routes() ->
    [
        #{
            path => "/api/users",
            allowed_methods => #{
                get => #{
                    tags => [<<"Users">>],
                    summary => <<"List all users">>,
                    responses => #{
                        <<"200">> => #{
                            description => <<"Successfully retrieved users">>,
                            content => #{
                                <<"application/json">> => #{
                                    schema => {array, user}
                                }
                            }
                        }
                    }
                },
                post => #{
                    tags => [<<"Users">>],
                    summary => <<"Create a new user">>,
                    requestBody => #{
                        required => true,
                        content => #{
                            <<"application/json">> => #{
                                schema => user
                            }
                        }
                    },
                    responses => #{
                        <<"201">> => #{
                            description => <<"User created">>,
                            content => #{
                                <<"application/json">> => #{
                                    schema => user
                                }
                            }
                        },
                        <<"400">> => #{
                            description => <<"Invalid input">>,
                            content => #{
                                <<"application/json">> => #{
                                    schema => error_response
                                }
                            }
                        }
                    }
                }
            }
        }
    ].

-spec trails() -> trails:trails().
trails() ->
    lists:map(
        fun(#{path := Path, allowed_methods := AllowedMethods}) ->
            State = #{
                handler_mod => handler_with_type_meta,
                allowed_methods => AllowedMethods
            },
            trails:trail(Path, handler_with_type_meta, State, AllowedMethods)
        end,
        routes()
    ).
