# Descriptor registry workflow

Moon Proto Lab includes a small descriptor-registry workflow for projects that publish protobuf schemas as `FileDescriptorSet` artifacts. It imports ordered descriptor versions, reconstructs the supported proto3 subset, validates every version with Schema Doctor, and checks adjacent versions for protobuf compatibility.

## Import ordered descriptor versions

```bash
python3 scripts/moon_proto_descriptor.py registry \
  tests/fixtures/user_descriptor_set.hex \
  tests/fixtures/user_descriptor_set_reserved_v2.hex \
  --name demo-user \
  --report generated/descriptor_registry_report.md \
  --json-out generated/descriptor_registry.json \
  --junit-out generated/descriptor_registry_report.xml \
  --policy tests/fixtures/descriptor_registry_policy.json
```

Inputs may be explicit descriptor files or directories containing descriptor files. Explicit files are recommended when version order matters. Supported input formats are `.pb`, `.bin`, `.hex`, and `.json`.

## Release policy gate

A registry manifest can also be checked against a JSON release policy:

```bash
python3 scripts/moon_proto_descriptor.py policy \
  generated/descriptor_registry.json \
  tests/fixtures/descriptor_registry_policy.json \
  --report generated/descriptor_policy_report.md \
  --json-out generated/descriptor_policy.json \
  --junit-out generated/descriptor_policy_report.xml
```

The checked-in strict sample policy requires at least two versions, at least one compatibility edge, unique descriptor digests, package `demo`, message `User`, and no breaking adjacent changes. The same policy can be passed directly to `registry --policy ...` so CI fails immediately when a proposed descriptor sequence violates the release gate.

## Release policy DSL

Policies support both simple top-level keys and a richer `checks` array. Each rule can set:

- `type`: `require_registry_pass`, `min_versions`, `min_compatibility_edges`, `max_breaking_edges`, `require_unique_digests`, `require_values`, or `forbid_values`;
- `name`: optional human-readable report label;
- `severity`: `error` by default, or `warning` for non-blocking advisory checks;
- `enabled`: optional boolean for temporarily disabling a rule.

Value rules use `key` (`files`, `packages`, `messages`, or `enums`) plus a `values` string list.

Example relaxed policy:

```json
{
  "require_registry_pass": false,
  "allow_breaking": true,
  "min_versions": 2,
  "max_breaking_edges": 1,
  "checks": [
    { "type": "require_unique_digests", "name": "unique digests via DSL" },
    {
      "type": "require_values",
      "name": "required User message via DSL",
      "key": "messages",
      "values": ["User"]
    },
    {
      "type": "forbid_values",
      "name": "warning when demo package is still present",
      "key": "packages",
      "values": ["demo"],
      "severity": "warning"
    }
  ]
}
```

With this policy, a registry can report base compatibility `FAIL` while the release gate returns `PASS` if the declared rule budget allows it. Warning checks are rendered as `WARN` in Markdown/JSON reports and do not create JUnit failures.

## What the registry command checks

For each imported version it records:

- descriptor input path;
- SHA-256 digest of the canonical serialized descriptor set;
- files, packages, messages, and enums discovered in the descriptor;
- Schema Doctor status after reconstructing proto text.

For every adjacent version pair it runs the same compatibility checker used by `.proto` files. A registry is considered passing only when every version validates and every adjacent compatibility edge is passing.

## Positive and negative fixtures

The checked-in fixtures provide both success and failure evidence:

- `user_descriptor_set.hex` -> `user_descriptor_set_reserved_v2.hex` passes because `phone = 6` is removed only after reserving both number `6` and name `"phone"`, while `created_at = 9` is added safely.
- `user_descriptor_set.hex` -> `user_descriptor_set_breaking.hex` fails because `id = 1` changes from `uint32` to `string`.

The generated Markdown and JUnit XML reports are suitable for human review. The generated JSON manifest and policy result are suitable for CI, release gates, or future integration with a real schema registry service.

## Why this matters

A protobuf ecosystem needs more than a runtime. Teams need a way to decide whether a schema version can be released safely. This workflow makes Moon Proto Lab useful as a CI-side guardrail for protobuf descriptor artifacts, including descriptors produced by other languages or tools.
