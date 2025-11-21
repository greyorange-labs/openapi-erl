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

For detailed information on how to write handler modules with type definitions and trails, see the [Handler Code Documentation](#handler-code-documentation).

### Generate OpenAPI Documentation



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
- `--app` (required): Application name for metadata

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

## Examples

See `test/fixtures/` for handler examples:
- `simple_handler.erl` - Basic example
- `handler_with_types.erl` - Type references example
- `comprehensive_handler.erl` - Full-featured example with all HTTP methods

For more detailed handler documentation, see the [Handler Code Documentation](https://github.com/greyorange-labs/PLACEHOLDER_HANDLER_DOCS).

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
