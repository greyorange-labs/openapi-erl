# rebar3_openapi

A rebar3 plugin that generates **OpenAPI 3.0.x** documentation from Erlang handler modules using the standard `trails` library format.

## Features

- ✅ **Standard Compliant**: Uses `trails` library format (compatible with `cowboy_swagger`)
- ✅ **OpenAPI 3.0.x**: Full compliance with OpenAPI 3.0.3 specification
- ✅ **Type-Driven**: Define types once, use everywhere (code + documentation)
- ✅ **Auto-Expansion**: Type references automatically expanded to full `$ref` paths
- ✅ **Auto-Generated IDs**: Unique `operationId` generated for each route
- ✅ **No Duplication**: Types stay in code for documentation & type checking
- ✅ **Shared Library**: Uses `gm_type_schema_converter` for type-to-schema conversion (shared with runtime validation)

## Installation

Add the plugin to your `rebar.config`:

```erlang
{project_plugins, [rebar3_openapi]}.

{deps, [
    {trails, ".*", {git, "https://github.com/inaka/cowboy_trails.git", {tag, "..."}}},
    {gm_type_schema_converter, {git, "git@github.com:greyorange-labs/gm_type_schema_converter.git", {branch, "main"}}}
]}.
```

**Note:** This plugin requires `yq` CLI tool (v4+) to be installed on your system for YAML output generation. Install from: https://github.com/mikefarah/yq

## Quick Start

### 1. Define Types

In your handler module, define Erlang types:
`gm_http_handler` is the root handler for all routes.

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
        trails:trail("/api/users/:id", gm_http_handler, [], #{
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
rebar3 openapi extract --handler src/user_handler.erl --output openapi.yaml
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
rebar3 openapi extract \
  --handler apps/butler_shared/src/interfaces/in/gm_common_http_handler.erl \
  --output openapi.yaml \
  --app butler_shared
```

**Options:**
- `--handler` (required): Path to Erlang handler file
- `--output` (required): Output file path (.yaml or .json)
- `--app` (optional): Application name for metadata

### Handler Generation

Generate a template HTTP handler module with example routes to get started quickly:

```bash
rebar3 openapi generate_handler --app pick
```

This command generates a handler module at:
```
apps/pick/src/interfaces/in/pick_http_handler.erl
```

**What's Generated:**
- Module with proper compile directives (`-compile(nowarn_unused_type)`, `-compile({parse_transform, gm_schema_extract_pt})`)
- Include directive for common headers (`-include("src/gm_common.hrl")`)
- Export list with `start_handlers/0`, `trails/0`, and `handle_request/3`
- Type definitions section with TODO comments and examples
- `trails/0` function with three example routes:
  - **GET** `/api/items/:id` - Retrieve resource by ID
  - **POST** `/api/items` - Create new resource
  - **PUT** `/api/items/:id` - Update existing resource
- `handle_request/3` function with default 501 response
- Helpful comments throughout for developers

**After Generation:**
1. Customize the route paths and metadata to match your API
2. Define your type definitions in the Type Definitions section
3. Replace `binary` schema references with your actual types
4. Implement the `handle_request/3` function clauses for each operation

**Example:**
```bash
# Generate handler for 'pick' app
rebar3 openapi generate_handler --app pick

# Generated file: apps/pick/src/interfaces/in/pick_http_handler.erl
```

**Note:** The command will fail if the target file already exists. Ensure the app directory structure exists or the command will create the necessary directories.

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

## Supported Type Definitions

- **Primitive types**: `binary()`, `integer()`, `float()`, `boolean()`
- **Map types**: `#{key := Value}` (required), `#{key => Value}` (optional)
- **Union types**: `admin | user | guest` (becomes enum)
- **List types**: `[ItemType]` (becomes array)
- **User-defined types**: References with `$ref`
- **Circular references**: Handled automatically with `$ref`

## Architecture

### Processing Flow

```
Handler File (trails/0 + types)
    ↓
[Parser] Extract trails + types
    ↓
[Expander] Expand type refs → $refs, Generate operationId
    ↓
[Schema Converter] Types → OpenAPI schemas (via gm_type_schema_converter)
    ↓
[Builder] Assemble OpenAPI 3.0.x document
    ↓
[Provider] Convert to JSON, then YAML (via yq CLI)
    ↓
OpenAPI YAML/JSON file
```

### Module Overview

#### Core Modules

1. **`rebar3_openapi_parser.erl`**
   - Extracts `trails/0` callback definitions
   - Extracts `-type` definitions from AST
   - Parses Erlang files with includes

2. **`rebar3_openapi_expander.erl`**
   - Generates unique `operationId` for each operation
   - Expands type atoms → `$ref` paths
   - Converts `schema => user_id` → `schema => #{$ref => "#/components/schemas/UserId"}`

3. **`gm_type_schema_converter`** (Shared Library)
   - Converts Erlang type AST → OpenAPI JSON Schema
   - Handles primitives, maps, unions, lists, circular refs
   - Capitalizes names: `user_id` → `UserId`
   - Shared with runtime schema validation

4. **`rebar3_openapi_builder.erl`**
   - Builds complete OpenAPI 3.0.x document structure
   - Converts paths: `:id` → `{id}` (OpenAPI format)
   - Assembles paths, components, info sections

5. **`rebar3_openapi_prv_extract.erl`**
   - rebar3 provider that orchestrates the pipeline
   - Converts map → JSON using `jsx:encode()`
   - Converts JSON → YAML using `yq` CLI tool

### Type System

#### Erlang → OpenAPI Mapping

| Erlang Type       | OpenAPI Schema                                               |
| ----------------- | ------------------------------------------------------------ |
| `binary()`        | `{type: "string"}`                                           |
| `integer()`       | `{type: "integer"}`                                          |
| `float()`         | `{type: "number"}`                                           |
| `boolean()`       | `{type: "boolean"}`                                          |
| `#{key := Value}` | `{type: "object", required: ["key"], properties: {...}}`     |
| `#{key => Value}` | `{type: "object", properties: {...}}` (optional)             |
| `Type1 \| Type2`  | `{oneOf: [{...}, {...}]}` or `{type: "string", enum: [...]}` |
| `[ItemType]`      | `{type: "array", items: {...}}`                              |
| `user_type()`     | `{$ref: "#/components/schemas/UserType"}`                    |

#### Type Reference Resolution

1. **In Metadata:** `schema => user_id` (atom)
2. **Expanded:** `schema => #{$ref => "#/components/schemas/UserId"}`
3. **Resolved:** Schema fetched from `components/schemas/UserId`

#### Circular References

Handled automatically by tracking visited types and using `$ref` to break cycles:

```erlang
-type node() :: #{value := binary(), children := [node()]}.
```

Converts to:
```yaml
Node:
  type: object
  properties:
    value:
      type: string
    children:
      type: array
      items:
        $ref: '#/components/schemas/Node'  # Circular ref broken
```

## OpenAPI 3.0.x Compliance

### Key Differences from Swagger 2.0

| Swagger 2.0                 | OpenAPI 3.0.x                  |
| --------------------------- | ------------------------------ |
| `swagger: "2.0"`            | `openapi: "3.0.3"`             |
| `definitions`               | `components/schemas`           |
| `body` in parameters        | `requestBody` object           |
| Direct `type` in responses  | `content` map with media types |
| `200` (number)              | `"200"` (string)               |
| `host` + `basePath`         | `servers` array                |
| Direct `type` in parameters | `schema` field                 |

### This Plugin Ensures

- ✅ Uses `openapi: 3.0.3` (not Swagger 2.0)
- ✅ Uses `components/schemas` (not `definitions`)
- ✅ Uses `requestBody` object (not `body` in parameters)
- ✅ Uses `content` map with media types
- ✅ Parameters have `schema` field
- ✅ Response keys as strings: `"200"`
- ✅ Path parameters: `:id` → `{id}`
- ✅ Unique `operationId` for each operation
- ✅ All schemas use `$ref: '#/components/schemas/TypeName'`

## Examples

See `test/fixtures/` for complete examples:

- `simple_handler.erl` - Basic example
- `handler_with_types.erl` - Type references example
- `comprehensive_handler.erl` - Full-featured example

## Dependencies

### Runtime Dependencies
- **rebar3**: Build tool
- **trails**: Route definition library
- **jsx**: JSON encoding library
- **gm_type_schema_converter**: Shared type-to-schema converter library

### External Tools
- **yq**: CLI tool (v4+) for JSON to YAML conversion
  - Install from: https://github.com/mikefarah/yq
  - Required for YAML output generation

## Output Generation

### JSON + yq Approach

The plugin uses a two-step process for YAML generation:

1. **JSON Generation**: Converts OpenAPI document map to ordered proplist and encodes to JSON using `jsx:encode()`
2. **YAML Conversion**: Uses `yq` CLI tool to convert JSON to YAML

**Why this approach?**
- Avoids YAML quoting issues (especially with `$ref` values)
- Preserves OpenAPI 3.0.3 field ordering (openapi, info, servers, paths, components)
- Reliable JSON encoding with `jsx` library
- Clean YAML output via `yq` CLI tool

## Requirements

- Erlang/OTP 21+
- rebar3
- `trails` library (for handler format)
- `yq` CLI tool (v4+) for YAML output

## Testing

Run the test suite:

```bash
rebar3 eunit
```

**Test Coverage:**
- **Unit Tests**: Parser, expander, converter, builder (22 tests)
- **Integration Tests**: End-to-end flow with real handler files (2 tests)
- **Total**: 29 tests (all passing)

## Contributing

Contributions welcome! Please ensure all tests pass:

```bash
rebar3 eunit
```

## Code Sharing

This plugin uses `gm_type_schema_converter` library for type-to-schema conversion. This shared library:
- Eliminates code duplication
- Provides single source of truth for type conversion logic
- Is also used by runtime schema validation in production applications

## License

[Add your license here]

## Credits

Inspired by `cowboy_swagger` and built for OpenAPI 3.0.x compliance.
