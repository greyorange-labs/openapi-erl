# Architecture

## Overview

`rebar3_openapi` is a rebar3 plugin that extracts OpenAPI 3.0.x documentation from Erlang handler modules using the `trails` library format. It converts Erlang type definitions and trails metadata into fully compliant OpenAPI specifications.

## Architecture Flow

```
Handler File (trails/0 + types)
    ↓
[Parser] Extract trails + types
    ↓
[Expander] Expand type refs → $refs
    ↓
[Schema Converter] Types → OpenAPI schemas
    ↓
[Builder] Assemble OpenAPI 3.0.x document
    ↓
[Provider] Convert map → ordered proplist
    ↓
[jsx] Encode to JSON
    ↓
[yq CLI] Convert JSON → YAML
    ↓
OpenAPI YAML/JSON file
```

### Detailed Processing Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Input: Handler File                                          │
│ - trails/0 callback with metadata                           │
│ - -type definitions                                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ [Parser] rebar3_openapi_parser.erl                            │
│ - Extract trails/0 function body                            │
│ - Extract -type definitions (AST)                            │
│ Output: {Trails, Types}                                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ [Expander] rebar3_openapi_expander.erl                         │
│ - Generate operationId for each operation                    │
│ - Expand type atoms → $ref paths                             │
│   schema => user_id → schema => #{$ref => "#/components/..."}│
│ Output: Expanded trails with $refs                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ [Schema Converter] rebar3_openapi_schema_converter.erl        │
│ - Convert Erlang type AST → OpenAPI JSON Schema              │
│ - Handle primitives, maps, unions, lists, circular refs     │
│ - Capitalize names: user_id → UserId                         │
│ Output: #{SchemaName => SchemaMap}                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ [Builder] rebar3_openapi_builder.erl                          │
│ - Build OpenAPI document structure                           │
│ - Convert paths: :id → {id}                                  │
│ - Assemble: openapi, info, servers, paths, components        │
│ Output: Complete OpenAPI 3.0.3 document (map)               │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ [Provider] rebar3_openapi_prv_extract.erl                     │
│ - Convert map → ordered proplist (preserve field order)      │
│ - Encode to JSON using jsx:encode()                         │
│ - Write JSON to temp file                                    │
│ - Convert JSON → YAML using yq CLI tool                     │
│ Output: OpenAPI YAML/JSON file                               │
└─────────────────────────────────────────────────────────────┘
```

## Module Structure

### Core Modules

#### `rebar3_openapi_parser.erl`
**Purpose:** Parse Erlang source files and extract trails metadata and type definitions.

**Key Functions:**
- `extract_trails/1` - Extracts `trails/0` callback definitions
- `extract_types/1` - Extracts `-type` definitions
- `parse_file/2` - Parse Erlang file with includes

**Output:**
- `[trail()]` - List of trails with unparsed metadata
- `[type_def()]` - List of type definitions (AST)

**Type Definitions:**
```erlang
-type trail() :: #{
    path => binary(),
    handler => atom(),
    options => map() | list(),
    metadata => map()  % Per-method metadata (get, post, etc.)
}.
```

---

#### `rebar3_openapi_expander.erl`
**Purpose:** Expand type references in trails metadata to OpenAPI 3.0.x compliant structures.

**Key Functions:**
- `expand_trails/2` - Expand all trails with type references
- `expand_operation/4` - Expand single operation metadata
- `generate_operation_id/2` - Auto-generate unique operationId
- `expand_parameters/2` - Expand parameter schemas
- `expand_request_body/2` - Expand requestBody schemas
- `expand_responses/2` - Expand response schemas
- `type_ref_to_schema_ref/1` - Convert type atom to `$ref` path

**Expansion Logic:**
1. Generate unique `operationId` if not present (format: `{method}{Path}`)
2. Expand `schema => TypeAtom` to `schema => #{<<"$ref">> => <<"#/components/schemas/TypeName">>}`
3. Expand `schema => {array, ItemType}` to OpenAPI array schema
4. Ensure OpenAPI 3.0.x structure compliance

**Input:** Trails with type references (atoms)
**Output:** Trails with expanded `$ref` paths

---

#### `rebar3_openapi_schema_converter.erl`
**Purpose:** Convert Erlang type definitions (AST) to OpenAPI JSON Schema format.

**Key Functions:**
- `types_to_schemas/1` - Convert list of types to schemas map
- `type_to_schema/2` - Convert single type to schema
- `capitalize_type_name/1` - Convert atom to capitalized binary

**Supported Types:**
- **Primitive**: `binary()` → `{type: "string"}`
- **Numbers**: `integer()` → `{type: "integer"}`, `float()` → `{type: "number"}`
- **Boolean**: `boolean()` → `{type: "boolean"}`
- **Maps**: `#{key := Value}` → object with `required: ["key"]`
- **Unions**: `admin | user | guest` → `{type: "string", enum: [...]}`
- **Lists**: `[ItemType]` → `{type: "array", items: {...}}`
- **References**: User types → `{$ref: "#/components/schemas/TypeName"}`
- **Circular**: Handled with `$ref` to break cycles

**Input:** `[type_def()]` (AST)
**Output:** `#{SchemaName => SchemaMap}`

---

#### `rebar3_openapi_builder.erl`
**Purpose:** Build complete OpenAPI 3.0.x document structure.

**Key Functions:**
- `build_from_trails/3` - Build document from expanded trails
- `build_paths_from_trails/1` - Build paths section
- `build_components/1` - Build components/schemas section
- `convert_path_params/1` - Convert `:id` to `{id}` (OpenAPI format)
- `operation_meta_to_openapi/1` - Convert metadata to OpenAPI operation

**OpenAPI Structure:**
```erlang
#{
    <<"openapi">> => <<"3.0.3">>,
    <<"info">> => #{...},
    <<"servers">> => [...],
    <<"paths">> => #{...},
    <<"components">> => #{
        <<"schemas">> => #{...}
    }
}
```

---

#### `rebar3_openapi_prv_extract.erl`
**Purpose:** rebar3 provider that orchestrates the extraction pipeline.

**Flow:**
```erlang
1. Parse handler file → extract trails + types
2. Expand trails metadata (type refs → $refs)
3. Convert types to schemas
4. Build OpenAPI 3.0.x document
5. Convert map → ordered proplist (preserve field order)
6. Encode to JSON using jsx:encode()
7. Convert JSON → YAML using yq CLI tool (if YAML output)
8. Write final file
```

**CLI Interface:**
```bash
rebar3 openapi extract \
  --handler path/to/handler.erl \
  --output openapi.yaml \
  --app MyApp
```

---

#### Output Generation (JSON + yq Approach)

**Purpose:** Generate OpenAPI YAML/JSON files with proper formatting and field ordering.

**Implementation:**
- `map_to_ordered_proplist/1` - Converts OpenAPI document map to ordered proplist
- `write_json_file/2` - Encodes proplist to JSON using `jsx:encode()`
- `write_yaml_file/2` - Encodes to JSON, then converts to YAML using `yq` CLI tool
- `convert_json_to_yaml/2` - Executes `yq -o yaml` command for conversion

**Why JSON + yq?**
- Avoids YAML quoting issues (especially with `$ref` values)
- Preserves OpenAPI 3.0.3 field ordering (openapi, info, servers, paths, components)
- Reliable JSON encoding with `jsx` library
- Clean YAML output via `yq` CLI tool

**Dependencies:**
- `jsx` (Erlang library) - JSON encoding
- `yq` (CLI tool v4+) - JSON to YAML conversion

---

### Test Modules

#### `rebar3_openapi_parser_tests.erl`
- `extract_trails_from_handler_test/0`
- `extract_types_from_handler_test/0`
- `extract_metadata_with_type_refs_test/0`

#### `rebar3_openapi_expander_tests.erl`
- `generate_unique_operation_id_test/0`
- `expand_parameter_with_type_ref_test/0`
- `expand_request_body_with_type_ref_test/0`
- `expand_response_with_type_ref_test/0`
- `expand_complete_trail_test/0`

#### `rebar3_openapi_schema_converter_tests.erl`
- 11 tests covering all type conversions
- Primitives, maps, unions, lists, references, circular refs

#### `rebar3_openapi_builder_tests.erl`
- `build_paths_from_trails_test/0`
- `build_components_with_schemas_test/0`
- `build_complete_openapi_doc_test/0`

#### `rebar3_openapi_integration_tests.erl`
- `simple_handler_end_to_end_test/0`
- `comprehensive_handler_end_to_end_test/0`

**Total: 24 tests (all passing)**

---

## Data Flow

### 1. Parsing Phase

**Input:** Erlang source file
```erlang
-module(user_handler).
-behaviour(trails_handler).

-type user() :: #{id := binary(), name := binary()}.

trails() ->
    [trails:trail("/users/:id", user_handler, [], #{
        get => #{
            parameters => [#{name => <<"id">>, schema => user_id}],
            responses => #{<<"200">> => #{content => #{<<"application/json">> => #{schema => user}}}}
        }
    })].
```

**Output:**
```erlang
Trails = [ #{
    path => <<"/users/:id">>,
    handler => user_handler,
    metadata => #{get => #{
        parameters => [#{name => <<"id">>, schema => user_id}],  % Atom!
        responses => #{<<"200">> => #{content => #{<<"application/json">> => #{schema => user}}}}  % Atom!
    }}
}]

Types = [{user_id, {type, _, binary, []}}, {user, {type, _, map, [...]}}]
```

---

### 2. Expansion Phase

**Input:** Trails with type references (atoms)

**Process:**
- Generate `operationId` (e.g., `getUsersById`)
- Expand `schema => user_id` → `schema => #{<<"$ref">> => <<"#/components/schemas/UserId">>}`
- Expand `schema => {array, user}` → array schema with `$ref` items

**Output:**
```erlang
ExpandedTrails = [ #{
    path => <<"/users/:id">>,
    handler => user_handler,
    metadata => #{get => #{
        operationId => <<"getUsersById">>,  % Generated!
        parameters => [#{
            name => <<"id">>,
            schema => #{<<"$ref">> => <<"#/components/schemas/UserId">>}  % Expanded!
        }],
        responses => #{<<"200">> => #{
            content => #{<<"application/json">> => #{
                schema => #{<<"$ref">> => <<"#/components/schemas/User">>}  % Expanded!
            }}
        }}
    }}
}]
```

---

### 3. Schema Conversion Phase

**Input:** Type definitions (AST)

**Process:**
- Convert Erlang type AST to OpenAPI schema
- Handle primitives, maps, unions, lists, references
- Capitalize type names: `user_id` → `UserId`

**Output:**
```erlang
Schemas = #{
    <<"UserId">> => #{<<"type">> => <<"string">>},
    <<"User">> => #{
        <<"type">> => <<"object">>,
        <<"required">> => [<<"id">>, <<"name">>],
        <<"properties">> => #{
            <<"id">> => #{<<"$ref">> => <<"#/components/schemas/UserId">>},
            <<"name">> => #{<<"type">> => <<"string">>}
        }
    }
}
```

---

### 4. Building Phase

**Input:** Expanded trails + schemas

**Process:**
- Build OpenAPI document structure
- Convert paths: `:id` → `{id}`
- Assemble paths, components, info sections

**Output:** Complete OpenAPI 3.0.x document

---

## Type System

### Erlang → OpenAPI Mapping

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

### Type Reference Resolution

1. **In Metadata:** `schema => user_id` (atom)
2. **Expanded:** `schema => #{<<"$ref">> => <<"#/components/schemas/UserId">>}`
3. **Resolved:** Schema fetched from `components/schemas/UserId`

### Circular References

Handled by tracking visited types and using `$ref` to break cycles:

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

---

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

### Our Implementation Ensures

- ✅ All schemas use `$ref: '#/components/schemas/TypeName'`
- ✅ Parameters have `schema` field (not direct `type`)
- ✅ Responses have `content` with media type map
- ✅ RequestBody has `content` with media type map
- ✅ Unique `operationId` for each operation
- ✅ Path parameters: `:id` → `{id}`
- ✅ Response keys as strings

---

## Testing Strategy

### Unit Tests (22 tests)
- **Parser**: Extract trails, types, metadata
- **Expander**: OperationId generation, type expansion
- **Converter**: Type-to-schema conversions
- **Builder**: Document assembly

### Integration Tests (2 tests)
- End-to-end flow with real handler files
- Verify complete OpenAPI document generation

### Test Fixtures
- `simple_handler.erl` - Basic example
- `handler_with_types.erl` - Type references
- `comprehensive_handler.erl` - Full features
- `trails_simple_handler.erl` - Original example

---

## Trails Metadata Conversion

### Overview

The plugin handles metadata conversion in two distinct contexts:

1. **Code-to-Doc Generation (Plugin Runtime)**: Converts type atoms to OpenAPI $ref paths and schemas
2. **Production Runtime (Application Runtime)**: Metadata remains with type atoms for runtime validation

### Code-to-Doc Generation Flow

**Step 1: Handler Definition**
```erlang
trails:trail("/users/:id", handler, [], #{
    get => #{
        parameters => [#{name => <<"id">>, schema => user_id}],  % Type atom!
        responses => #{<<"200">> => #{
            content => #{<<"application/json">> => #{
                schema => user  % Type atom!
            }}
        }}
    }
})
```

**Step 2: Parser Extraction**
- Extracts metadata with type atoms unchanged
- Extracts type definitions from `-type` annotations

**Step 3: Expander Conversion**
- Converts type atoms to $ref paths:
  - `schema => user_id` → `schema => #{<<"$ref">> => <<"#/components/schemas/UserId">>}`
  - `schema => {array, user}` → `schema => #{<<"type">> => <<"array">>, <<"items">> => #{<<"$ref">> => ...}}`
- Generates unique `operationId` for each operation

**Step 4: Schema Converter**
- Converts Erlang type definitions to OpenAPI JSON Schema:
  - `-type user_id() :: binary()` → `#{<<"type">> => <<"string">>}`
  - `-type user() :: #{id := user_id(), name := binary()}` → Object schema with properties

**Step 5: Builder Assembly**
- Assembles complete OpenAPI document with:
  - Expanded $ref paths in paths section
  - Full schemas in components/schemas section
  - Proper OpenAPI 3.0.3 structure

### Production Runtime Usage

**Metadata in Handler (Unchanged)**
```erlang
trails:trail("/users/:id", handler, [], #{
    get => #{
        parameters => [#{name => <<"id">>, schema => user_id}],  % Still atom!
        responses => #{<<"200">> => #{
            content => #{<<"application/json">> => #{
                schema => user  % Still atom!
            }}
        }}
    }
})
```

**Runtime Validation Options:**

1. **Erlang Type System**: Use type atoms directly with Erlang's type checking
   ```erlang
   case validate_type(Value, user_id) of
       true -> ok;
       false -> {error, invalid_type}
   end
   ```

2. **Expand for JSON Schema Validation**: Use the same expander logic at runtime
   ```erlang
   ExpandedMeta = rebar3_openapi_expander:expand_operation(Path, Method, Meta, Types),
   Schema = get_schema_from_metadata(ExpandedMeta),
   jesse:validate(Schema, JSONValue)
   ```

3. **cowboy_swagger Integration**: If using cowboy_swagger, it expects expanded metadata format
   ```erlang
   ExpandedTrails = rebar3_openapi_expander:expand_trails(Trails, Types),
   cowboy_swagger:compile_spec(ExpandedTrails)
   ```

**Key Point**: The handler code keeps type atoms for simplicity and type safety. The plugin expands them only during documentation generation.

---

## Dependencies

- **rebar3**: Build tool
- **trails**: Route definition library
- **jsx**: JSON encoding (for JSON/YAML output)
- **yq**: CLI tool (v4+) for JSON to YAML conversion (must be installed on system)

---

## Extension Points

### Adding New Type Conversions

Extend `rebar3_openapi_schema_converter.erl`:
```erlang
convert_type_definition({type, _Line, my_custom_type, Args}, AllTypes, Visited) ->
    %% Custom conversion logic
    #{<<"custom">> => <<"schema">>};
```

### Custom OperationId Generation

Override `generate_operation_id/2` in expander or provide in metadata.

### Custom Output Formats

Extend `rebar3_openapi_prv_extract.erl` to support additional formats beyond YAML/JSON. The current implementation supports:
- JSON output (via `jsx:encode()`)
- YAML output (via JSON → `yq` conversion)

---

## Performance Considerations

- **AST Parsing**: Single pass through source file
- **Type Expansion**: O(n) where n = number of type references
- **Schema Conversion**: O(n) where n = number of type definitions
- **Circular Detection**: O(n) with visited tracking

---

## Future Enhancements

- [ ] Support for multiple handler files
- [ ] Validation of generated OpenAPI spec
- [ ] Support for external references
- [ ] Custom schema formatters
- [ ] OpenAPI 3.1.x support

