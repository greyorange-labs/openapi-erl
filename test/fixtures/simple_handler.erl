-module(simple_handler).
-compile(nowarn_unused_type).

-export([
    routes/0,
    trails/0
]).

%%%===================================================================
%%% Simple handler for testing route extraction with trails
%%%===================================================================

routes() ->
    [
        #{
            path => "/api/test",
            allowed_methods => #{
                get => #{
                    tags => [<<"test">>],
                    description => <<"Simple test endpoint">>,
                    responses => #{
                        <<"200">> => #{
                            description => <<"Success">>
                        }
                    }
                }
            }
        },
        #{
            path => "/api/users",
            allowed_methods => #{
                post => #{
                    tags => [<<"users">>],
                    description => <<"Create a user">>,
                    responses => #{
                        <<"201">> => #{
                            description => <<"User created">>
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
                handler_mod => simple_handler,
                allowed_methods => AllowedMethods
            },
            trails:trail(Path, simple_handler, State, AllowedMethods)
        end,
        routes()
    ).
