# Schema Doctor and verification reports

Moon Proto Lab now includes file-based commands for schema diagnostics and AI-generated code verification. These commands are intentionally positioned as ecosystem tooling around protobuf usage in MoonBit, not as a replacement for existing protobuf runtime packages.

## Schema Doctor

Run diagnostics for a `.proto` file:

```bash
python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto
```

Expected output for a valid schema:

```text
schema valid
syntax: proto3
package: demo
messages: 1
enums: 0
```

For invalid schemas, the command returns a non-zero exit status and prints stable issue paths, for example:

```text
schema invalid
issues: 1
message.Bad.field.1: duplicate field number
```

The parser accepts common real-world proto decorations before diagnostics run: dotted package/type names, `import`, `option`, `reserved`, `extensions`, and field/enum value option brackets. The current diagnostics are backed by the MoonBit `validate_proto_file` implementation and cover:

- proto3 syntax check;
- field number range and protobuf-reserved 19000..19999 numbers;
- duplicate field names and field numbers;
- empty names;
- proto3 enum first value must be zero;
- duplicate enum names or values;
- top-level message/enum name conflicts;
- map key/value constraints;
- oneof group name validation.

## Schema inspect

Print a compact schema summary for debugging and reports:

```bash
python3 scripts/moon_proto_lab.py inspect examples/decorated/telemetry.proto
```

The output includes package, message count, enum count, fields, labels, numbers and resolved scalar/named types.


## Schema compatibility check

Check whether a new schema preserves the contracts used by an old schema:

```bash
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto \
  --report generated/compat_report.md
```

The compatibility checker treats these changes as breaking:

- old message removed;
- old field number removed;
- old field number reused with a different name;
- old field type changed;
- old field label changed, including singular/repeated/optional/oneof changes;
- old field name moved to a different number;
- old enum removed;
- old enum value removed or moved to a different number;
- package or syntax changed;
- either old or new schema fails Schema Doctor validation.

Adding new fields or new enum values is accepted. The command returns a non-zero exit status for incompatible schemas and can emit Markdown or HTML reports by choosing the report file suffix.

## AI verify workflow

Run the full verification workflow:

```bash
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto \
  --report generated/verify_report.md
```

The verify command performs:

1. Schema Doctor diagnostics.
2. Schema inspection summary.
3. MoonBit source generation.
4. Generated-code compile check through `moon check` in a temporary copy of the repository.
5. Optional Markdown or HTML report generation.

Write an HTML report by using an `.html` suffix:

```bash
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto \
  --report generated/verify_report.html
```

Use `--skip-compile` only when a fast report is needed and the caller will run compile checks elsewhere.

## Why this matters

AI can produce plausible `.proto` schemas and generated MoonBit code, but plausibility is not enough for maintainable infrastructure. This workflow turns AI output into checked artifacts:

- invalid schemas fail early;
- old/new schema compatibility regressions are caught before codegen;
- diagnostics are stable enough for CI and documentation;
- generated MoonBit source must compile;
- Markdown/HTML reports make the verification result reviewable in a contest demo or code review.
