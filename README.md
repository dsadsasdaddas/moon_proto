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
- provide conformance-lite fixtures for scalar, repeated, packed repeated, enum, nested, map, oneof and upstream-style wire-decode edge cases;
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
- `.proto` lexer/parser for `syntax`, `edition` declaration tolerance, dotted `package` names, `import`, top-level/message/enum `option`, real `reserved` number/name descriptors, `extensions`, `message`, `enum`, nested message/enum definitions, qualified nested type references, scalar/named fields, field/enum options, signed enum values and enum reserved ranges, enum `allow_alias` duplicate-number semantics, single-quoted/escaped string literals, empty statements, `optional`, `repeated`, `map`, `oneof`, oneof options, block comments, and ignored `service`/`rpc`/`extend` blocks;
- schema validator for field numbers, duplicate names/numbers, proto3 enum invariants, top-level conflicts, map constraints, and field/enum reserved-number/name reuse;
- schema-driven dynamic message encode/decode for scalar, repeated, packed repeated, enum, nested message, map and oneof fields;
- unknown-field skipping during decode;
- protobuf-style JSON writer/parser for scalar/repeated/map/nested/oneof dynamic messages, including enum-name schema mapping, URL-safe/unpadded bytes base64 input, `null`-as-absent parsing semantics and lowerCamelCase input/output helpers;
- MoonBit source generator for message structs, enums, descriptor registries and helper functions;
- file-based generator wrapper for `.proto` input and generated `.mbt` output;
- file-based Schema Doctor CLI for stable diagnostics on valid and invalid schemas;
- AI verification CLI that runs doctor, schema inspection, codegen, generated-code compile checks, and Markdown/HTML/JUnit XML report generation;
- old/new schema compatibility checker for detecting field, enum, package, type and reserved-contract breaking changes;
- official MoonBit protobuf differential harness manifest/report for schemas overlapping with `moonbitlang/protoc-gen-mbt`, including manifest feature coverage gates, scalar-matrix adapter coverage, source-contract, pre-generated output and installed-plugin live-generator smoke paths;
- FileDescriptorSet descriptor/reflection bridge for `.pb`/`.hex`/`.json` descriptor imports, proto reconstruction, verification reports, old/new descriptor-set compatibility reports, descriptor-registry release gates, JSON release-policy checks with rule-based severity/warning support, and file/HTTP/authenticated/profile/GitHub Contents managed-backend registry adapter publish/push/pull verification;
- Python and Go official protobuf oracle fixtures for cross-language compatibility checks, including 32-bit numeric boundary values, float/double values, special NaN/Infinity JSON values, and upstream-style wire-decode edge vectors;
- conformance-lite evidence report with Markdown/JSON/JUnit output for scalar/repeated/packed, map, oneof, numeric-boundary, float/double, special-float, wire-decode edge cases and an imported upstream-lite conformance manifest, expected-fail mutation self-checks, and coverage-gate taxonomy;
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
python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry_service.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/nested_types.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/nested_qualified.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/enum_numbers.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/enum_alias.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/string_literals.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/custom_options.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/edition_schema.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/oneof_options.proto
python3 scripts/moon_proto_lab.py inspect examples/decorated/telemetry.proto
python3 scripts/moon_proto_lab.py inspect examples/simple/user.proto
python3 scripts/moon_proto_lab.py inspect examples/decorated/enum_numbers.proto
python3 scripts/moon_proto_lab.py inspect examples/decorated/enum_alias.proto
python3 scripts/moon_proto_lab.py inspect examples/decorated/string_literals.proto
python3 scripts/moon_proto_lab.py inspect examples/decorated/custom_options.proto
python3 scripts/moon_proto_lab.py inspect examples/decorated/edition_schema.proto
python3 scripts/moon_proto_lab.py inspect examples/decorated/oneof_options.proto
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md --junit-out generated/compat_report.xml
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md --junit-out generated/verify_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/enum_numbers.proto --report generated/verify_enum_numbers_report.md --junit-out generated/verify_enum_numbers_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/enum_alias.proto --report generated/verify_enum_alias_report.md --junit-out generated/verify_enum_alias_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/string_literals.proto --report generated/verify_string_literals_report.md --junit-out generated/verify_string_literals_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/nested_qualified.proto --report generated/verify_nested_qualified_report.md --junit-out generated/verify_nested_qualified_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/custom_options.proto --report generated/verify_custom_options_report.md --junit-out generated/verify_custom_options_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/edition_schema.proto --report generated/verify_edition_schema_report.md --junit-out generated/verify_edition_schema_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/oneof_options.proto --report generated/verify_oneof_options_report.md --junit-out generated/verify_oneof_options_report.xml
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.html
python3 scripts/moon_proto_official_diff.py --report generated/official_diff_report.md --junit-out generated/official_diff_report.xml
python3 scripts/moon_proto_official_diff.py --official-generated-dir tests/differential/official_generated_fixture --report generated/official_generated_diff_report.md --junit-out generated/official_generated_diff_report.xml
python3 scripts/moon_proto_official_diff.py --run-official-generator --official-plugin-bin protoc-gen-mbt --protoc-bin protoc --report generated/official_installed_plugin_diff_report.md --junit-out generated/official_installed_plugin_diff_report.xml
python3 scripts/moon_proto_conformance.py --report generated/conformance_lite_report.md --json-out generated/conformance_lite.json --junit-out generated/conformance_lite.xml
git clone --depth 1 https://github.com/moonbitlang/protoc-gen-mbt /tmp/protoc-gen-mbt
python3 scripts/moon_proto_official_diff.py --official-repo /tmp/protoc-gen-mbt --require-official --report generated/official_source_diff_report.md --junit-out generated/official_source_diff_report.xml
python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md --junit-out generated/descriptor_verify_report.xml
python3 scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md --junit-out generated/descriptor_compat_report.xml
python3 scripts/moon_proto_descriptor.py registry tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --name demo-user --report generated/descriptor_registry_report.md --json-out generated/descriptor_registry.json --policy tests/fixtures/descriptor_registry_policy.json --junit-out generated/descriptor_registry_report.xml
python3 scripts/moon_proto_descriptor.py policy generated/descriptor_registry.json tests/fixtures/descriptor_registry_policy.json --report generated/descriptor_policy_report.md --json-out generated/descriptor_policy.json --junit-out generated/descriptor_policy_report.xml
python3 scripts/moon_proto_descriptor.py publish generated/descriptor_registry.json --store generated/schema_registry_store --base-dir . --report generated/descriptor_registry_publish_report.md --json-out generated/descriptor_registry_published.json --junit-out generated/descriptor_registry_publish_report.xml
python3 scripts/moon_proto_descriptor.py pull generated/schema_registry_store/registries/demo-user.json --output-dir generated/schema_registry_pull --report generated/descriptor_registry_pull_report.md --json-out generated/descriptor_registry_pulled.json --junit-out generated/descriptor_registry_pull_report.xml
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
python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry_service.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/nested_types.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/nested_qualified.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/enum_numbers.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/enum_alias.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/string_literals.proto
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md --junit-out generated/compat_report.xml
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md --junit-out generated/verify_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/enum_numbers.proto --report generated/verify_enum_numbers_report.md --junit-out generated/verify_enum_numbers_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/enum_alias.proto --report generated/verify_enum_alias_report.md --junit-out generated/verify_enum_alias_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/string_literals.proto --report generated/verify_string_literals_report.md --junit-out generated/verify_string_literals_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/nested_qualified.proto --report generated/verify_nested_qualified_report.md --junit-out generated/verify_nested_qualified_report.xml
python3 scripts/moon_proto_official_diff.py --report generated/official_diff_report.md --junit-out generated/official_diff_report.xml
python3 scripts/moon_proto_official_diff.py --official-generated-dir tests/differential/official_generated_fixture --report generated/official_generated_diff_report.md --junit-out generated/official_generated_diff_report.xml
python3 scripts/moon_proto_official_diff.py --run-official-generator --official-plugin-bin protoc-gen-mbt --protoc-bin protoc --report generated/official_installed_plugin_diff_report.md --junit-out generated/official_installed_plugin_diff_report.xml
python3 scripts/moon_proto_conformance.py --report generated/conformance_lite_report.md --json-out generated/conformance_lite.json --junit-out generated/conformance_lite.xml
git clone --depth 1 https://github.com/moonbitlang/protoc-gen-mbt /tmp/protoc-gen-mbt
python3 scripts/moon_proto_official_diff.py --official-repo /tmp/protoc-gen-mbt --require-official --report generated/official_source_diff_report.md --junit-out generated/official_source_diff_report.xml
python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md --junit-out generated/descriptor_verify_report.xml
python3 scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md --junit-out generated/descriptor_compat_report.xml
python3 scripts/moon_proto_descriptor.py registry tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --name demo-user --report generated/descriptor_registry_report.md --json-out generated/descriptor_registry.json --policy tests/fixtures/descriptor_registry_policy.json --junit-out generated/descriptor_registry_report.xml
python3 scripts/moon_proto_descriptor.py policy generated/descriptor_registry.json tests/fixtures/descriptor_registry_policy.json --report generated/descriptor_policy_report.md --json-out generated/descriptor_policy.json --junit-out generated/descriptor_policy_report.xml
python3 scripts/moon_proto_descriptor.py publish generated/descriptor_registry.json --store generated/schema_registry_store --base-dir . --report generated/descriptor_registry_publish_report.md --json-out generated/descriptor_registry_published.json --junit-out generated/descriptor_registry_publish_report.xml
python3 scripts/moon_proto_descriptor.py pull generated/schema_registry_store/registries/demo-user.json --output-dir generated/schema_registry_pull --report generated/descriptor_registry_pull_report.md --json-out generated/descriptor_registry_pulled.json --junit-out generated/descriptor_registry_pull_report.xml
tests/codegen/compile_generated.sh
```

## Documentation

- [Ecosystem positioning](docs/ECOSYSTEM_POSITIONING.md)
- [Schema Doctor and verify reports](docs/SCHEMA_DOCTOR.md)
- [Official differential harness](docs/OFFICIAL_DIFFERENTIAL.md)
- [Descriptor set bridge](docs/DESCRIPTOR_SET.md)
- [Descriptor registry workflow](docs/SCHEMA_REGISTRY.md)
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
- M19: larger conformance-lite corpus and float/double/special-float oracle fixtures. Done.
- M20: import/option/reserved/extensions/field-option parser tolerance for real-world `.proto` files. Done.
- M21: reserved number/name validation and compatibility contracts. Done.
- M22: official MoonBit protobuf differential harness manifest and report. Done.
- M23: CI-enforced official source contract check against `moonbitlang/protoc-gen-mbt`. Done.
- M24: official generated-output differential contract for pre-generated or installed-generator output. Done.
- M25: descriptor set / reflection import path with descriptor reports. Done.
- M26: descriptor-set compatibility checks with reserved-field migration reports. Done.
- M27: descriptor registry imports, version indexes and adjacent compatibility release gates. Done.
- M28: JSON release-policy gate for descriptor registry manifests. Done.
- M29: JUnit XML outputs for CI/test dashboards. Done.
- M30a: richer descriptor registry release-policy DSL with warning severity and breaking-change budgets. Done.
- M30b: file/HTTP descriptor registry adapter publish/pull with artifact digest verification. Done.
- M31: authenticated HTTP registry pull with bearer-token/header support. Done.
- M32: authenticated HTTP registry push with PUT upload and digest verification. Done.
- M33: hosted registry profiles for reusable base URL, registry, token and header configuration. Done.
- M34: managed hosted registry backend integration via GitHub Contents API profiles. Done.
- M35: conformance-lite evidence report with Markdown/JSON/JUnit output. Done.
- M36: conformance-lite expected-fail mutation self-checks for corrupted fixtures. Done.
- M37: conformance-lite semantic-axis coverage gates in Markdown/JSON/JUnit reports. Done.
- M38: installed official protoc-gen-mbt plugin live-generator smoke path. Done.
- M39: upstream-style wire-decode conformance vectors for duplicate singular last-one-wins, unknown-field skipping, and mixed packed/unpacked repeated input. Done.
- M40: imported upstream-lite conformance manifest with 11 protobuf-input/JSON-output acceptance cases and CI coverage gates. Done.
- M41: official differential scalar-matrix adapter case with manifest feature coverage gate. Done.
- M42: real-world service/rpc block and block-comment parser tolerance with verify-report coverage. Done.
- M43: nested message/enum parser lifting with generated-code verify coverage. Done.
- M44: signed enum values, signed enum reserved ranges and empty-statement parser tolerance with generated-code verify coverage. Done.
- M45: enum `allow_alias` parser, validation and generated-code verify coverage. Done.
- M46: single-quoted and escaped `.proto` string literal parser tolerance with generated-code verify coverage. Done.
- M47: qualified nested message/enum type reference resolution with generated-code verify coverage. Done.
- M48: top-level `extend` custom-option block parser tolerance with generated-code verify coverage. Done.
- M49: protobuf `edition = "2023"` declaration parser tolerance with generated-code verify coverage. Done.
- M50: oneof option statement parser tolerance with generated-code verify coverage. Done.
- M51: protobuf JSON `null` parsing as absent fields, with duplicate-field and repeated-element guards. Done.
- M52: protobuf JSON lowerCamelCase field-name alias parsing with canonical duplicate detection. Done.
- M53: protobuf JSON lowerCamelCase output helpers, including generated runtime helper coverage. Done.
- M54: protobuf JSON bytes parser accepts URL-safe base64 and omitted final padding. Done.
- M55: protobuf JSON enum-name schema mapping with generated enum descriptor registry coverage. Done.

## License

MIT.
