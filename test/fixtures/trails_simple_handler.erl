-module(trails_simple_handler).
-behaviour(trails_handler).

-export([trails/0]).

%% Type definitions
-type user_id() :: binary().
-type user() :: #{
    id := user_id(),
    name := binary(),
    email := binary()
}.

%% Trails callback with OpenAPI 3.0.x metadata
trails() ->
    [
        trails:trail("/api/users/:id", trails_simple_handler, [], #{
            get => #{
                tags => [<<"users">>],
                description => <<"Get user by ID">>,
                parameters => [
                    #{
                        name => <<"id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id
                    }
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Success">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => user
                            }
                        }
                    },
                    <<"404">> => #{
                        description => <<"User not found">>
                    }
                }
            }
        }),
        trails:trail("/api/users", trails_simple_handler, [], #{
            post => #{
                tags => [<<"users">>],
                description => <<"Create a new user">>,
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
                    }
                }
            }
        })
    ].

