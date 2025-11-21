-module(handler_with_types).
-compile(nowarn_unused_type).

-export([
    routes/0,
    trails/0
]).

%%%===================================================================
%%% Type Definitions (Used for schema generation)
%%%===================================================================

%% Simple user type
-type user() :: #{
    id := binary(),
    name := binary(),
    email := binary(),
    % Optional field
    age => integer()
}.

%% User role enum
-type user_role() :: admin | user | guest.

%% Create user request
-type create_user_request() :: #{
    name := binary(),
    email := binary(),
    % Optional, defaults to 'user'
    role => user_role()
}.

%% Error response
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
        %% GET /api/users - List all users
        #{
            path => "/api/users",
            allowed_methods => #{
                get => #{
                    tags => [<<"Users">>],
                    summary => <<"List all users">>,
                    description => <<"Retrieves a list of users">>,
                    responses => #{
                        <<"200">> => #{
                            description => <<"Successfully retrieved users">>,
                            content => #{
                                <<"application/json">> => #{
                                    % Array of user type
                                    schema => {array, user}
                                }
                            }
                        }
                    }
                },
                %% POST /api/users - Create a new user
                post => #{
                    tags => [<<"Users">>],
                    summary => <<"Create a new user">>,
                    description => <<"Creates a new user with the provided data">>,
                    requestBody => #{
                        required => true,
                        content => #{
                            <<"application/json">> => #{
                                schema => create_user_request
                            }
                        }
                    },
                    responses => #{
                        <<"201">> => #{
                            description => <<"User created successfully">>,
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
        },
        %% GET /api/users/:user_id - Get user by ID
        #{
            path => "/api/users/:user_id",
            allowed_methods => #{
                get => #{
                    tags => [<<"Users">>],
                    summary => <<"Get user by ID">>,
                    description => <<"Retrieves a single user by their ID">>,
                    parameters => [
                        #{
                            name => <<"user_id">>,
                            in => <<"path">>,
                            required => true,
                            % Use binary type directly
                            schema => binary
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
                handler_mod => handler_with_types,
                allowed_methods => AllowedMethods
            },
            trails:trail(Path, handler_with_types, State, AllowedMethods)
        end,
        routes()
    ).
