# Descriptor set and reflection bridge

Moon Proto Lab can now consume protobuf `FileDescriptorSet` data as a reflection-style schema input. This complements the `.proto` parser and makes the project useful for pipelines that already produce descriptors with `protoc --descriptor_set_out`, language runtimes, or schema registries.

## Commands

Generate the deterministic descriptor fixture used by tests:

```bash
python3 scripts/moon_proto_descriptor.py fixture \
  --hex-out generated/user_descriptor_set.hex \
  --json-out generated/user_descriptor_set.json
```

Inspect a descriptor set:

```bash
python3 scripts/moon_proto_descriptor.py inspect tests/fixtures/user_descriptor_set.hex \
  --report generated/descriptor_report.md
```

Convert a descriptor set back into the Moon Proto Lab supported proto3 subset:

```bash
python3 scripts/moon_proto_descriptor.py to-proto tests/fixtures/user_descriptor_set.hex \
  -o generated/user_from_descriptor.proto
```

Run the full descriptor verification workflow:

```bash
python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex \
  --report generated/descriptor_verify_report.md
```

Compare two descriptor sets for protobuf compatibility:

```bash
python3 scripts/moon_proto_descriptor.py compat \
  tests/fixtures/user_descriptor_set.hex \
  tests/fixtures/user_descriptor_set_reserved_v2.hex \
  --report generated/descriptor_compat_report.md
```

The verify command performs:

1. Parse `FileDescriptorSet` from `.bin`/`.pb`, `.hex`, or `.json`.
2. Reconstruct a proto3 schema subset.
3. Run Schema Doctor on the reconstructed schema.
4. Run schema inspect.
5. Generate MoonBit helper code.
6. Compile-check the generated MoonBit source.
7. Write a Markdown or HTML descriptor report.

The compat command performs:

1. Parse old and new `FileDescriptorSet` inputs.
2. Reconstruct old and new proto3 schema subsets.
3. Reuse the MoonBit schema compatibility checker.
4. Write a Markdown or HTML compatibility report with descriptor summaries, reconstructed proto previews, and compatibility diagnostics.

## Current coverage

The checked-in descriptor fixtures cover:

- `tests/fixtures/user_descriptor_set.hex`: package and syntax metadata, scalar fields, repeated fields, proto3 map-entry descriptors converted back to `map<K, V>` syntax, and oneof descriptors converted back to `oneof` syntax;
- `tests/fixtures/user_descriptor_set_reserved_v2.hex`: a compatible migration that adds `created_at = 9` and removes `phone = 6` only after reserving both the number and name;
- `tests/fixtures/user_descriptor_set_breaking.hex`: an intentionally incompatible migration that changes field `id = 1` from `uint32` to `string`.

These intentionally start with the same `examples/simple/user.proto` feature set so descriptor import is tested against existing parser/runtime/codegen paths while descriptor compatibility is tested for both PASS and FAIL paths.

## Why this matters

Descriptor sets are the interchange format behind protobuf reflection. Supporting them gives Moon Proto Lab a path to integrate with existing protobuf tools without requiring users to keep original `.proto` text around. It also creates a foundation for future work:

- schema registry imports;
- differential tests against descriptors emitted by official code generators;
- richer reflection-based debugging reports.
