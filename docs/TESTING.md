# Testing strategy

moon_proto is designed for verification-first development.

Current tests cover:

- protobuf varint golden vectors: `0`, `1`, `127`, `128`, `300`;
- zig-zag golden vectors for signed integer mapping;
- key packing/parsing: `(field_number << 3) | wire_type`;
- little-endian fixed32/fixed64 encoding;
- length-delimited string encoding;
- a hand-checked `User` message byte stream;
- a small proto3 lexer/parser smoke test;
- schema-driven dynamic message encode golden bytes;
- schema-driven dynamic message decode roundtrip;
- unknown-field skipping;
- invalid dynamic value rejection;
- MoonBit struct/descriptor codegen snapshot;
- proto3 packed repeated numeric encode/decode;
- unpacked repeated numeric decode compatibility;
- JSON string escaping and bytes base64 vectors;
- protobuf-style JSON output for descriptor-driven dynamic messages;
- JSON mapping rejection of unknown or mismatched fields;
- JSON parser roundtrip and duplicate/invalid value rejection;
- top-level enum parser and MoonBit codegen snapshots;
- enum field binary and JSON roundtrip;
- schema validator positive and negative cases;
- nested message binary and JSON roundtrip through descriptor registries;
- proto3 map parser/codegen snapshot, schema validation, binary roundtrip and JSON object mapping;
- codegen runtime helper snapshots, CLI smoke generation, and generated-code compile checks;
- deterministic property-style roundtrip corpora for varint, zig-zag, dynamic message binary and JSON;
- official Python `google.protobuf` and Go `google.golang.org/protobuf` oracle fixtures for full scalar/repeated and map messages.

Run the full matrix:

```bash
python3 tests/oracle/python_protobuf_oracle.py
(cd tests/oracle && go run .)
moon check
moon build
moon test
moon test --target all
moon run cmd/main -- gen --example
tests/codegen/compile_generated.sh
```

Python/Go oracle fixtures live in `tests/fixtures/`. The Python script can
regenerate the checked-in binary/hex/JSON fixtures:

```bash
python3 tests/oracle/python_protobuf_oracle.py --write
```

Planned next verification:

- add file-based CLI tests once file IO is available.
