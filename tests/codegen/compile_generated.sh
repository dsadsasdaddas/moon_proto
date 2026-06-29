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

python3 scripts/moon_proto_gen.py gen examples/simple/user.proto --stdout --quiet \
  | grep -q 'pub fn decode_User'

echo "Generated MoonBit source compiles"
