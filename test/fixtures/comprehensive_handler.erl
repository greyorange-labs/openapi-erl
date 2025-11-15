-module(comprehensive_handler).
-compile(nowarn_unused_type).

-export([trails/0]).

%%%===================================================================
%%% Type Definitions (Common Schemas)
%%%===================================================================

%% Common types used across multiple routes
-type user_id() :: binary().
-type email() :: binary().
-type timestamp() :: integer().

%% User object - used in multiple responses
-type user() :: #{
    id := user_id(),
    email := email(),
    name := binary(),
    role := user_role(),
    % Optional field
    age => integer(),
    % Optional nested object
    metadata => map(),
    created_at := timestamp()
}.

%% Enum type for user roles
-type user_role() :: admin | user | guest.

%% User status enum
-type user_status() :: active | inactive | suspended | deleted.

%% Address object - nested in user profile
-type address() :: #{
    street := binary(),
    city := binary(),
    state := binary(),
    zip_code := binary(),
    country := binary()
}.

%% User profile with nested objects
-type user_profile() :: #{
    user_id := user_id(),
    % Optional
    bio => binary(),
    % Optional
    avatar_url => binary(),
    % Optional nested object
    address => address(),
    preferences := user_preferences()
}.

%% Preferences object - nested in profile
-type user_preferences() :: #{
    notifications := boolean(),
    theme := light | dark,
    language := binary()
}.

%% Paginated response - common pattern
-type paginated_response(ItemType) :: #{
    items := [ItemType],
    total := integer(),
    page := integer(),
    page_size := integer(),
    has_more := boolean()
}.

%% Error response - common across all routes
-type error_response() :: #{
    error := #{
        code := binary(),
        message := binary(),
        % Optional array
        details => [binary()]
    }
}.

%% Product object for e-commerce example
-type product() :: #{
    id := binary(),
    name := binary(),
    % Optional
    description => binary(),
    price := #{
        amount := float(),
        currency := binary()
    },
    % Array of strings
    tags := [binary()],
    % Array of objects
    variants := [product_variant()],
    in_stock := boolean(),
    category := product_category()
}.

-type product_variant() :: #{
    sku := binary(),
    name := binary(),
    price_adjustment := float(),
    attributes := map()
}.

-type product_category() :: electronics | clothing | books | food | other.

%% Order object with nested arrays and objects
-type order() :: #{
    id := binary(),
    user_id := user_id(),
    items := [order_item()],
    shipping_address := address(),
    % Optional, may differ from shipping
    billing_address => address(),
    total := #{
        subtotal := float(),
        tax := float(),
        shipping := float(),
        total := float()
    },
    status := order_status(),
    created_at := timestamp(),
    updated_at := timestamp()
}.

-type order_item() :: #{
    product_id := binary(),
    % Optional
    variant_sku => binary(),
    quantity := integer(),
    unit_price := float(),
    total_price := float()
}.

-type order_status() :: pending | processing | shipped | delivered | cancelled | refunded.

%% Create user request type
-type create_user_request() :: #{
    email := email(),
    name := binary(),
    role := user_role(),
    age => integer(),
    metadata => map()
}.

%% Update user request type
-type update_user_request() :: #{
    name => binary(),
    role => user_role(),
    age => integer()
}.

%% Update profile request type
-type update_profile_request() :: #{
    bio => binary(),
    avatar_url => binary(),
    address => address(),
    preferences => user_preferences()
}.

%% Create order request type
-type create_order_request() :: #{
    user_id := user_id(),
    items := [order_item()],
    shipping_address := address(),
    billing_address => address()
}.

%%%===================================================================
%%% Trails Definition (Using type references)
%%%===================================================================

trails() ->
    [
        %% GET /api/users - List users with pagination
        trails:trail("/api/users", comprehensive_handler, [], #{
            get => #{
                tags => [<<"Users">>],
                summary => <<"List all users with pagination">>,
                description => <<"Retrieves a paginated list of users. Supports filtering by role and status.">>,
                parameters => [
                    #{
                        name => <<"page">>,
                        in => <<"query">>,
                        required => false,
                        schema => integer,
                        description => <<"Page number">>
                    },
                    #{
                        name => <<"page_size">>,
                        in => <<"query">>,
                        required => false,
                        schema => integer,
                        description => <<"Number of items per page">>
                    },
                    #{
                        name => <<"role">>,
                        in => <<"query">>,
                        required => false,
                        schema => user_role,
                        description => <<"Filter by user role">>
                    },
                    #{
                        name => <<"status">>,
                        in => <<"query">>,
                        required => false,
                        schema => user_status,
                        description => <<"Filter by user status">>
                    }
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Successfully retrieved users">>,
                        content => #{
                            <<"application/json">> => #{
                                % Array of users
                                schema => {array, user}
                            }
                        }
                    },
                    <<"400">> => #{
                        description => <<"Invalid request parameters">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => error_response
                            }
                        }
                    }
                }
            },
            %% POST /api/users - Create a new user
            post => #{
                tags => [<<"Users">>],
                summary => <<"Create a new user">>,
                description => <<"Creates a new user account with the provided information">>,
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
                    },
                    <<"409">> => #{
                        description => <<"User with this email already exists">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => error_response
                            }
                        }
                    }
                }
            }
        }),
        %% GET/PUT/DELETE /api/users/:user_id
        trails:trail("/api/users/:user_id", comprehensive_handler, [], #{
            get => #{
                tags => [<<"Users">>],
                summary => <<"Get user by ID">>,
                description => <<"Retrieves detailed information about a specific user">>,
                parameters => [
                    #{
                        name => <<"user_id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id,
                        description => <<"Unique user identifier">>
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
            },
            put => #{
                tags => [<<"Users">>],
                summary => <<"Update user information">>,
                description => <<"Updates an existing user's information. All fields are optional.">>,
                parameters => [
                    #{
                        name => <<"user_id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id,
                        description => <<"Unique user identifier">>
                    }
                ],
                requestBody => #{
                    required => true,
                    content => #{
                        <<"application/json">> => #{
                            schema => update_user_request
                        }
                    }
                },
                responses => #{
                    <<"200">> => #{
                        description => <<"User updated successfully">>,
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
            },
            delete => #{
                tags => [<<"Users">>],
                summary => <<"Delete user">>,
                description => <<"Permanently deletes a user account">>,
                parameters => [
                    #{
                        name => <<"user_id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id,
                        description => <<"Unique user identifier">>
                    }
                ],
                responses => #{
                    <<"204">> => #{
                        description => <<"User deleted successfully">>
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
        }),
        %% GET/PATCH /api/users/:user_id/profile
        trails:trail("/api/users/:user_id/profile", comprehensive_handler, [], #{
            get => #{
                tags => [<<"Users">>, <<"Profiles">>],
                summary => <<"Get user profile">>,
                description => <<"Retrieves detailed profile information including nested objects">>,
                parameters => [
                    #{
                        name => <<"user_id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id,
                        description => <<"Unique user identifier">>
                    }
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Profile found">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => user_profile
                            }
                        }
                    },
                    <<"404">> => #{
                        description => <<"Profile not found">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => error_response
                            }
                        }
                    }
                }
            },
            patch => #{
                tags => [<<"Users">>, <<"Profiles">>],
                summary => <<"Update user profile">>,
                description => <<"Updates user profile with nested objects like address and preferences">>,
                parameters => [
                    #{
                        name => <<"user_id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id,
                        description => <<"Unique user identifier">>
                    }
                ],
                requestBody => #{
                    required => true,
                    content => #{
                        <<"application/json">> => #{
                            schema => update_profile_request
                        }
                    }
                },
                responses => #{
                    <<"200">> => #{
                        description => <<"Profile updated">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => user_profile
                            }
                        }
                    },
                    <<"404">> => #{
                        description => <<"Profile not found">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => error_response
                            }
                        }
                    }
                }
            }
        }),
        %% GET /api/products
        trails:trail("/api/products", comprehensive_handler, [], #{
            get => #{
                tags => [<<"Products">>],
                summary => <<"List products">>,
                description => <<"Retrieves paginated list of products with complex nested structures">>,
                parameters => [
                    #{
                        name => <<"category">>,
                        in => <<"query">>,
                        required => false,
                        schema => product_category,
                        description => <<"Filter by product category">>
                    },
                    #{
                        name => <<"in_stock">>,
                        in => <<"query">>,
                        required => false,
                        schema => boolean,
                        description => <<"Filter by availability">>
                    }
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Products retrieved">>,
                        content => #{
                            <<"application/json">> => #{
                                % Array of products
                                schema => {array, product}
                            }
                        }
                    }
                }
            }
        }),
        %% POST /api/orders
        trails:trail("/api/orders", comprehensive_handler, [], #{
            post => #{
                tags => [<<"Orders">>],
                summary => <<"Create new order">>,
                description => <<"Creates a new order with multiple items, shipping and billing addresses">>,
                requestBody => #{
                    required => true,
                    content => #{
                        <<"application/json">> => #{
                            schema => create_order_request
                        }
                    }
                },
                responses => #{
                    <<"201">> => #{
                        description => <<"Order created">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => order
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
        }),
        %% GET /api/orders/:order_id
        trails:trail("/api/orders/:order_id", comprehensive_handler, [], #{
            get => #{
                tags => [<<"Orders">>],
                summary => <<"Get order details">>,
                description => <<"Retrieves complete order information with nested items and addresses">>,
                parameters => [
                    #{
                        name => <<"order_id">>,
                        in => <<"path">>,
                        required => true,
                        schema => binary,
                        description => <<"Unique order identifier">>
                    }
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Order found">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => order
                            }
                        }
                    },
                    <<"404">> => #{
                        description => <<"Order not found">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => error_response
                            }
                        }
                    }
                }
            }
        })
    ].
