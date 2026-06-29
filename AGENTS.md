# moon_proto Agent Guide

This repository is a MoonBit implementation of a proto3 Protocol Buffers runtime/parser/codegen toolkit.

## Commands

Use the Linux server MoonBit toolchain when local `moon` is unavailable:

```bash
moon check && moon build && moon test
moon test --target all
```

## Development rules

- Keep the project verification-first: add golden or cross-language tests before expanding runtime scope.
- Stage 1 supports a focused proto3 subset; do not claim full protobuf compatibility until conformance tests exist.
- Keep generated-code work separate from runtime primitives.
- Prefer small focused commits: runtime primitive, parser feature, tests, docs.
