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

echo "Generated MoonBit source compiles"
