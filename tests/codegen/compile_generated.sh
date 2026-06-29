#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/moon_proto_codegen_check_$$"
cleanup() {
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
  --report generated/compat_report.md
grep -q 'schema compatible' generated/compat_report.md
grep -Fq 'Overall status: **PASS**' generated/compat_report.md

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
  --report generated/verify_report.md
grep -Fq 'Overall status: **PASS**' generated/verify_report.md
grep -q 'Generated MoonBit source preview' generated/verify_report.md

python3 scripts/moon_proto_lab.py verify examples/simple/user.proto \
  --report generated/verify_report.html --skip-compile
grep -q '<!doctype html>' generated/verify_report.html
grep -q 'Moon Proto Lab verification report' generated/verify_report.html

python3 scripts/moon_proto_official_diff.py \
  --report generated/official_diff_report.md
grep -Fq 'Overall status: **PASS**' generated/official_diff_report.md
grep -q 'official protoc-gen-mbt' generated/official_diff_report.md
grep -q 'SKIP' generated/official_diff_report.md

echo "Generated MoonBit source compiles"
