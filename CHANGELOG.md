# Changelog

All notable changes to **Moon Proto Lab** are recorded here for contest review,
release tracking, and long-term maintenance.

## [0.1.0-submission] - 2026-06-30

### Added

- Protobuf wire-format primitives: varint, wire keys, zig-zag, fixed-width,
  length-delimited values and common field encoders.
- Proto3 schema model, lexer and parser for messages, enums, maps, oneof,
  reservations, options, nested types, service/rpc tolerance and edition
  tolerance.
- Schema validation diagnostics for duplicate fields, reserved contracts, enum
  invariants, map constraints and breaking schema patterns.
- Dynamic descriptor-driven encode/decode runtime for scalar, repeated, packed,
  enum, nested message, map and oneof fields.
- Protobuf JSON mapping support, including lowerCamel aliases, enum-name
  mapping, bytes base64 variants, Unicode escapes, strict number grammar,
  integer exponent notation, null-as-absent semantics and canonical map-key
  normalization.
- MoonBit code generation helpers and file-based generator wrapper.
- Schema Doctor, schema inspection, compatibility checker, schema-aware JSON
  roundtrip CLI and AI-verification report workflow.
- Python and Go protobuf oracle fixtures, deterministic golden vectors,
  conformance-lite evidence, official MoonBit protobuf differential checks and
  generated-code compile checks.
- FileDescriptorSet bridge, descriptor compatibility, descriptor registry
  release gates, policy checks, publish/pull workflows and registry adapter
  verification.
- GitHub Actions CI and submission documentation.

### Verification evidence

- `moon check`
- `moon build`
- `moon test` -> `60/60 passed`
- `moon test --target all` -> wasm / wasm-gc / js / native all passed
- `tests/codegen/compile_generated.sh` -> `Generated MoonBit source compiles`
- `python3 scripts/moon_proto_conformance.py ...` -> conformance-lite `PASS`
- `python3 scripts/moon_proto_lab.py verify ...` -> verification report `PASS`
- `python3 scripts/moon_proto_lab.py compat ...` -> compatibility report `PASS`
- Python protobuf oracle -> `PASS`
- Go protobuf oracle -> `PASS` when Go is available

### Engineering notes

This release is feature-frozen for contest submission. Future changes should be
small, issue-driven and regression-test-first.
