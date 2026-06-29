# moon_proto

`moon_proto` is a **proto3 Protocol Buffers runtime, parser, and codegen toolkit for MoonBit**.

The project targets the MoonBit open-source ecosystem contest as basic software infrastructure for cloud, edge, WebAssembly, RPC-like data exchange, and multi-language interoperability.

## Repository links

- GitHub: https://github.com/dsadsasdaddas/moon_proto
- Gitlink: https://gitlink.org.cn/wangyue111/moon_proto

## Current scope

The project keeps the early milestones small and testable while moving toward
a complete proto3 toolkit:

- protobuf wire type model;
- UInt64 varint encode/decode;
- zig-zag signed integer mapping;
- fixed32/fixed64 little-endian helpers;
- length-delimited bytes/string helpers;
- field-level helpers for `uint64`, `bool`, `sint64`, `string`, `bytes`;
- schema-driven dynamic message encode/decode for scalar fields;
- repeated field emission and accumulation;
- proto3 packed repeated encoding/decoding for numeric scalar fields;
- unknown-field skipping during decode;
- protobuf-style JSON writer for scalar/repeated dynamic messages;
- proto3 schema model for messages, fields and top-level enums;
- a small `.proto` lexer/parser for `syntax`, `package`, `message`, `enum`, scalar fields, `optional`, and `repeated`;
- MoonBit source generator for message structs, enums and descriptor functions;
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

Encode/decode through a descriptor:

```moonbit
let desc = MessageDescriptor::{
  name : "User",
  fields : [
    FieldDescriptor::{ name : "id", typ : UInt64Type, number : 1, label : Singular },
    FieldDescriptor::{ name : "name", typ : StringType, number : 2, label : Singular },
  ],
}
let msg = message_value([
  message_field("id", UInt64Value(150UL)),
  message_field("name", StringValue("Alice")),
])
let encoded = encode_message(desc, msg)
```

Generate MoonBit source from a parsed proto:

```moonbit
match parse_proto(src) {
  ProtoOk(file) => println(generate_moonbit_source(file))
  ProtoErr(_) => println("invalid schema")
}
```

Convert a dynamic message to protobuf-style JSON:

```moonbit
match message_to_json(desc, msg) {
  JsonOk(text) => println(text)
  JsonErr(_) => println("message cannot be rendered as JSON")
}
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
- M2: schema-driven dynamic encode/decode for scalar fields and repeated fields. ✅
- M3: generated MoonBit structs and descriptor functions. ✅
- M4: packed repeated numeric scalar encoding/decoding. ✅
- M5: protobuf-style JSON writer for scalar/repeated messages. ✅
- M6: top-level enum parser and codegen. ✅
- M7: nested messages, oneof, maps.
- M8: JSON parser and Python/Go oracle cross-language compatibility tests.
- M9: CLI `moon_proto gen schema.proto -o generated/` and examples.

## License

MIT.
