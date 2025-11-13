# rebar3_opapi

A rebar3 plugin that generates **OpenAPI 3.0.x** documentation from Erlang handler modules using the standard `trails` library format.

## Features

- ✅ **Standard Compliant**: Uses `trails` library format (compatible with `cowboy_swagger`)
- ✅ **OpenAPI 3.0.x**: Full compliance with OpenAPI 3.0.3 specification
- ✅ **Type-Driven**: Define types once, use everywhere (code + documentation)
- ✅ **Auto-Expansion**: Type references automatically expanded to full `$ref` paths
- ✅ **Auto-Generated IDs**: Unique `operationId` generated for each route
- ✅ **No Duplication**: Types stay in code for documentation & type checking

## Installation

Add the plugin to your `rebar.config`:

```erlang
{project_plugins, [rebar3_opapi]}.

{deps, [
    {trails, ".*", {git, "https://github.com/inaka/cowboy_trails.git", {tag, "..."}}}
]}.
```

## Quick Start

### 1. Define Types

In your handler module, define Erlang types:

```erlang
-module(user_handler).
-behaviour(trails_handler).

%% Type definitions
-type user_id() :: binary().
-type user() :: #{
    id := user_id(),
    name := binary(),
    email := binary(),
    role := user_role()
}.
-type user_role() :: admin | user | guest.
```

### 2. Create Trails Definition

Implement the `trails/0` callback with type references:

```erlang
trails() ->
    [
        trails:trail("/api/users/:id", user_handler, [], #{
            get => #{
                tags => [<<"users">>],
                description => <<"Get user by ID">>,
                parameters => [
                    #{
                        name => <<"id">>,
                        in => <<"path">>,
                        required => true,
                        schema => user_id  % Type reference!
                    }
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Success">>,
                        content => #{
                            <<"application/json">> => #{
                                schema => user  % Type reference!
                            }
                        }
                    },
                    <<"404">> => #{
                        description => <<"User not found">>
                    }
                }
            },
            put => #{
                tags => [<<"users">>],
                description => <<"Update user">>,
                requestBody => #{
                    required => true,
                    content => #{
                        <<"application/json">> => #{
                            schema => user  % Type reference!
                        }
                    }
                },
                responses => #{
                    <<"200">> => #{
                        description => <<"Updated">>,
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
```

### 3. Generate OpenAPI Documentation

Run the plugin:

```bash
rebar3 opapi extract --handler src/user_handler.erl --output openapi.yaml
```

### 4. View Generated OpenAPI

The generated YAML will have:

```yaml
openapi: 3.0.3
info:
  title: API
  version: 1.0.0
paths:
  /api/users/{id}:
    get:
      operationId: getUserById  # Auto-generated
      tags:
        - users
      parameters:
        - name: id
          in: path
          required: true
          schema:
            $ref: '#/components/schemas/UserId'  # Expanded!
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'  # Expanded!
components:
  schemas:
    UserId:
      type: string
    User:
      type: object
      required:
        - id
        - name
        - email
        - role
      properties:
        id:
          $ref: '#/components/schemas/UserId'
        name:
          type: string
        email:
          type: string
        role:
          $ref: '#/components/schemas/UserRole'
    UserRole:
      type: string
      enum:
        - admin
        - user
        - guest
```

## Usage

### Command Line

```bash
rebar3 opapi extract \
  --handler path/to/handler.erl \
  --output openapi.yaml \
  --app MyApp
```

**Options:**
- `--handler` (required): Path to Erlang handler file
- `--output` (required): Output file path (.yaml or .json)
- `--app` (optional): Application name for metadata

### Type References

Use atom type names in metadata:

```erlang
%% Simple type reference
schema => user_id

%% Array type reference
schema => {array, user}

%% Primitive type
schema => binary
schema => integer
schema => float
schema => boolean
```

### Arrays

For array responses, use the `{array, TypeName}` tuple:

```erlang
responses => #{
    <<"200">> => #{
        content => #{
            <<"application/json">> => #{
                schema => {array, user}  % Array of users
            }
        }
    }
}
```

### Supported Type Definitions

- **Primitive types**: `binary()`, `integer()`, `float()`, `boolean()`
- **Map types**: `#{key := Value}` (required), `#{key => Value}` (optional)
- **Union types**: `admin | user | guest` (becomes enum)
- **List types**: `[ItemType]` (becomes array)
- **User-defined types**: References with `$ref`

## Examples

See `test/fixtures/` for complete examples:

- `simple_handler.erl` - Basic example
- `handler_with_types.erl` - Type references example
- `comprehensive_handler.erl` - Full-featured example

## Requirements

- Erlang/OTP 21+
- rebar3
- `trails` library (for handler format)

## OpenAPI 3.0.x Compliance

This plugin generates fully compliant OpenAPI 3.0.3 specifications:

- ✅ Uses `openapi: 3.0.3` (not Swagger 2.0)
- ✅ Uses `components/schemas` (not `definitions`)
- ✅ Uses `requestBody` object (not `body` in parameters)
- ✅ Uses `content` map with media types
- ✅ Parameters have `schema` field
- ✅ Response keys as strings: `"200"`
- ✅ Path parameters: `:id` → `{id}`

## Contributing

Contributions welcome! Please ensure all tests pass:

```bash
rebar3 eunit
```

## License

[Add your license here]

## Credits

Inspired by `cowboy_swagger` and built for OpenAPI 3.0.x compliance.

