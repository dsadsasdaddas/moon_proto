# Moon Proto Lab 5-minute demo

This demo is written for contest reviewers who want to verify the project value
quickly.  It shows the intended positioning: Moon Proto Lab is not a replacement
for `moonbitlang/protobuf`; it is a verification and tooling layer for MoonBit
protobuf schemas, JSON mapping, generated-code checks and compatibility review.

## 0. One-command health check

```bash
moon check
moon build
moon test
moon test --target all
tests/codegen/compile_generated.sh
```

Expected evidence:

- `moon test`: `60/60 passed`;
- all MoonBit targets pass: `wasm`, `wasm-gc`, `js`, `native`;
- generated-code compile check ends with `Generated MoonBit source compiles`.

## 1. Schema Doctor: reject unsafe `.proto` changes early

Valid schema:

```bash
python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto
```

Expected key output:

```text
schema valid
```

Invalid schema example:

```bash
cat > /tmp/moon_proto_bad.proto <<'PROTO'
syntax = "proto3";
message Bad {
  reserved 1;
  uint64 id = 1;
}
PROTO
python3 scripts/moon_proto_lab.py doctor /tmp/moon_proto_bad.proto
```

Expected key output:

```text
schema invalid
field uses reserved number
```

## 2. JSON roundtrip: normalize protobuf JSON with a schema

This demonstrates lowerCamel aliases, canonical snake_case output and numeric
map-key normalization.

```bash
moon run cmd/main -- json-roundtrip \
  --schema 'syntax = "proto3"; message Bag { map<uint64, string> u64 = 1; uint64 user_id = 2; }' \
  --message Bag \
  --json '{"u64":{"1.0":"one"},"userId":"150"}'
```

Expected exact output:

```json
{"u64":{"1":"one"},"user_id":"150"}
```

LowerCamel output mode:

```bash
moon run cmd/main -- json-roundtrip \
  --schema 'syntax = "proto3"; message Bag { map<uint64, string> u64 = 1; uint64 user_id = 2; }' \
  --message Bag \
  --json '{"u64":{"1.0":"one"},"userId":"150"}' \
  --lower-camel
```

Expected exact output:

```json
{"u64":{"1":"one"},"userId":"150"}
```

Duplicate canonical map keys are rejected:

```bash
moon run cmd/main -- json-roundtrip \
  --schema 'syntax = "proto3"; message Bag { map<uint64, string> u64 = 1; }' \
  --message Bag \
  --json '{"u64":{"1":"one","1.0":"uno"}}'
```

Expected key output:

```text
error: json decode failed: duplicate map JSON key: 1
```

## 3. Generated-code verification: AI output must compile

Generate MoonBit code from a `.proto` file:

```bash
python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/
moon check
```

Run the higher-level verification report:

```bash
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto \
  --report generated/verify_report.md \
  --junit-out generated/verify_report.xml
```

Expected evidence:

- `generated/verify_report.md` contains `Overall status: **PASS**`;
- `generated/verify_report.xml` contains `failures="0"`;
- generated MoonBit source is compile-checked.

## 4. Compatibility check: catch breaking schema changes

Compatible reserved-field migration:

```bash
python3 scripts/moon_proto_lab.py compat \
  examples/simple/user.proto \
  examples/simple/user_v2.proto \
  --report generated/compat_report.md \
  --junit-out generated/compat_report.xml
```

Expected key output/report evidence:

```text
schema compatible
```

Breaking change smoke example:

```bash
cat > /tmp/moon_proto_breaking.proto <<'PROTO'
syntax = "proto3";
package demo;
message User {
  string id = 1;
  string name = 3;
}
PROTO
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto /tmp/moon_proto_breaking.proto
```

Expected key output:

```text
schema incompatible
field type changed
field number changed
```

## 5. Conformance-lite evidence report

```bash
python3 scripts/moon_proto_conformance.py \
  --report generated/conformance_lite_report.md \
  --json-out generated/conformance_lite.json \
  --junit-out generated/conformance_lite.xml
```

Expected evidence:

- `generated/conformance_lite_report.md` contains `Overall status: **PASS**`;
- report includes upstream-style wire-decode cases, maps, oneof, numeric boundary,
  float/double and special float JSON cases;
- report includes negative self-checks for corrupted fixtures and missing
  artifacts;
- `generated/conformance_lite.xml` contains `failures="0"`.

## 6. Official MoonBit protobuf differential evidence

Default offline/partial mode:

```bash
python3 scripts/moon_proto_official_diff.py \
  --report generated/official_diff_report.md \
  --junit-out generated/official_diff_report.xml
```

CI also runs a stronger source-contract mode by cloning `moonbitlang/protoc-gen-mbt`:

```bash
python3 scripts/moon_proto_official_diff.py \
  --official-repo /tmp/protoc-gen-mbt \
  --require-official \
  --report generated/official_source_diff_report.md \
  --junit-out generated/official_source_diff_report.xml
```

Expected evidence:

- report status is `PASS`;
- manifest feature coverage is present;
- JUnit XML has `failures="0"`.

## 7. What this proves

After the steps above, reviewers have direct evidence for:

- schema parsing and validation;
- protobuf JSON mapping with MoonBit schema awareness;
- generated MoonBit code compiling;
- compatibility checks for schema evolution;
- cross-language oracle-backed fixture evidence;
- CI-friendly Markdown/JSON/JUnit reports;
- differentiation from the official runtime/codegen stack by focusing on
  verification, conformance evidence and AI-generated code maintainability.
