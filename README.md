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
- descriptor-registry based nested message binary and JSON roundtrip;
- repeated field emission and accumulation;
- proto3 map parser, dynamic binary runtime, JSON object mapping and validation;
- proto3 oneof parser, conflict validation and last-one-wins decode semantics;
- proto3 packed repeated encoding/decoding for numeric scalar fields;
- unknown-field skipping during decode;
- protobuf-style JSON writer/parser for scalar/repeated/map/oneof dynamic messages;
- proto3 schema model for messages, fields and top-level enums;
- enum field resolution with protobuf varint runtime support;
- a small `.proto` lexer/parser for `syntax`, `package`, `message`, `enum`, scalar fields, `optional`, `repeated`, `map`, and `oneof`;
- MoonBit source generator for message structs, enums and descriptor functions;
- file-based generator wrapper for `.proto` input and generated `.mbt` output;
- schema validator for field numbers, duplicates and proto3 enum invariants;
- official Python and Go protobuf oracle fixtures for cross-language scalar/repeated/map/oneof compatibility;
- deterministic property-style roundtrip corpora for binary and JSON paths;
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

Run the bundled CLI smoke generator:

```bash
moon run cmd/main -- gen --example
moon run cmd/main -- gen --schema 'syntax = "proto3"; message User { uint64 id = 1; }'
```

Generate from a `.proto` file into a project directory:

```bash
python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/
```

Convert a dynamic message to protobuf-style JSON:

```moonbit
match message_to_json(desc, msg) {
  JsonOk(text) => println(text)
  JsonErr(_) => println("message cannot be rendered as JSON")
}
```

Parse protobuf-style JSON back into a dynamic message:

```moonbit
match json_to_message(desc, "{\"id\":\"150\",\"name\":\"Alice\"}") {
  JsonDecodeOk(msg) => println("ok")
  JsonDecodeErr(_) => println("invalid JSON")
}
```

Validate parsed schemas before codegen:

```moonbit
match parse_proto(src) {
  ProtoOk(file) => assert_true(schema_is_valid(file))
  ProtoErr(_) => println("invalid schema syntax")
}
```

## Verify

```bash
python3 tests/oracle/python_protobuf_oracle.py
(cd tests/oracle && go run .)
moon check
moon build
moon test
moon test --target all
moon run cmd/main -- gen --example
python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/
tests/codegen/compile_generated.sh
```

## Documentation

- [Testing strategy](docs/TESTING.md)
- [Development report](docs/DEVELOPMENT_REPORT.md)
- [Submission checklist](docs/SUBMISSION_CHECKLIST.md)
- Proposal PDF: `output/pdf/MoonProto_王越的战队_项目申报书.pdf`

## Roadmap

- M1: wire runtime + schema parser + tests. ✅
- M2: schema-driven dynamic encode/decode for scalar fields and repeated fields. ✅
- M3: generated MoonBit structs and descriptor functions. ✅
- M4: packed repeated numeric scalar encoding/decoding. ✅
- M5: protobuf-style JSON writer/parser for scalar/repeated messages. ✅
- M6: top-level enum parser and codegen. ✅
- M7: enum field runtime/JSON support. ✅
- M8: Python/Go protobuf oracle compatibility fixtures. ✅
- M9: schema validator for AI/codegen safety. ✅
- M10: nested message dynamic runtime/JSON support. ✅
- M11: CLI smoke generator and runtime helper codegen. ✅
- M12: generated-code compile check. ✅
- M13: proto3 maps. ✅
- M14: oneof groups. ✅
- M15: file-based CLI wrapper `moon_proto gen schema.proto -o generated/`. ✅

## License

MIT.
