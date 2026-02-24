# rebar3_openapi

A rebar3 plugin that generates **OpenAPI 3.0.x** documentation from Erlang handler modules using the `trails` library format.

## Features

- **Standard Compliant** -- Generates OpenAPI 3.0.3 documents
- **Trails Integration** -- Uses `trails` library format (compatible with `cowboy_swagger`)
- **Type-Driven** -- Erlang `-type` definitions drive schema generation
- **Auto-Expansion** -- Type references automatically expanded to `$ref` paths
- **Auto-Generated IDs** -- Unique `operationId` generated for each route
- **Shared Converter** -- Uses [`gm_type_schema_converter`](https://github.com/greyorange-labs/gm_type_schema_converter) for type-to-schema conversion (shared with runtime validation)

## Installation

Add the plugin to your `rebar.config`:

```erlang
{project_plugins, [rebar3_openapi]}.

{deps, [
    {trails, ".*", {git, "https://github.com/inaka/cowboy_trails.git", {tag, "..."}}},
    {gm_type_schema_converter, {git, "git@github.com:greyorange-labs/gm_type_schema_converter.git", {branch, "main"}}}
]}.
```

**External tool required:** [`yq`](https://github.com/mikefarah/yq) v4+ for YAML output generation.

## Usage

```bash
rebar3 openapi extract \
  --handler apps/my_app/src/my_handler.erl \
  --output openapi.yaml \
  --app my_app
```

| Option | Required | Description |
|--------|----------|-------------|
| `--handler` | Yes | Path to Erlang handler file(s) |
| `--output` | Yes | Output file path (`.yaml` or `.json`) |
| `--app` | Yes | Application name for info metadata |

## Architecture

### Processing Pipeline

```
Handler .erl File
    │
    ├── [Parser] Extract -type definitions from AST
    │
    ├── [Runtime] Call trails/0 to get route metadata
    │
    ├── [Expander] Type atoms → $ref paths, generate operationId
    │
    ├── [Converter] Erlang type ASTs → OpenAPI JSON schemas
    │   (via gm_type_schema_converter)
    │
    ├── [Builder] Assemble OpenAPI 3.0.3 document
    │
    └── [Provider] JSON → YAML (via yq CLI)
            │
            ▼
      openapi.yaml
```

### Modules

| Module | Responsibility |
|--------|---------------|
| `rebar3_openapi` | Plugin entry point -- registers the provider with rebar3 |
| `rebar3_openapi_prv_extract` | Provider -- orchestrates the full pipeline, handles CLI args, writes output |
| `rebar3_openapi_parser` | Extracts `-type` definitions and remote type references from Erlang AST |
| `rebar3_openapi_expander` | Expands type atoms to `$ref` paths, generates `operationId`, handles nullable/array wrappers |
| `rebar3_openapi_builder` | Builds complete OpenAPI document -- paths, components, info (reads `.app.src` for version/description) |

### How Type Expansion Works

In handler metadata, types are referenced as atoms:

```erlang
%% In trails/0 metadata
get => #{
    parameters => [
        #{name => <<"id">>, in => <<"path">>, schema => user_id}
    ],
    responses => #{
        <<"200">> => #{
            content => #{
                <<"application/json">> => #{schema => user}
            }
        }
    }
}
```

The expander converts these to `$ref` paths:

```yaml
# After expansion
parameters:
  - name: id
    in: path
    schema:
      $ref: '#/components/schemas/UserId'
responses:
  '200':
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/User'
```

The converter (`gm_type_schema_converter`) then generates the actual schemas from Erlang `-type` definitions:

```erlang
-type user_id() :: binary().
-type user() :: #{
    id := user_id(),
    name := binary(),
    role := user_role()
}.
```

becomes:

```yaml
components:
  schemas:
    UserId:
      type: string
    User:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/UserId'
        name:
          type: string
        role:
          $ref: '#/components/schemas/UserRole'
      required: [id, name, role]
```

### Special Schema Wrappers

The expander supports these wrapper forms in trail metadata:

| Wrapper | Example | Result |
|---------|---------|--------|
| Array | `{array, user}` | `{type: array, items: {$ref: ...User}}` |
| Nullable | `{nullable, user}` | `{oneOf: [{$ref: ...User}, {type: null}]}` |
| Nullable array | `{nullable, {array, user}}` | `{oneOf: [{type: array, items: ...}, {type: null}]}` |

### YAML Output Strategy

The plugin uses a two-step JSON-then-YAML approach:

1. **JSON**: `jsx:encode()` with ordered proplists for deterministic field ordering
2. **YAML**: `yq` CLI converts JSON to clean YAML

This avoids YAML quoting issues (especially with `$ref` values) and preserves OpenAPI field ordering.

## Handler Example

```erlang
-module(my_handler).
-behaviour(trails_handler).
-export([trails/0]).

%% Types become schemas
-type user_id() :: binary().
-type user() :: #{
    id := user_id(),
    name := binary(),
    active => boolean()  %% => means optional
}.

trails() ->
    [trails:trail(
        <<"/api/users/:id">>,
        ?MODULE,
        #{},
        #{
            get => #{
                tags => [<<"Users">>],
                description => <<"Get user by ID">>,
                parameters => [
                    #{name => <<"id">>, in => <<"path">>,
                      required => true, schema => user_id}
                ],
                responses => #{
                    <<"200">> => #{
                        description => <<"Success">>,
                        content => #{
                            <<"application/json">> => #{schema => user}
                        }
                    }
                }
            }
        }
    )].
```

See `test/fixtures/` for more examples:
- `simple_handler.erl` -- Basic handler
- `handler_with_types.erl` -- Type references
- `comprehensive_handler.erl` -- All HTTP methods, parameters, request bodies, arrays, enums

## Dependencies

| Dependency | Purpose |
|-----------|---------|
| `trails` | Route definition library (cowboy integration) |
| `jsx` | JSON encoding |
| `gm_type_schema_converter` | Erlang type AST to OpenAPI JSON Schema |
| `yq` (external CLI) | JSON to YAML conversion |

## Development

```bash
# Compile
make compile        # or: rebar3 compile

# Run tests (46 tests)
make test           # or: rebar3 eunit

# Format code (erlfmt, 130 char width)
make format         # or: rebar3 fmt
make check-format   # or: rebar3 fmt --check

# Clean
make clean          # or: rebar3 clean
```

### Requirements

- Erlang/OTP 27+
- rebar3
- `yq` v4+ (for YAML output)

## License

Copyright (C) 2025, Grey Orange
