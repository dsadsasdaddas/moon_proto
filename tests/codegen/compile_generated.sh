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
grep -q 'official protoc-gen-mbt' generated/official_diff_report.md
grep -q 'SKIP' generated/official_diff_report.md
grep -q '<testsuite' generated/official_diff_report.xml
grep -q 'failures="0"' generated/official_diff_report.xml
grep -q '<skipped' generated/official_diff_report.xml

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
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
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

echo "Generated MoonBit source compiles"
