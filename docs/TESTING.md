# Testing strategy

Moon Proto Lab is designed for verification-first development. Its main value is not only that it can encode/decode a protobuf subset, but that every implemented behavior is backed by reproducible tests, golden fixtures, cross-language oracles, and generated-code compile checks.

Current tests cover:

- protobuf varint golden vectors: `0`, `1`, `127`, `128`, `300`;
- zig-zag golden vectors for signed integer mapping;
- key packing/parsing: `(field_number << 3) | wire_type`;
- little-endian fixed32/fixed64 encoding;
- length-delimited string encoding;
- a hand-checked `User` message byte stream;
- a small proto3 lexer/parser smoke test;
- parser tolerance for edition declarations, dotted package/type names, import, option, reserved/extensions, field/enum options, nested message/enum definitions, qualified nested type references, oneof option statements, signed enum values/reserved ranges, enum allow_alias duplicate-number semantics, single-quoted/escaped string literals, empty statements, block comments, and ignored service/rpc/extend blocks;
- reserved number/name descriptors, Schema Doctor reserved-reuse rejection, and compatibility behavior for removed-but-reserved fields;
- schema-driven dynamic message encode golden bytes;
- schema-driven dynamic message decode roundtrip;
- unknown-field skipping;
- invalid dynamic value rejection;
- MoonBit struct/descriptor codegen snapshot;
- proto3 packed repeated numeric encode/decode;
- uint32/int32/sint32/fixed32/sfixed32 boundary encoding, JSON parsing and overflow rejection;
- float/double binary encoding, decoding and protobuf-style JSON roundtrip;
- float/double protobuf JSON special strings: `"NaN"`, `"Infinity"`, `"-Infinity"`;
- unpacked repeated numeric decode compatibility;
- upstream-style wire decode vector covering duplicate singular last-one-wins, unknown field skipping, and mixed packed/unpacked repeated numeric input;
- JSON string escaping and bytes base64 vectors;
- protobuf-style JSON output for descriptor-driven dynamic messages;
- JSON mapping rejection of unknown or mismatched fields;
- JSON parser roundtrip, `null`-as-absent parsing, duplicate-key rejection and repeated-element null rejection;
- top-level enum parser and MoonBit codegen snapshots;
- enum field binary and JSON roundtrip;
- schema validator positive and negative cases;
- nested message binary and JSON roundtrip through descriptor registries;
- proto3 map parser/codegen snapshot, schema validation, binary roundtrip and JSON object mapping;
- proto3 oneof parser/codegen snapshot, encode-time conflict rejection, binary last-one-wins decode and JSON conflict rejection;
- codegen runtime helper snapshots, inline/file-based CLI smoke generation, Schema Doctor diagnostics, compatibility checks, verify report and JUnit XML generation, official differential/source/generated-output/installed-plugin live-generator report, manifest feature coverage gate and JUnit XML generation, descriptor verify/compat/registry/policy report and JUnit XML generation, registry adapter publish/push/pull/authenticated HTTP/profile/managed GitHub Contents backend report and JUnit XML generation, CI official source-contract checks, and generated-code compile checks;
- deterministic property-style roundtrip corpora for varint, zig-zag, dynamic message binary and JSON;
- official Python `google.protobuf` and Go `google.golang.org/protobuf` oracle fixtures for full scalar/repeated, map, oneof, 32-bit numeric boundary, float/double, special float and wire-decode edge messages;
- conformance-lite Markdown/JSON/JUnit evidence report over the same oracle-backed fixture matrix, including upstream-style wire-decode edge vectors, an imported 11-case upstream-lite manifest, expected-fail mutation self-checks for corrupted fixtures and missing artifacts plus semantic-axis coverage gates.

Run the full matrix:

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
python3 scripts/moon_proto_lab.py doctor examples/decorated/custom_options.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/edition_schema.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/oneof_options.proto
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md --junit-out generated/compat_report.xml
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md --junit-out generated/verify_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/enum_numbers.proto --report generated/verify_enum_numbers_report.md --junit-out generated/verify_enum_numbers_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/enum_alias.proto --report generated/verify_enum_alias_report.md --junit-out generated/verify_enum_alias_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/string_literals.proto --report generated/verify_string_literals_report.md --junit-out generated/verify_string_literals_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/nested_qualified.proto --report generated/verify_nested_qualified_report.md --junit-out generated/verify_nested_qualified_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/custom_options.proto --report generated/verify_custom_options_report.md --junit-out generated/verify_custom_options_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/edition_schema.proto --report generated/verify_edition_schema_report.md --junit-out generated/verify_edition_schema_report.xml
python3 scripts/moon_proto_lab.py verify examples/decorated/oneof_options.proto --report generated/verify_oneof_options_report.md --junit-out generated/verify_oneof_options_report.xml
python3 scripts/moon_proto_official_diff.py --report generated/official_diff_report.md --junit-out generated/official_diff_report.xml
python3 scripts/moon_proto_official_diff.py --official-generated-dir tests/differential/official_generated_fixture --report generated/official_generated_diff_report.md --junit-out generated/official_generated_diff_report.xml
python3 scripts/moon_proto_official_diff.py --run-official-generator --official-plugin-bin protoc-gen-mbt --protoc-bin protoc --report generated/official_installed_plugin_diff_report.md --junit-out generated/official_installed_plugin_diff_report.xml
python3 scripts/moon_proto_conformance.py --report generated/conformance_lite_report.md --json-out generated/conformance_lite.json --junit-out generated/conformance_lite.xml
python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md --junit-out generated/descriptor_verify_report.xml
python3 scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md --junit-out generated/descriptor_compat_report.xml
python3 scripts/moon_proto_descriptor.py registry tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --name demo-user --report generated/descriptor_registry_report.md --json-out generated/descriptor_registry.json --policy tests/fixtures/descriptor_registry_policy.json --junit-out generated/descriptor_registry_report.xml
python3 scripts/moon_proto_descriptor.py policy generated/descriptor_registry.json tests/fixtures/descriptor_registry_policy.json --report generated/descriptor_policy_report.md --json-out generated/descriptor_policy.json --junit-out generated/descriptor_policy_report.xml
python3 scripts/moon_proto_descriptor.py publish generated/descriptor_registry.json --store generated/schema_registry_store --base-dir . --report generated/descriptor_registry_publish_report.md --json-out generated/descriptor_registry_published.json --junit-out generated/descriptor_registry_publish_report.xml
python3 scripts/moon_proto_descriptor.py pull generated/schema_registry_store/registries/demo-user.json --output-dir generated/schema_registry_pull --report generated/descriptor_registry_pull_report.md --json-out generated/descriptor_registry_pulled.json --junit-out generated/descriptor_registry_pull_report.xml
tests/codegen/compile_generated.sh
```

Python/Go oracle fixtures live in `tests/fixtures/`. The Python script can regenerate the checked-in binary/hex/JSON fixtures:

```bash
python3 tests/oracle/python_protobuf_oracle.py --write
```

## Why these tests matter

The project is positioned as a protobuf ecosystem verification lab for MoonBit. The tests are therefore part of the product:

- golden bytes detect binary compatibility regressions;
- JSON roundtrip tests detect mapping drift;
- Python/Go oracles make behavior comparable with mature ecosystems;
- negative tests reject invalid AI-generated schemas or dynamic messages;
- generated-code compile checks ensure generated MoonBit source actually builds;
- verify reports make the result reviewable as Markdown/HTML artifacts.

Completed parser/schema-tool verification now includes old/new compatibility checks, descriptor-set compatibility checks, descriptor-registry release gates, JSON release-policy checks, richer release-policy DSL checks with warning severity, official generated-output contract checks, official scalar-matrix adapter coverage, installed-plugin official generator smoke checks, conformance-lite Markdown/JSON/JUnit evidence reports with expected-fail mutation self-checks and coverage gates, registry adapter publish/push/pull checks over local paths, HTTP, authenticated HTTP, hosted registry profiles, and managed GitHub Contents backend profiles, larger conformance-lite oracle fixtures, upstream-style wire-decode edge vectors, an imported upstream-lite conformance subset, edition/import/option/reserved/service/nested-type/qualified-nested-reference parser tolerance, signed enum value/reserved-range tolerance, enum allow_alias duplicate-number validation, string-literal escape/single-quote tolerance, empty-statement tolerance, top-level extend/custom-option block tolerance, oneof option tolerance, protobuf JSON null-as-absent parsing, block-comment tolerance, and reserved contract validation. Planned next verification:

- differential adapter tests against more official MoonBit protobuf runtime/codegen outputs when stable sample projects are available.
