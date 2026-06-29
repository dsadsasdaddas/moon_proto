# Official MoonBit protobuf differential harness

Moon Proto Lab includes a lightweight differential harness around the public `moonbitlang/protoc-gen-mbt` / `moonbitlang/protobuf` ecosystem.

The goal is not to replace the official production generator. The goal is to make Moon Proto Lab useful as a verification layer around it:

- run Schema Doctor on schemas that overlap with the official feature surface;
- verify inspect output against a stable case manifest;
- generate Moon Proto Lab dynamic helper code and compile-check it;
- document intentional differences between the dynamic lab and the official typed generator;
- optionally invoke an official `protoc-gen-mbt` checkout when `protoc` and the official repository are available.

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
  --report generated/official_diff_report.md
```

Default mode does not require `protoc`. It must still run Moon Proto Lab doctor, inspect, codegen and generated-code compile checks. The official generator step is marked `SKIP` unless an official checkout is supplied.

## Run with the optional official generator

When `protoc`, MoonBit and a checkout of `moonbitlang/protoc-gen-mbt` are available:

```bash
git clone https://github.com/moonbitlang/protoc-gen-mbt /tmp/protoc-gen-mbt
python3 scripts/moon_proto_official_diff.py \
  --official-repo /tmp/protoc-gen-mbt \
  --report generated/official_diff_report.md
```

Use `--require-official` in environments where the official generator must be executed and `SKIP` should be treated as failure.

## Why this matters

This turns the project into ecosystem infrastructure rather than another protobuf runtime:

- Moon Proto Lab can verify schemas before official code generation;
- the manifest makes overlap with official capabilities explicit;
- generated reports are suitable for CI artifacts and contest demos;
- intentional differences are documented instead of hidden: Moon Proto Lab focuses on descriptor-driven dynamic `MessageValue` verification, while the official generator emits production typed MoonBit structs, maps and oneof enums.
