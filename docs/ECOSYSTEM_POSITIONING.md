# Moon Proto Lab ecosystem positioning

## Existing MoonBit protobuf ecosystem

The MoonBit ecosystem already contains protobuf-related work, including:

- `moonbitlang/protobuf`: protobuf support in the MoonBit package ecosystem (https://mooncakes.io/docs/moonbitlang/protobuf);
- `moonbitlang/protoc-gen-mbt`: MoonBit code generation around `protoc` (https://github.com/moonbitlang/protoc-gen-mbt).

Because of this, Moon Proto Lab is **not** positioned as a duplicate protobuf runtime or as a direct replacement for these packages.

## Independent value of this project

Moon Proto Lab focuses on the tooling and verification layer around protobuf development in MoonBit:

1. **Dynamic schema lab**
   - parse proto3 schema subsets;
   - build descriptors in MoonBit;
   - encode/decode dynamic messages without requiring generated typed structs first.

2. **AI-generated schema/code verification**
   - validate field numbers, duplicate names/numbers, enum invariants and map constraints;
   - reject invalid JSON or oneof conflicts;
   - compile-check generated MoonBit source instead of trusting text-only output;
   - generate Markdown/HTML verification reports for review and CI artifacts.

3. **Cross-language compatibility oracle**
   - compare MoonBit behavior with Python `google.protobuf`;
   - compare MoonBit behavior with Go `google.golang.org/protobuf`;
   - keep checked-in binary/hex/JSON fixtures for reproducibility.

4. **Conformance-lite corpus**
   - scalar values;
   - repeated fields;
   - packed repeated numeric fields;
   - bytes/base64 JSON mapping;
   - enum fields;
   - nested messages;
   - maps;
   - oneof groups.

5. **Future integration path**
   - add adapters that read schemas or generated descriptors from official MoonBit protobuf packages;
   - use this repository as a differential testing harness;
   - keep experimental dynamic tooling here while stable runtime/codegen can live in or interoperate with existing ecosystem packages.

## Contest positioning

The contest encourages useful MoonBit open-source infrastructure and explicitly mentions that AI-generated code can be hard to verify and maintain. Moon Proto Lab addresses that problem directly:

- `.proto` schemas can be parsed and checked;
- dynamic messages can be encoded/decoded and compared against mature language ecosystems;
- generated MoonBit code is built in CI;
- Schema Doctor and verify reports expose diagnostics as reviewable artifacts;
- documentation and fixtures make behavior reproducible.

Therefore the project should be submitted as:

> Moon Proto Lab: MoonBit protobuf 生态的动态 schema、兼容性测试与 AI 代码验证工具链。

This positioning avoids overlap with existing mature protobuf packages while preserving the practical value of the code already implemented in this repository.
