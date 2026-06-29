# Moon Proto 开发报告

## 1. 项目概述

Moon Proto 是面向 MoonBit 生态的 proto3 Protocol Buffers 编解码与代码生成工具链。项目目标是提供一套可复用、可测试、可持续维护的基础序列化能力，使 MoonBit 程序能够围绕 `.proto` schema 进行二进制数据交换、JSON mapping、动态 message 编解码和 MoonBit 源码生成。

仓库地址：

- GitHub: https://github.com/dsadsasdaddas/moon_proto
- Gitlink: https://gitlink.org.cn/wangyue111/moon_proto

## 2. 当前完成范围

当前版本已经形成从 schema 解析、动态 runtime、代码生成、CLI 包装到跨语言 oracle 测试的闭环：

- protobuf wire model：`Varint`、`Fixed32`、`Fixed64`、`LengthDelimited`；
- key packing/parsing：`(field_number << 3) | wire_type`；
- UInt64 varint 编解码；
- zig-zag signed integer mapping；
- fixed32/fixed64 little-endian helper；
- length-delimited bytes/string helper；
- descriptor-driven dynamic message encode/decode；
- repeated fields 与 proto3 packed repeated numeric fields；
- unknown field skipping；
- enum parser/codegen/runtime/JSON 数值映射；
- nested message descriptor registry 与二进制/JSON roundtrip；
- proto3 map parser、runtime、JSON object mapping、schema validation；
- proto3 oneof parser、codegen、encode-time conflict rejection、binary last-one-wins decode、JSON conflict rejection；
- protobuf-style JSON writer/parser，覆盖 bytes base64、64-bit integer string form、repeated/map/nested/oneof；
- MoonBit codegen：生成 struct、enum、descriptor function、message registry、encode/decode/JSON helper；
- file-based generator wrapper：`python3 scripts/moon_proto_gen.py gen schema.proto -o generated/`；
- Python/Go 官方 protobuf oracle fixtures，用于验证 scalar/repeated/map/oneof golden bytes 与 JSON 兼容性。

## 3. 工程结构

```text
.
├── bytes.mbt / varint.mbt / fixed.mbt / zigzag.mbt / wire.mbt
│   └── wire primitive 与基础编码能力
├── schema.mbt / parser.mbt / validation.mbt
│   └── proto3 schema model、lexer/parser、schema diagnostics
├── field.mbt / runtime.mbt / json.mbt
│   └── dynamic message value、binary runtime、protobuf-style JSON mapping
├── codegen.mbt
│   └── MoonBit source generator
├── cmd/main/
│   └── MoonBit CLI smoke generator
├── scripts/moon_proto_gen.py
│   └── file-based .proto → .mbt generator wrapper
├── tests/oracle/
│   └── Python / Go official protobuf oracle scripts
├── tests/fixtures/
│   └── checked-in golden binary/hex/JSON fixtures
├── tests/codegen/compile_generated.sh
│   └── generated code compile check and file-based CLI test
└── docs/
    ├── TESTING.md
    └── DEVELOPMENT_REPORT.md
```

## 4. 测试与质量保障

项目采用 verification-first 策略。每个新增能力都至少配套以下一种验证：

- golden bytes：手写或官方 protobuf 生成的二进制结果；
- roundtrip：encode → decode、JSON encode → JSON decode；
- parser/codegen snapshot：验证 `.proto` 输入产生稳定 AST 和 MoonBit 源码；
- negative tests：验证错误输入、类型不匹配、oneof 冲突、非法 map key 等被拒绝；
- cross-language oracle：Python `google.protobuf` 与 Go `google.golang.org/protobuf`；
- generated-code compile check：实际生成 `.mbt` 文件并执行 `moon check`；
- CI：GitHub Actions 自动执行完整检查矩阵。

当前核心验证命令：

```bash
python3 tests/oracle/python_protobuf_oracle.py
(cd tests/oracle && go run .)
moon check
moon build
moon test
moon test --target all
moon run cmd/main -- gen --example
python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/
tests/codegen/compile_generated.sh
```

最近一次本地/远端验证结果：

- MoonBit tests: `36/36 passed`；
- `moon test --target all`: wasm、wasm-gc、js、native 全通过；
- generated-code compile check 通过；
- GitHub Actions CI 通过。

## 5. 跨语言兼容 fixtures

`tests/fixtures/` 当前包含三类官方 oracle fixtures：

| Fixture | 覆盖能力 |
| --- | --- |
| `user_full.*` | scalar、bytes、repeated、packed repeated、JSON 64-bit string form |
| `bag_maps.*` | proto3 map binary encoding 与 JSON object mapping |
| `contact_oneof.*` | oneof binary/JSON 输出 |

Python 与 Go oracle 均会重新构造官方 protobuf descriptors，并验证 checked-in binary/hex/JSON 文件未漂移。

## 6. AI 协作与可维护性实践

本项目适合 AI 协作开发，但每次 AI 生成或修改代码后都通过确定性验证收口：

- 使用小步提交，每个提交对应一个可解释能力；
- 对 parser/runtime/codegen 的行为使用 snapshot/golden tests 锁定；
- 对二进制格式使用跨语言 oracle 降低“看起来可用但不兼容”的风险；
- 对 schema validation 与 JSON parser 加 negative tests，减少 silent failure；
- 文档、申报 PDF、README、CI 同步更新，避免代码能力和项目说明脱节。

## 7. 已知边界与后续方向

当前项目定位为 MoonBit proto3 toolkit 的可用 MVP，不直接宣称完整替代官方 protobuf 全量实现。后续可继续扩展：

- import/option/reserved 等 schema 子集；
- proto descriptor set / reflection 兼容；
- 更完整的 float/double JSON 与 binary 支持；
- conformance suite 子集接入；
- 原生 MoonBit file IO 稳定后，将 Python wrapper 下沉为纯 MoonBit CLI；
- 更强的 typed struct encode/decode 生成，而不只依赖 dynamic `MessageValue` helper。

## 8. 验收交付物

- 公开 GitHub 仓库；
- 公开 Gitlink 仓库；
- MoonBit 源码与测试；
- README 使用说明；
- `docs/TESTING.md` 测试说明；
- `docs/DEVELOPMENT_REPORT.md` 开发报告；
- GitHub Actions CI；
- 申报 PDF：`output/pdf/MoonProto_王越的战队_项目申报书.pdf`。
