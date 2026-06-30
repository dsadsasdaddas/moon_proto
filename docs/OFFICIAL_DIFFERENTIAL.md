# Official MoonBit protobuf differential harness

Moon Proto Lab includes a lightweight differential harness around the public `moonbitlang/protoc-gen-mbt` / `moonbitlang/protobuf` ecosystem.

The goal is not to replace the official production generator. The goal is to make Moon Proto Lab useful as a verification layer around it:

- run Schema Doctor on schemas that overlap with the official feature surface;
- verify inspect output against a stable case manifest;
- generate Moon Proto Lab dynamic helper code and compile-check it;
- document intentional differences between the dynamic lab and the official typed generator;
- validate the public official README/spec contract when an official checkout is available;
- optionally invoke an official `protoc-gen-mbt` checkout when `protoc` and registry dependencies are available;
- optionally invoke an already-installed `protoc-gen-mbt` plugin via `--official-plugin-bin` without requiring an official checkout.

## Manifest

The case manifest lives at:

```text
tests/differential/official_cases.json
```

It records the observed official repository and feature contract used by the harness:

- official repository: https://github.com/moonbitlang/protoc-gen-mbt
- observed commit: `9ac87899cf20ea88e31ba77330958ba389eab5fd`
- runtime package: `moonbitlang/protobuf@0.1.3`
- source files: `README.md` and `doc/spec.md`

Current cases:

| Case | Schema | Coverage |
| --- | --- | --- |
| `simple_user` | `examples/simple/user.proto` | scalar, repeated, map, oneof |
| `decorated_telemetry` | `examples/decorated/telemetry.proto` | import, option, reserved, enum, optional, map, oneof |

## Run the default contract check

```bash
python3 scripts/moon_proto_official_diff.py \
  --report generated/official_diff_report.md \
  --junit-out generated/official_diff_report.xml
```

Default mode does not require `protoc` or an official checkout. It still runs Moon Proto Lab doctor, inspect, codegen and generated-code compile checks. The official source and generator steps are marked `SKIP`, but the overall report can still pass because the dynamic lab contract is verified. `--junit-out` emits CI-readable skipped test cases for those optional official steps.

## Run the official source contract check

When a checkout of `moonbitlang/protoc-gen-mbt` is available, the harness can validate that the public README/spec feature contract still matches the manifest. This mode is stable enough for CI and does not build the official generator:

```bash
git clone --depth 1 https://github.com/moonbitlang/protoc-gen-mbt /tmp/protoc-gen-mbt
python3 scripts/moon_proto_official_diff.py \
  --official-repo /tmp/protoc-gen-mbt \
  --require-official \
  --report generated/official_source_diff_report.md \
  --junit-out generated/official_source_diff_report.xml
```

`--require-official` makes the source-contract step blocking. Moon Proto Lab CI runs this mode.

## Run with the optional official generator

When `protoc`, MoonBit, the official checkout, and its registry dependencies are all available, the same harness can attempt to build and invoke the official generator:

```bash
python3 scripts/moon_proto_official_diff.py \
  --official-repo /tmp/protoc-gen-mbt \
  --run-official-generator \
  --require-official \
  --report generated/official_generator_diff_report.md \
  --junit-out generated/official_generator_diff_report.xml
```

The generator step is only blocking when both `--require-official` and `--run-official-generator` are used. This keeps the main CI stable while still documenting a deeper path for environments where the official generator dependency graph resolves.


If an official plugin is already installed, use `--official-plugin-bin` instead of building from the checkout:

```bash
python3 scripts/moon_proto_official_diff.py \
  --run-official-generator \
  --official-plugin-bin protoc-gen-mbt \
  --protoc-bin protoc \
  --report generated/official_installed_plugin_diff_report.md \
  --junit-out generated/official_installed_plugin_diff_report.xml
```

This installed-plugin path is useful for CI images or developer machines that cache the official generator executable. It still marks the source-contract step as `SKIP` unless `--official-repo` is also provided, but the generator step itself can pass and is emitted to Markdown/JUnit.

## Validate pre-generated official output

When the official generator has already been run in another environment, point the harness at the generated `.mbt` tree:

```bash
python3 scripts/moon_proto_official_diff.py \
  --official-generated-dir tests/differential/official_generated_fixture \
  --report generated/official_generated_diff_report.md \
  --junit-out generated/official_generated_diff_report.xml
```

The harness checks each case against `expected_official_generated` snippets in `tests/differential/official_cases.json`. This mode is useful for CI environments that can consume cached official-generator artifacts but should not rebuild the official generator on every run.

## Why this matters

This turns the project into ecosystem infrastructure rather than another protobuf runtime:

- Moon Proto Lab can verify schemas before official code generation;
- the manifest makes overlap with official capabilities explicit;
- generated Markdown/HTML/JUnit reports are suitable for CI artifacts and contest demos;
- pre-generated official output can be checked without requiring `protoc` or official generator dependencies in the same job;
- installed official generator binaries can be smoke-tested directly with `--official-plugin-bin`;
- intentional differences are documented instead of hidden: Moon Proto Lab focuses on descriptor-driven dynamic `MessageValue` verification, while the official generator emits production typed MoonBit structs, maps and oneof enums.
