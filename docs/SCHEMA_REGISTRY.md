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

## Registry adapter publish/pull

The registry workflow also includes a small portable adapter for sharing descriptor registry artifacts without depending on a hosted service. `publish` writes a registry store with this layout:

```text
schema_registry_store/
├── registries/demo-user.json
└── blobs/<descriptor-sha256>.hex
```

Each published manifest version gets an `artifact_path` pointing at a content-addressed descriptor blob. `pull` can read the manifest from a local path, `file://` URL, or `http://` / `https://` URL, download every descriptor artifact, parse it as a `FileDescriptorSet`, and verify the descriptor SHA-256 against the manifest.

```bash
python3 scripts/moon_proto_descriptor.py publish \
  generated/descriptor_registry.json \
  --store generated/schema_registry_store \
  --base-dir . \
  --report generated/descriptor_registry_publish_report.md \
  --json-out generated/descriptor_registry_published.json \
  --junit-out generated/descriptor_registry_publish_report.xml

python3 scripts/moon_proto_descriptor.py pull \
  generated/schema_registry_store/registries/demo-user.json \
  --output-dir generated/schema_registry_pull \
  --report generated/descriptor_registry_pull_report.md \
  --json-out generated/descriptor_registry_pulled.json \
  --junit-out generated/descriptor_registry_pull_report.xml

python3 scripts/moon_proto_descriptor.py pull \
  http://127.0.0.1:8000/registries/demo-user.json \
  --output-dir generated/schema_registry_http_pull \
  --report generated/descriptor_registry_http_pull_report.md \
  --json-out generated/descriptor_registry_http_pulled.json \
  --junit-out generated/descriptor_registry_http_pull_report.xml
```

Authenticated HTTP registries are supported through either `--bearer-token`, `--token-env`, or repeated `--header 'Name: value'` options. The same headers are used for the manifest request and descriptor artifact requests:

```bash
MOON_PROTO_REGISTRY_TOKEN=moon-secret-token \
python3 scripts/moon_proto_descriptor.py pull \
  https://schemas.example.test/registries/demo-user.json \
  --token-env MOON_PROTO_REGISTRY_TOKEN \
  --output-dir generated/schema_registry_auth_pull \
  --report generated/descriptor_registry_auth_pull_report.md \
  --json-out generated/descriptor_registry_auth_pulled.json \
  --junit-out generated/descriptor_registry_auth_pull_report.xml
```

The reverse direction is covered by `push`, which uploads all content-addressed descriptor blobs and the registry manifest to an HTTP(S) endpoint that accepts `PUT` for `blobs/...` and `registries/...`:

```bash
MOON_PROTO_REGISTRY_TOKEN=moon-secret-token \
python3 scripts/moon_proto_descriptor.py push \
  generated/schema_registry_store \
  --base-url https://schemas.example.test/ \
  --registry demo-user.json \
  --token-env MOON_PROTO_REGISTRY_TOKEN \
  --report generated/descriptor_registry_push_report.md \
  --json-out generated/descriptor_registry_pushed.json \
  --junit-out generated/descriptor_registry_push_report.xml
```

`push` verifies each local descriptor artifact against the manifest SHA-256 before uploading it, and it records the remote base URL in the JSON result. This gives CI and demos a concrete registry adapter story: generate a registry manifest, publish immutable descriptor blobs, push/pull them over HTTP(S), authenticate against hosted registries when needed, and verify every artifact before accepting a release gate.

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

The generated Markdown and JUnit XML reports are suitable for human review. The generated JSON manifest, policy result, and adapter publish/pull metadata are suitable for CI, release gates, static artifact hosting, or future integration with a hosted schema registry service.

## Why this matters

A protobuf ecosystem needs more than a runtime. Teams need a way to decide whether a schema version can be released safely. This workflow makes Moon Proto Lab useful as a CI-side guardrail for protobuf descriptor artifacts, including descriptors produced by other languages or tools.
