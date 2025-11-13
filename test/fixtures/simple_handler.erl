-module(simple_handler).
-behaviour(trails_handler).

-export([trails/0]).

%%%===================================================================
%%% Simple handler for testing route extraction with trails
%%%===================================================================

trails() ->
    [
        trails:trail("/api/test", simple_handler, [], #{
            get => #{
                tags => [<<"test">>],
                description => <<"Simple test endpoint">>,
                responses => #{
                    <<"200">> => #{
                        description => <<"Success">>
                    }
                }
            }
        }),
        trails:trail("/api/users", simple_handler, [], #{
            post => #{
                tags => [<<"users">>],
                description => <<"Create a user">>,
                responses => #{
                    <<"201">> => #{
                        description => <<"User created">>
                    }
                }
            }
        })
    ].
