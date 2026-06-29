# moon_proto

`moon_proto` is a **proto3 Protocol Buffers runtime, parser, and codegen toolkit for MoonBit**.

The project targets the MoonBit open-source ecosystem contest as basic software infrastructure for cloud, edge, WebAssembly, RPC-like data exchange, and multi-language interoperability.

## Stage-1 scope

This first milestone intentionally keeps the scope small and testable:

- protobuf wire type model;
- UInt64 varint encode/decode;
- zig-zag signed integer mapping;
- fixed32/fixed64 little-endian helpers;
- length-delimited bytes/string helpers;
- field-level helpers for `uint64`, `bool`, `sint64`, `string`, `bytes`;
- proto3 schema model;
- a small `.proto` lexer/parser for `syntax`, `package`, `message`, scalar fields, `optional`, and `repeated`;
- golden tests for all implemented pieces.

## Example

```moonbit
let user = concat_bytes([
  encode_uint64_field(1, 150UL),
  encode_string_field(2, "Alice"),
  encode_bool_field(3, true),
])
// b"\x08\x96\x01\x12\x05Alice\x18\x01"
```

Parse a small schema:

```moonbit
let src = #|syntax = "proto3";
  #|package demo;
  #|message User {
  #|  uint32 id = 1;
  #|  string name = 2;
  #|  repeated string tags = 3;
  #|}
let ast = parse_proto(src)
```

## Verify

```bash
moon check
moon build
moon test
moon test --target all
```

## Roadmap

- M1: wire runtime + schema parser + tests. ✅
- M2: generated MoonBit structs and encode/decode for scalar fields.
- M3: repeated fields, packed repeated encoding, enums, nested messages.
- M4: JSON mapping and Python/Go oracle cross-language compatibility tests.
- M5: CLI `moon_proto gen schema.proto -o generated/` and examples.

## License

MIT.
