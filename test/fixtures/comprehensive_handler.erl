-module(comprehensive_handler).
-compile(nowarn_unused_type).

-export([routes/0, trails/0]).

%%%===================================================================
%%% Type Definitions (Common Schemas)
%%%===================================================================

-type user_id() :: binary().
-type email() :: binary().

-type user_role() :: admin | user | guest.

-type user() :: #{
    id := user_id(),
    email := email(),
    name := binary(),
    role := user_role()
}.

-type error_response() :: #{
    error := #{
        code := binary(),
        message := binary()
    }
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
                }
            }
        },
        #{
            path => "/api/users/:user_id",
            allowed_methods => #{
                get => #{
                    tags => [<<"Users">>],
                    summary => <<"Get user by ID">>,
                    parameters => [
                        #{
                            name => <<"user_id">>,
                            in => <<"path">>,
                            required => true,
                            schema => user_id
                        }
                    ],
                    responses => #{
                        <<"200">> => #{
                            description => <<"User found">>,
                            content => #{
                                <<"application/json">> => #{
                                    schema => user
                                }
                            }
                        },
                        <<"404">> => #{
                            description => <<"User not found">>,
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
                handler_mod => comprehensive_handler,
                allowed_methods => AllowedMethods
            },
            trails:trail(Path, comprehensive_handler, State, AllowedMethods)
        end,
        routes()
    ).
