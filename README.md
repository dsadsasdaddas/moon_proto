# Moon Proto Lab

**Moon Proto Lab** is a MoonBit protobuf ecosystem lab for **dynamic schema parsing, compatibility testing, JSON mapping, code generation experiments, and AI-generated schema/code verification**.

The repository name remains `moon_proto`, but the project is now deliberately positioned as an ecosystem companion instead of a replacement for the existing MoonBit protobuf implementation.

## Repository links

- GitHub: https://github.com/dsadsasdaddas/moon_proto
- Gitlink: https://gitlink.org.cn/wangyue111/moon_proto

## Ecosystem positioning

Before submission we checked the MoonBit package ecosystem and found existing protobuf-related packages, including `moonbitlang/protobuf` (https://mooncakes.io/docs/moonbitlang/protobuf) and `moonbitlang/protoc-gen-mbt` (https://github.com/moonbitlang/protoc-gen-mbt).

Moon Proto Lab therefore does **not** claim to replace the official/runtime-oriented protobuf stack. Its independent value is the verification and tooling layer around protobuf usage in MoonBit:

- parse and validate `.proto` schemas before code generation;
- provide a dynamic descriptor/message runtime for debugging and schema experiments;
- check protobuf binary and JSON mapping behavior against Python/Go official protobuf oracles;
- provide conformance-lite fixtures for scalar, repeated, packed repeated, enum, nested, map and oneof cases;
- compile-check generated MoonBit source so AI-generated schema/code changes are not only syntactically plausible but actually buildable;
- keep the door open for future adapters to official MoonBit protobuf packages.

This makes the project fit the contest theme of improving MoonBit open-source infrastructure and addressing the problem that AI-generated code is hard to verify and maintain over time.

## Current scope

The project has a small but end-to-end verifiable protobuf laboratory pipeline:

- protobuf wire type model;
- key packing/parsing;
- UInt64 varint encode/decode;
- zig-zag signed integer mapping;
- fixed32/fixed64 little-endian helpers;
- length-delimited bytes/string helpers;
- field-level helpers for `uint64`, `bool`, `sint64`, `string`, `bytes`;
- proto3 schema model for messages, fields, labels, scalar types, enums, named messages, maps and oneof groups;
- `.proto` lexer/parser for `syntax`, `package`, `message`, `enum`, scalar fields, `optional`, `repeated`, `map`, and `oneof`;
- schema validator for field numbers, duplicate names/numbers, proto3 enum invariants, top-level conflicts and map constraints;
- schema-driven dynamic message encode/decode for scalar, repeated, packed repeated, enum, nested message, map and oneof fields;
- unknown-field skipping during decode;
- protobuf-style JSON writer/parser for scalar/repeated/map/nested/oneof dynamic messages;
- MoonBit source generator for message structs, enums, descriptor registries and helper functions;
- file-based generator wrapper for `.proto` input and generated `.mbt` output;
- file-based Schema Doctor CLI for stable diagnostics on valid and invalid schemas;
- AI verification CLI that runs doctor, schema inspection, codegen, generated-code compile checks, and Markdown/HTML report generation;
- old/new schema compatibility checker for detecting field, enum, package and type breaking changes;
- Python and Go official protobuf oracle fixtures for cross-language compatibility checks, including 32-bit numeric boundary values, float/double values, and special NaN/Infinity JSON values;
- deterministic property-style roundtrip corpora for binary and JSON paths;
- generated-code compile checks and GitHub Actions CI.

## Example

Encode a small hand-written message:

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

Run the bundled CLI smoke generator and schema tools:

```bash
moon run cmd/main -- gen --example
moon run cmd/main -- gen --schema 'syntax = "proto3"; message User { uint64 id = 1; }'
moon run cmd/main -- doctor --schema 'syntax = "proto3"; message User { uint64 id = 1; }'
moon run cmd/main -- inspect --schema 'syntax = "proto3"; message User { uint64 id = 1; }'
```

Generate from a `.proto` file into a project directory:

```bash
python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/
```

Run the file-based Schema Doctor and AI verification report workflow:

```bash
python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto
python3 scripts/moon_proto_lab.py inspect examples/simple/user.proto
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.html
```

Convert a dynamic message to protobuf-style JSON:

```moonbit
match message_to_json(desc, msg) {
  JsonOk(text) => println(text)
  JsonErr(_) => println("message cannot be rendered as JSON")
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
python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md
tests/codegen/compile_generated.sh
```

## Documentation

- [Ecosystem positioning](docs/ECOSYSTEM_POSITIONING.md)
- [Schema Doctor and verify reports](docs/SCHEMA_DOCTOR.md)
- [Testing strategy](docs/TESTING.md)
- [Development report](docs/DEVELOPMENT_REPORT.md)
- [Submission checklist](docs/SUBMISSION_CHECKLIST.md)
- Proposal PDF: `output/pdf/MoonProto_王越的战队_项目申报书.pdf`

## Roadmap

- M1: wire runtime + schema parser + tests. Done.
- M2: schema-driven dynamic encode/decode for scalar and repeated fields. Done.
- M3: generated MoonBit structs and descriptor functions. Done.
- M4: packed repeated numeric scalar encoding/decoding. Done.
- M5: protobuf-style JSON writer/parser for scalar/repeated messages. Done.
- M6: top-level enum parser and codegen. Done.
- M7: enum field runtime/JSON support. Done.
- M8: Python/Go protobuf oracle compatibility fixtures. Done.
- M9: schema validator for AI/codegen safety. Done.
- M10: nested message dynamic runtime/JSON support. Done.
- M11: CLI smoke generator and runtime helper codegen. Done.
- M12: generated-code compile check. Done.
- M13: proto3 maps. Done.
- M14: oneof groups. Done.
- M15: file-based CLI wrapper `moon_proto gen schema.proto -o generated/`. Done.
- M16: Schema Doctor CLI for stable diagnostics. Done.
- M17: AI verify command with generated-code compile check and Markdown/HTML reports. Done.
- M18: old/new schema compatibility checking with Markdown/HTML reports. Done.
- M19: adapters and differential tests around existing MoonBit protobuf packages. Planned.
- M20: larger conformance-lite corpus and import/option/reserved schema support. Planned.

## License

MIT.
