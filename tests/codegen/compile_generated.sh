#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/moon_proto_codegen_check_$$"
HTTP_PID=""
cleanup() {
  if [ -n "${HTTP_PID:-}" ]; then
    kill "$HTTP_PID" 2>/dev/null || true
    wait "$HTTP_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP"
(
  cd "$ROOT"
  tar \
    --exclude=.git \
    --exclude=_build \
    --exclude=.mooncakes \
    --exclude=tmp \
    -cf - .
) | tar -xf - -C "$TMP"

cd "$TMP"
moon run cmd/main -- gen --example > generated_check.mbt

grep -q 'pub(all) struct User' generated_check.mbt
grep -q 'pub fn message_descriptors' generated_check.mbt
grep -q 'pub fn encode_User' generated_check.mbt
grep -q 'pub fn from_json_User' generated_check.mbt

moon check

rm generated_check.mbt
moon run cmd/main -- gen --schema 'syntax = "proto3"; message Smoke { uint64 id = 1; }' > generated_inline_check.mbt

grep -q 'pub(all) struct Smoke' generated_inline_check.mbt
grep -q 'pub fn encode_Smoke' generated_inline_check.mbt

moon check

rm generated_inline_check.mbt
python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/

grep -q 'pub(all) struct User' generated/user.mbt
grep -q 'MapType(StringType, UInt64Type)' generated/user.mbt
grep -q 'Oneof("contact")' generated/user.mbt

cp generated/user.mbt generated_file_check.mbt
moon check
rm generated_file_check.mbt

python3 scripts/moon_proto_gen.py gen examples/simple/user.proto --stdout --quiet \
  | grep -q 'pub fn decode_User'

python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/simple/user.proto \
  | grep -q 'message User fields='

python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/decorated/telemetry.proto \
  | grep -q 'reserved numbers: 7, 9 to 12'

python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry_service.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/decorated/telemetry_service.proto \
  | grep -q 'message TelemetryRequest fields=1'

python3 scripts/moon_proto_lab.py verify examples/decorated/telemetry_service.proto \
  --report generated/verify_service_report.md \
  --junit-out generated/verify_service_report.xml
grep -Fq 'Overall status: **PASS**' generated/verify_service_report.md
grep -q 'TelemetryAck' generated/verify_service_report.md
grep -q 'failures="0"' generated/verify_service_report.xml

python3 scripts/moon_proto_lab.py doctor examples/decorated/nested_types.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/decorated/nested_types.proto \
  | grep -q 'message Envelope fields=3'

python3 scripts/moon_proto_lab.py inspect examples/decorated/nested_types.proto \
  | grep -q 'enum Kind values=3'

python3 scripts/moon_proto_lab.py inspect examples/decorated/telemetry.proto \
  | grep -q 'enum Severity values=4 allow_alias=true'

python3 scripts/moon_proto_lab.py verify examples/decorated/nested_types.proto \
  --report generated/verify_nested_types_report.md \
  --junit-out generated/verify_nested_types_report.xml
grep -Fq 'Overall status: **PASS**' generated/verify_nested_types_report.md
grep -q 'pub(all) struct Payload' generated/verify_nested_types_report.md
grep -q 'history : Array\[Payload\]' generated/verify_nested_types_report.md
grep -q 'failures="0"' generated/verify_nested_types_report.xml

python3 scripts/moon_proto_lab.py doctor examples/decorated/nested_qualified.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/decorated/nested_qualified.proto \
  | grep -q 'message AuditTrail fields=4'

python3 scripts/moon_proto_lab.py inspect examples/decorated/nested_qualified.proto \
  | grep -q 'map<string, Payload>'

python3 scripts/moon_proto_lab.py verify examples/decorated/nested_qualified.proto \
  --report generated/verify_nested_qualified_report.md \
  --junit-out generated/verify_nested_qualified_report.xml
grep -Fq 'Overall status: **PASS**' generated/verify_nested_qualified_report.md
grep -q 'latest : Payload' generated/verify_nested_qualified_report.md
grep -q 'kind : Kind' generated/verify_nested_qualified_report.md
grep -q 'history : Array\[Payload\]' generated/verify_nested_qualified_report.md
grep -q 'MapType(StringType, NamedType("Payload"))' generated/verify_nested_qualified_report.md
grep -q 'failures="0"' generated/verify_nested_qualified_report.xml

python3 scripts/moon_proto_lab.py doctor examples/decorated/enum_numbers.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/decorated/enum_numbers.proto \
  | grep -q -- '-1 STATUS_NEGATIVE'

python3 scripts/moon_proto_lab.py inspect examples/decorated/enum_numbers.proto \
  | grep -q -- 'reserved numbers: -10 to -2'

python3 scripts/moon_proto_lab.py verify examples/decorated/enum_numbers.proto \
  --report generated/verify_enum_numbers_report.md \
  --junit-out generated/verify_enum_numbers_report.xml
grep -Fq 'Overall status: **PASS**' generated/verify_enum_numbers_report.md
grep -q 'STATUS_NEGATIVE' generated/verify_enum_numbers_report.md
grep -q 'number : -1' generated/verify_enum_numbers_report.md
grep -q 'failures="0"' generated/verify_enum_numbers_report.xml

python3 scripts/moon_proto_lab.py doctor examples/decorated/enum_alias.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/decorated/enum_alias.proto \
  | grep -q 'enum AliasResult values=4 allow_alias=true'

python3 scripts/moon_proto_lab.py verify examples/decorated/enum_alias.proto \
  --report generated/verify_enum_alias_report.md \
  --junit-out generated/verify_enum_alias_report.xml
grep -Fq 'Overall status: **PASS**' generated/verify_enum_alias_report.md
grep -q 'allow_alias : true' generated/verify_enum_alias_report.md
grep -q 'ALIAS_RESULT_SUCCESS' generated/verify_enum_alias_report.md
grep -q 'failures="0"' generated/verify_enum_alias_report.xml

python3 scripts/moon_proto_lab.py doctor examples/decorated/string_literals.proto \
  | grep -q 'schema valid'

python3 scripts/moon_proto_lab.py inspect examples/decorated/string_literals.proto \
  | grep -q 'reserved names: old_name, legacy_name'

python3 scripts/moon_proto_lab.py verify examples/decorated/string_literals.proto \
  --report generated/verify_string_literals_report.md \
  --junit-out generated/verify_string_literals_report.xml
grep -Fq 'Overall status: **PASS**' generated/verify_string_literals_report.md
grep -q 'StringLiteralCarrier' generated/verify_string_literals_report.md
grep -q 'text : String' generated/verify_string_literals_report.md
grep -q 'failures="0"' generated/verify_string_literals_report.xml

python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto \
  --report generated/compat_report.md \
  --junit-out generated/compat_report.xml
grep -q 'schema compatible' generated/compat_report.md
grep -Fq 'Overall status: **PASS**' generated/compat_report.md
grep -q '<testsuite' generated/compat_report.xml
grep -q 'failures="0"' generated/compat_report.xml

cat > user_v2_breaking.proto <<'EOF'
syntax = "proto3";
package demo;
message User {
  string id = 1;
  string name = 3;
}
EOF

if python3 scripts/moon_proto_lab.py compat examples/simple/user.proto user_v2_breaking.proto > compat_breaking.txt 2>&1; then
  echo "compat unexpectedly accepted user_v2_breaking.proto" >&2
  exit 1
fi
grep -q 'schema incompatible' compat_breaking.txt
grep -q 'field type changed' compat_breaking.txt
grep -q 'field number changed' compat_breaking.txt

cat > item_v1.proto <<'EOF'
syntax = "proto3";
package demo;
message Item {
  uint64 keep = 1;
  string old_name = 2;
}
EOF

cat > item_v2_reserved.proto <<'EOF'
syntax = "proto3";
package demo;
message Item {
  uint64 keep = 1;
  reserved 2;
  reserved "old_name";
}
EOF

python3 scripts/moon_proto_lab.py compat item_v1.proto item_v2_reserved.proto \
  | grep -q 'schema compatible'

cat > item_v1_reserved.proto <<'EOF'
syntax = "proto3";
package demo;
message Item {
  reserved 9;
  reserved "legacy";
  uint64 keep = 1;
}
EOF

cat > item_v2_reuse_reserved.proto <<'EOF'
syntax = "proto3";
package demo;
message Item {
  uint64 keep = 1;
  string legacy = 9;
}
EOF

if python3 scripts/moon_proto_lab.py compat item_v1_reserved.proto item_v2_reuse_reserved.proto > compat_reserved_breaking.txt 2>&1; then
  echo "compat unexpectedly accepted reserved reuse" >&2
  exit 1
fi
grep -q 'field uses previously reserved number' compat_reserved_breaking.txt
grep -q 'reserved name not preserved' compat_reserved_breaking.txt

cat > invalid_duplicate.proto <<'EOF'
syntax = "proto3";
message Bad {
  uint64 id = 1;
  string name = 1;
}
EOF

if python3 scripts/moon_proto_lab.py doctor invalid_duplicate.proto > invalid_doctor.txt 2>&1; then
  echo "doctor unexpectedly accepted invalid_duplicate.proto" >&2
  exit 1
fi
grep -q 'schema invalid' invalid_doctor.txt
grep -q 'duplicate field number' invalid_doctor.txt

cat > invalid_reserved.proto <<'EOF'
syntax = "proto3";
message Bad {
  reserved 1, 5 to 6;
  reserved "old_name";
  uint64 id = 1;
  string old_name = 2;
  bool another = 5;
}
EOF

if python3 scripts/moon_proto_lab.py doctor invalid_reserved.proto > invalid_reserved_doctor.txt 2>&1; then
  echo "doctor unexpectedly accepted invalid_reserved.proto" >&2
  exit 1
fi
grep -q 'field uses reserved number' invalid_reserved_doctor.txt
grep -q 'field uses reserved name' invalid_reserved_doctor.txt

python3 scripts/moon_proto_lab.py verify examples/simple/user.proto \
  --report generated/verify_report.md \
  --junit-out generated/verify_report.xml
grep -Fq 'Overall status: **PASS**' generated/verify_report.md
grep -q 'Generated MoonBit source preview' generated/verify_report.md
grep -q '<testsuite' generated/verify_report.xml
grep -q 'failures="0"' generated/verify_report.xml

python3 scripts/moon_proto_lab.py verify examples/simple/user.proto \
  --report generated/verify_report.html --skip-compile
grep -q '<!doctype html>' generated/verify_report.html
grep -q 'Moon Proto Lab verification report' generated/verify_report.html

python3 scripts/moon_proto_official_diff.py \
  --report generated/official_diff_report.md \
  --junit-out generated/official_diff_report.xml
grep -Fq 'Overall status: **PASS**' generated/official_diff_report.md
grep -q 'Manifest feature coverage' generated/official_diff_report.md
grep -q 'official feature coverage' generated/official_diff_report.md
grep -q 'scalar_matrix' generated/official_diff_report.md
grep -q '17 samples : repeated uint32' generated/official_diff_report.md
grep -q 'official protoc-gen-mbt' generated/official_diff_report.md
grep -q 'SKIP' generated/official_diff_report.md
grep -q '<testsuite' generated/official_diff_report.xml
grep -q 'failures="0"' generated/official_diff_report.xml
grep -q '<skipped' generated/official_diff_report.xml

python3 scripts/moon_proto_official_diff.py \
  --official-generated-dir tests/differential/official_generated_fixture \
  --report generated/official_generated_diff_report.md \
  --junit-out generated/official_generated_diff_report.xml
grep -Fq 'Overall status: **PASS**' generated/official_generated_diff_report.md
grep -q 'official generated output contract' generated/official_generated_diff_report.md
grep -q 'scalar_matrix' generated/official_generated_diff_report.md
grep -q 'pub struct ScalarMatrix' generated/official_generated_diff_report.md
grep -q 'expected snippets found' generated/official_generated_diff_report.md
grep -q '<testsuite' generated/official_generated_diff_report.xml
grep -q 'failures="0"' generated/official_generated_diff_report.xml

cat > generated/fake_protoc <<'PY'
#!/usr/bin/env python3
import pathlib
import sys

out_root = None
project = "official_diff_gen"
for arg in sys.argv[1:]:
    if arg.startswith("--mbt_out="):
        out_root = pathlib.Path(arg.split("=", 1)[1])
    elif arg.startswith("--mbt_opt="):
        for item in arg.split("=", 1)[1].split(","):
            if item.startswith("project_name="):
                project = item.split("=", 1)[1]
if out_root is None:
    raise SystemExit("--mbt_out is required")
target = out_root / project / "fake_official_output.mbt"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text("// fake official protoc-gen-mbt output for installed-plugin smoke test\n", encoding="utf-8")
PY
cat > generated/fake_protoc_gen_mbt <<'SH'
#!/usr/bin/env sh
exit 0
SH
chmod +x generated/fake_protoc generated/fake_protoc_gen_mbt
python3 scripts/moon_proto_official_diff.py \
  --run-official-generator \
  --official-plugin-bin generated/fake_protoc_gen_mbt \
  --protoc-bin generated/fake_protoc \
  --report generated/official_installed_plugin_diff_report.md \
  --junit-out generated/official_installed_plugin_diff_report.xml
grep -Fq 'Overall status: **PASS**' generated/official_installed_plugin_diff_report.md
grep -q 'Official generator requested: `true`' generated/official_installed_plugin_diff_report.md
grep -q 'official protoc-gen-mbt | PASS' generated/official_installed_plugin_diff_report.md
grep -q 'generated 1 file' generated/official_installed_plugin_diff_report.md
grep -q 'failures="0"' generated/official_installed_plugin_diff_report.xml

python3 scripts/moon_proto_conformance.py \
  --report generated/conformance_lite_report.md \
  --json-out generated/conformance_lite.json \
  --junit-out generated/conformance_lite.xml
grep -Fq 'Overall status: **PASS**' generated/conformance_lite_report.md
grep -q 'proto3_map_string_and_int64_keys' generated/conformance_lite_report.md
grep -q 'proto3_wire_decode_unknown_duplicate_packed_unpacked' generated/conformance_lite_report.md
grep -q 'coverage:wire-decode' generated/conformance_lite_report.md
grep -q 'coverage:unknown-field' generated/conformance_lite_report.md
grep -q 'Required.Proto3.UnknownFieldsAreSkipped.BinaryInput' generated/conformance_lite_report.md
grep -q 'Required.Proto3.SpecialFloatJsonStrings.JsonOutput' generated/conformance_lite_report.md
grep -q 'Upstream-lite subset' generated/conformance_lite_report.md
grep -q 'coverage:upstream-lite' generated/conformance_lite_report.md
grep -q 'coverage:protobuf-input' generated/conformance_lite_report.md
grep -q '"upstream_lite"' generated/conformance_lite.json
grep -q 'coverage:upstream-lite' generated/conformance_lite.xml
grep -q 'reject_hex_binary_mismatch' generated/conformance_lite_report.md
grep -q 'Coverage gates' generated/conformance_lite_report.md
grep -q 'coverage:fixture-integrity' generated/conformance_lite_report.md
grep -q 'negative-self-check' generated/conformance_lite.json
grep -q '"coverage_gates"' generated/conformance_lite.json
grep -q 'coverage:map' generated/conformance_lite.xml
grep -q '"overall_status": "PASS"' generated/conformance_lite.json
grep -q '<testsuite' generated/conformance_lite.xml
grep -q 'failures="0"' generated/conformance_lite.xml

python3 scripts/moon_proto_descriptor.py fixture \
  --hex-out generated/user_descriptor_set.hex \
  --json-out generated/user_descriptor_set.json
cmp generated/user_descriptor_set.hex tests/fixtures/user_descriptor_set.hex
python3 scripts/moon_proto_descriptor.py fixture \
  --variant user_reserved_v2 \
  --hex-out generated/user_descriptor_set_reserved_v2.hex \
  --json-out generated/user_descriptor_set_reserved_v2.json
cmp generated/user_descriptor_set_reserved_v2.hex tests/fixtures/user_descriptor_set_reserved_v2.hex
python3 scripts/moon_proto_descriptor.py fixture \
  --variant user_breaking \
  --hex-out generated/user_descriptor_set_breaking.hex \
  --json-out generated/user_descriptor_set_breaking.json
cmp generated/user_descriptor_set_breaking.hex tests/fixtures/user_descriptor_set_breaking.hex

python3 scripts/moon_proto_descriptor.py inspect tests/fixtures/user_descriptor_set.hex \
  --report generated/descriptor_report.md
grep -q 'descriptor set valid' generated/descriptor_report.md

python3 scripts/moon_proto_descriptor.py to-proto tests/fixtures/user_descriptor_set.hex \
  -o generated/user_from_descriptor.proto
grep -q 'map<string, uint64> counters = 4;' generated/user_from_descriptor.proto
grep -q 'oneof contact' generated/user_from_descriptor.proto

python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex \
  --report generated/descriptor_verify_report.md \
  --junit-out generated/descriptor_verify_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_verify_report.md
grep -q '<testsuite' generated/descriptor_verify_report.xml
grep -q 'failures="0"' generated/descriptor_verify_report.xml

python3 scripts/moon_proto_descriptor.py compat \
  tests/fixtures/user_descriptor_set.hex \
  tests/fixtures/user_descriptor_set_reserved_v2.hex \
  --report generated/descriptor_compat_report.md \
  --junit-out generated/descriptor_compat_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_compat_report.md
grep -q '<testsuite' generated/descriptor_compat_report.xml
grep -q 'failures="0"' generated/descriptor_compat_report.xml

if python3 scripts/moon_proto_descriptor.py compat \
  tests/fixtures/user_descriptor_set.hex \
  tests/fixtures/user_descriptor_set_breaking.hex \
  --report generated/descriptor_breaking_report.md \
  --junit-out generated/descriptor_breaking_report.xml; then
  echo "expected descriptor compat failure" >&2
  exit 1
fi
grep -Fq 'Overall status: **FAIL**' generated/descriptor_breaking_report.md
grep -q 'field type changed' generated/descriptor_breaking_report.md
grep -q '<failure' generated/descriptor_breaking_report.xml

python3 scripts/moon_proto_descriptor.py registry \
  tests/fixtures/user_descriptor_set.hex \
  tests/fixtures/user_descriptor_set_reserved_v2.hex \
  --name demo-user \
  --report generated/descriptor_registry_report.md \
  --json-out generated/descriptor_registry.json \
  --policy tests/fixtures/descriptor_registry_policy.json \
  --junit-out generated/descriptor_registry_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_report.md
grep -q 'schema compatible' generated/descriptor_registry_report.md
grep -q 'Release policy checks' generated/descriptor_registry_report.md
grep -q '"overall_status": "PASS"' generated/descriptor_registry.json
grep -q '"policy"' generated/descriptor_registry.json
grep -q '<testsuite' generated/descriptor_registry_report.xml
grep -q 'failures="0"' generated/descriptor_registry_report.xml

python3 scripts/moon_proto_descriptor.py policy \
  generated/descriptor_registry.json \
  tests/fixtures/descriptor_registry_policy.json \
  --report generated/descriptor_policy_report.md \
  --json-out generated/descriptor_policy.json \
  --junit-out generated/descriptor_policy_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_policy_report.md
grep -q '"status": "PASS"' generated/descriptor_policy.json
grep -q '<testsuite' generated/descriptor_policy_report.xml
grep -q 'failures="0"' generated/descriptor_policy_report.xml

if python3 scripts/moon_proto_descriptor.py registry \
  tests/fixtures/user_descriptor_set.hex \
  tests/fixtures/user_descriptor_set_breaking.hex \
  --name demo-user-breaking \
  --report generated/descriptor_registry_breaking_report.md \
  --json-out generated/descriptor_registry_breaking.json \
  --policy tests/fixtures/descriptor_registry_policy.json \
  --junit-out generated/descriptor_registry_breaking_report.xml; then
  echo "expected descriptor registry failure" >&2
  exit 1
fi
grep -Fq 'Overall status: **FAIL**' generated/descriptor_registry_breaking_report.md
grep -q 'field type changed' generated/descriptor_registry_breaking_report.md
grep -q '"overall_status": "FAIL"' generated/descriptor_registry_breaking.json
grep -q '<failure' generated/descriptor_registry_breaking_report.xml
if python3 scripts/moon_proto_descriptor.py policy \
  generated/descriptor_registry_breaking.json \
  tests/fixtures/descriptor_registry_policy.json \
  --report generated/descriptor_policy_breaking_report.md \
  --json-out generated/descriptor_policy_breaking.json \
  --junit-out generated/descriptor_policy_breaking_report.xml; then
  echo "expected descriptor policy failure" >&2
  exit 1
fi
grep -Fq 'Overall status: **FAIL**' generated/descriptor_policy_breaking_report.md
grep -q 'no breaking adjacent changes' generated/descriptor_policy_breaking_report.md
grep -q '"status": "FAIL"' generated/descriptor_policy_breaking.json
grep -q '<failure' generated/descriptor_policy_breaking_report.xml

python3 scripts/moon_proto_descriptor.py registry \
  tests/fixtures/user_descriptor_set.hex \
  tests/fixtures/user_descriptor_set_breaking.hex \
  --name demo-user-relaxed \
  --report generated/descriptor_registry_relaxed_report.md \
  --json-out generated/descriptor_registry_relaxed.json \
  --policy tests/fixtures/descriptor_registry_policy_relaxed.json \
  --junit-out generated/descriptor_registry_relaxed_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_relaxed_report.md
grep -Fq 'Base compatibility status: `FAIL`' generated/descriptor_registry_relaxed_report.md
grep -q 'maximum breaking adjacent changes' generated/descriptor_registry_relaxed_report.md
grep -q 'WARN' generated/descriptor_registry_relaxed_report.md
grep -q '"overall_status": "PASS"' generated/descriptor_registry_relaxed.json
grep -q '"base_status": "FAIL"' generated/descriptor_registry_relaxed.json
grep -q '"status": "WARN"' generated/descriptor_registry_relaxed.json
grep -q '<testsuite' generated/descriptor_registry_relaxed_report.xml
grep -q 'failures="0"' generated/descriptor_registry_relaxed_report.xml

python3 scripts/moon_proto_descriptor.py policy \
  generated/descriptor_registry_relaxed.json \
  tests/fixtures/descriptor_registry_policy_relaxed.json \
  --report generated/descriptor_policy_relaxed_report.md \
  --json-out generated/descriptor_policy_relaxed.json \
  --junit-out generated/descriptor_policy_relaxed_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_policy_relaxed_report.md
grep -q 'WARN' generated/descriptor_policy_relaxed_report.md
grep -q '"status": "PASS"' generated/descriptor_policy_relaxed.json
grep -q '"status": "WARN"' generated/descriptor_policy_relaxed.json
grep -q '<testsuite' generated/descriptor_policy_relaxed_report.xml
grep -q 'failures="0"' generated/descriptor_policy_relaxed_report.xml

python3 scripts/moon_proto_descriptor.py publish \
  generated/descriptor_registry.json \
  --store generated/schema_registry_store \
  --base-dir . \
  --report generated/descriptor_registry_publish_report.md \
  --json-out generated/descriptor_registry_published.json \
  --junit-out generated/descriptor_registry_publish_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_publish_report.md
grep -q 'artifact_path' generated/descriptor_registry_published.json
grep -q '<testsuite' generated/descriptor_registry_publish_report.xml
grep -q 'failures="0"' generated/descriptor_registry_publish_report.xml
test -f generated/schema_registry_store/registries/demo-user.json

python3 scripts/moon_proto_descriptor.py pull \
  generated/schema_registry_store/registries/demo-user.json \
  --output-dir generated/schema_registry_pull \
  --report generated/descriptor_registry_pull_report.md \
  --json-out generated/descriptor_registry_pulled.json \
  --junit-out generated/descriptor_registry_pull_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_pull_report.md
grep -q 'pulled_path' generated/descriptor_registry_pulled.json
grep -q '<testsuite' generated/descriptor_registry_pull_report.xml
grep -q 'failures="0"' generated/descriptor_registry_pull_report.xml
find generated/schema_registry_pull -type f | grep -q 'version_0_'

cat > generated/registry_http_server.py <<'PY'
import functools
import http.server
import pathlib
import socketserver
import sys

directory = sys.argv[1]
port_file = pathlib.Path(sys.argv[2])
token = sys.argv[3] if len(sys.argv) > 3 else ""

class AuthenticatedHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if token and self.headers.get("Authorization") != f"Bearer {token}":
            self.send_response(401)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"unauthorized")
            return
        super().do_GET()

    def do_PUT(self):
        if token and self.headers.get("Authorization") != f"Bearer {token}":
            self.send_response(401)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"unauthorized")
            return
        root = pathlib.Path(directory).resolve()
        target = (root / self.path.lstrip("/")).resolve()
        if root not in target.parents and target != root:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"invalid path")
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        length = int(self.headers.get("Content-Length", "0"))
        target.write_bytes(self.rfile.read(length))
        self.send_response(201)
        self.end_headers()
        self.wfile.write(b"created")

handler_class = AuthenticatedHandler
handler = functools.partial(handler_class, directory=directory)
with socketserver.TCPServer(("127.0.0.1", 0), handler) as httpd:
    port_file.write_text(str(httpd.server_address[1]), encoding="utf-8")
    httpd.serve_forever()
PY
python3 generated/registry_http_server.py generated/schema_registry_store generated/registry_http_port.txt > generated/registry_http.log 2>&1 &
HTTP_PID="$!"
for _ in $(seq 1 50); do
  if [ -s generated/registry_http_port.txt ]; then
    break
  fi
  sleep 0.1
done
test -s generated/registry_http_port.txt
REGISTRY_HTTP_PORT="$(cat generated/registry_http_port.txt)"
python3 scripts/moon_proto_descriptor.py pull \
  "http://127.0.0.1:${REGISTRY_HTTP_PORT}/registries/demo-user.json" \
  --output-dir generated/schema_registry_http_pull \
  --report generated/descriptor_registry_http_pull_report.md \
  --json-out generated/descriptor_registry_http_pulled.json \
  --junit-out generated/descriptor_registry_http_pull_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_http_pull_report.md
grep -q 'http://127.0.0.1' generated/descriptor_registry_http_pulled.json
grep -q '<testsuite' generated/descriptor_registry_http_pull_report.xml
grep -q 'failures="0"' generated/descriptor_registry_http_pull_report.xml
find generated/schema_registry_http_pull -type f | grep -q 'version_1_'
kill "$HTTP_PID" 2>/dev/null || true
wait "$HTTP_PID" 2>/dev/null || true
HTTP_PID=""

python3 generated/registry_http_server.py generated/schema_registry_store generated/registry_auth_http_port.txt moon-secret-token > generated/registry_auth_http.log 2>&1 &
HTTP_PID="$!"
for _ in $(seq 1 50); do
  if [ -s generated/registry_auth_http_port.txt ]; then
    break
  fi
  sleep 0.1
done
test -s generated/registry_auth_http_port.txt
REGISTRY_AUTH_HTTP_PORT="$(cat generated/registry_auth_http_port.txt)"
if python3 scripts/moon_proto_descriptor.py pull \
  "http://127.0.0.1:${REGISTRY_AUTH_HTTP_PORT}/registries/demo-user.json" \
  --output-dir generated/schema_registry_auth_missing_pull \
  --report generated/descriptor_registry_auth_missing_pull_report.md \
  --json-out generated/descriptor_registry_auth_missing_pulled.json \
  --junit-out generated/descriptor_registry_auth_missing_pull_report.xml; then
  echo "expected authenticated registry pull failure without token" >&2
  exit 1
fi
grep -Fq 'Overall status: **FAIL**' generated/descriptor_registry_auth_missing_pull_report.md
grep -q '<failure' generated/descriptor_registry_auth_missing_pull_report.xml

MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py pull \
  "http://127.0.0.1:${REGISTRY_AUTH_HTTP_PORT}/registries/demo-user.json" \
  --token-env MOON_PROTO_REGISTRY_TOKEN \
  --output-dir generated/schema_registry_auth_pull \
  --report generated/descriptor_registry_auth_pull_report.md \
  --json-out generated/descriptor_registry_auth_pulled.json \
  --junit-out generated/descriptor_registry_auth_pull_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_auth_pull_report.md
grep -q 'configure HTTP headers' generated/descriptor_registry_auth_pull_report.md
grep -q 'Authorization' generated/descriptor_registry_auth_pull_report.md
grep -q '<testsuite' generated/descriptor_registry_auth_pull_report.xml
grep -q 'failures="0"' generated/descriptor_registry_auth_pull_report.xml
find generated/schema_registry_auth_pull -type f | grep -q 'version_1_'
kill "$HTTP_PID" 2>/dev/null || true
wait "$HTTP_PID" 2>/dev/null || true
HTTP_PID=""

mkdir -p generated/schema_registry_hosted
python3 generated/registry_http_server.py generated/schema_registry_hosted generated/registry_push_http_port.txt moon-secret-token > generated/registry_push_http.log 2>&1 &
HTTP_PID="$!"
for _ in $(seq 1 50); do
  if [ -s generated/registry_push_http_port.txt ]; then
    break
  fi
  sleep 0.1
done
test -s generated/registry_push_http_port.txt
REGISTRY_PUSH_HTTP_PORT="$(cat generated/registry_push_http_port.txt)"
if python3 scripts/moon_proto_descriptor.py push \
  generated/schema_registry_store \
  --base-url "http://127.0.0.1:${REGISTRY_PUSH_HTTP_PORT}/" \
  --registry demo-user.json \
  --report generated/descriptor_registry_push_missing_report.md \
  --json-out generated/descriptor_registry_push_missing.json \
  --junit-out generated/descriptor_registry_push_missing.xml; then
  echo "expected authenticated registry push failure without token" >&2
  exit 1
fi
grep -Fq 'Overall status: **FAIL**' generated/descriptor_registry_push_missing_report.md
grep -q '<failure' generated/descriptor_registry_push_missing.xml

MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py push \
  generated/schema_registry_store \
  --base-url "http://127.0.0.1:${REGISTRY_PUSH_HTTP_PORT}/" \
  --registry demo-user.json \
  --token-env MOON_PROTO_REGISTRY_TOKEN \
  --report generated/descriptor_registry_push_report.md \
  --json-out generated/descriptor_registry_pushed.json \
  --junit-out generated/descriptor_registry_push_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_push_report.md
grep -q 'push registry manifest' generated/descriptor_registry_push_report.md
grep -q '"remote_base_url"' generated/descriptor_registry_pushed.json
grep -q '<testsuite' generated/descriptor_registry_push_report.xml
grep -q 'failures="0"' generated/descriptor_registry_push_report.xml
test -f generated/schema_registry_hosted/registries/demo-user.json
find generated/schema_registry_hosted/blobs -type f | grep -q '.hex'

MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py pull \
  "http://127.0.0.1:${REGISTRY_PUSH_HTTP_PORT}/registries/demo-user.json" \
  --token-env MOON_PROTO_REGISTRY_TOKEN \
  --output-dir generated/schema_registry_hosted_pull \
  --report generated/descriptor_registry_hosted_pull_report.md \
  --json-out generated/descriptor_registry_hosted_pulled.json \
  --junit-out generated/descriptor_registry_hosted_pull_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_hosted_pull_report.md
grep -q '<testsuite' generated/descriptor_registry_hosted_pull_report.xml
grep -q 'failures="0"' generated/descriptor_registry_hosted_pull_report.xml
find generated/schema_registry_hosted_pull -type f | grep -q 'version_1_'

cat > generated/registry_profiles.json <<EOF
{
  "profiles": {
    "local-hosted": {
      "base_url": "http://127.0.0.1:${REGISTRY_PUSH_HTTP_PORT}/",
      "registry": "demo-user.json",
      "token_env": "MOON_PROTO_REGISTRY_TOKEN",
      "headers": {
        "X-Registry-Client": "moon-proto-lab"
      }
    }
  }
}
EOF
MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py push \
  generated/schema_registry_store \
  --profile-file generated/registry_profiles.json \
  --profile local-hosted \
  --report generated/descriptor_registry_profile_push_report.md \
  --json-out generated/descriptor_registry_profile_pushed.json \
  --junit-out generated/descriptor_registry_profile_push_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_profile_push_report.md
grep -q 'load registry profile' generated/descriptor_registry_profile_push_report.md
grep -q 'X-Registry-Client' generated/descriptor_registry_profile_push_report.md
grep -q 'failures="0"' generated/descriptor_registry_profile_push_report.xml

MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py pull \
  registries/demo-user.json \
  --profile-file generated/registry_profiles.json \
  --profile local-hosted \
  --output-dir generated/schema_registry_profile_pull \
  --report generated/descriptor_registry_profile_pull_report.md \
  --json-out generated/descriptor_registry_profile_pulled.json \
  --junit-out generated/descriptor_registry_profile_pull_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_profile_pull_report.md
grep -q 'load registry profile' generated/descriptor_registry_profile_pull_report.md
grep -q 'http://127.0.0.1' generated/descriptor_registry_profile_pulled.json
grep -q 'failures="0"' generated/descriptor_registry_profile_pull_report.xml
find generated/schema_registry_profile_pull -type f | grep -q 'version_1_'
kill "$HTTP_PID" 2>/dev/null || true
wait "$HTTP_PID" 2>/dev/null || true
HTTP_PID=""

cat > generated/managed_registry_server.py <<'PY'
import base64
import hashlib
import http.server
import json
import pathlib
import socketserver
import sys
import urllib.parse

root = pathlib.Path(sys.argv[1]).resolve()
port_file = pathlib.Path(sys.argv[2])
token = sys.argv[3]

def safe_target(relative_path):
    target = (root / relative_path.lstrip("/")).resolve()
    if root not in target.parents and target != root:
        raise ValueError("invalid path")
    return target

def api_relative_path(request_path):
    parts = urllib.parse.urlparse(request_path).path.split("/")
    if len(parts) < 7 or parts[1] != "repos" or parts[4] != "contents":
        raise ValueError("expected /repos/<owner>/<repo>/contents/<path>")
    return "/".join(urllib.parse.unquote(part) for part in parts[5:])

class ManagedRegistryHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def require_auth(self):
        if self.headers.get("Authorization") == f"Bearer {token}":
            return True
        self.send_response(401)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"unauthorized")
        return False

    def write_json(self, status, payload):
        data = json.dumps(payload, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.require_auth():
            return
        try:
            if urllib.parse.urlparse(self.path).path.startswith("/repos/"):
                target = safe_target(api_relative_path(self.path))
                if not target.is_file():
                    self.write_json(404, {"message": "not found"})
                    return
                self.write_json(200, {"sha": hashlib.sha1(target.read_bytes()).hexdigest()})
                return
            target = safe_target(urllib.parse.unquote(urllib.parse.urlparse(self.path).path))
            if not target.is_file():
                self.send_response(404)
                self.end_headers()
                return
            data = target.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:
            self.write_json(400, {"message": str(exc)})

    def do_PUT(self):
        if not self.require_auth():
            return
        try:
            target = safe_target(api_relative_path(self.path))
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if target.exists() and not payload.get("sha"):
                self.write_json(409, {"message": "sha required for update"})
                return
            data = base64.b64decode(payload["content"])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            self.write_json(200 if payload.get("sha") else 201, {
                "content": {
                    "path": api_relative_path(self.path),
                    "sha": hashlib.sha1(data).hexdigest(),
                }
            })
        except Exception as exc:
            self.write_json(400, {"message": str(exc)})

with socketserver.TCPServer(("127.0.0.1", 0), ManagedRegistryHandler) as httpd:
    port_file.write_text(str(httpd.server_address[1]), encoding="utf-8")
    httpd.serve_forever()
PY
mkdir -p generated/schema_registry_managed
python3 generated/managed_registry_server.py generated/schema_registry_managed generated/registry_managed_http_port.txt moon-secret-token > generated/registry_managed_http.log 2>&1 &
HTTP_PID="$!"
for _ in $(seq 1 50); do
  if [ -s generated/registry_managed_http_port.txt ]; then
    break
  fi
  sleep 0.1
done
test -s generated/registry_managed_http_port.txt
REGISTRY_MANAGED_HTTP_PORT="$(cat generated/registry_managed_http_port.txt)"
cat > generated/registry_managed_profiles.json <<EOF
{
  "profiles": {
    "github-managed": {
      "backend": "github-contents",
      "api_base_url": "http://127.0.0.1:${REGISTRY_MANAGED_HTTP_PORT}/",
      "raw_base_url": "http://127.0.0.1:${REGISTRY_MANAGED_HTTP_PORT}/",
      "owner": "moonbit-community",
      "repo": "schema-registry",
      "branch": "main",
      "path": "moon-registry",
      "registry": "demo-user.json",
      "token_env": "MOON_PROTO_REGISTRY_TOKEN",
      "headers": {
        "X-Registry-Client": "moon-proto-lab"
      }
    }
  }
}
EOF
MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py push \
  generated/schema_registry_store \
  --profile-file generated/registry_managed_profiles.json \
  --profile github-managed \
  --report generated/descriptor_registry_managed_push_report.md \
  --json-out generated/descriptor_registry_managed_pushed.json \
  --junit-out generated/descriptor_registry_managed_push_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_managed_push_report.md
grep -q 'resolve registry backend' generated/descriptor_registry_managed_push_report.md
grep -q 'github-contents' generated/descriptor_registry_managed_push_report.md
grep -q '"remote_backend": "github-contents"' generated/descriptor_registry_managed_pushed.json
grep -q 'failures="0"' generated/descriptor_registry_managed_push_report.xml
test -f generated/schema_registry_managed/moon-registry/registries/demo-user.json
find generated/schema_registry_managed/moon-registry/blobs -type f | grep -q '.hex'

MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py push \
  generated/schema_registry_store \
  --profile-file generated/registry_managed_profiles.json \
  --profile github-managed \
  --report generated/descriptor_registry_managed_update_report.md \
  --json-out generated/descriptor_registry_managed_updated.json \
  --junit-out generated/descriptor_registry_managed_update_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_managed_update_report.md
grep -q 'failures="0"' generated/descriptor_registry_managed_update_report.xml

MOON_PROTO_REGISTRY_TOKEN=moon-secret-token python3 scripts/moon_proto_descriptor.py pull \
  registries/demo-user.json \
  --profile-file generated/registry_managed_profiles.json \
  --profile github-managed \
  --output-dir generated/schema_registry_managed_pull \
  --report generated/descriptor_registry_managed_pull_report.md \
  --json-out generated/descriptor_registry_managed_pulled.json \
  --junit-out generated/descriptor_registry_managed_pull_report.xml
grep -Fq 'Overall status: **PASS**' generated/descriptor_registry_managed_pull_report.md
grep -q 'resolve registry backend' generated/descriptor_registry_managed_pull_report.md
grep -q 'github-contents' generated/descriptor_registry_managed_pull_report.md
grep -q 'moon-registry' generated/descriptor_registry_managed_pulled.json
grep -q 'failures="0"' generated/descriptor_registry_managed_pull_report.xml
find generated/schema_registry_managed_pull -type f | grep -q 'version_1_'
kill "$HTTP_PID" 2>/dev/null || true
wait "$HTTP_PID" 2>/dev/null || true
HTTP_PID=""

echo "Generated MoonBit source compiles"
