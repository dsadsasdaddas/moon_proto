# Testing strategy

moon_proto is designed for verification-first development.

Stage 1 tests cover:

- protobuf varint golden vectors: `0`, `1`, `127`, `128`, `300`;
- zig-zag golden vectors for signed integer mapping;
- key packing/parsing: `(field_number << 3) | wire_type`;
- little-endian fixed32/fixed64 encoding;
- length-delimited string encoding;
- a hand-checked `User` message byte stream;
- a small proto3 lexer/parser smoke test.

Planned Stage 2 verification:

- generate Python protobuf oracle bytes in `tests/fixtures/*.bin`;
- verify MoonBit decode against Python encode;
- verify Python decode against MoonBit encode;
- add property-style roundtrip tests for scalar and repeated fields.
