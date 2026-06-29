# Moon Proto Lab 开发报告

## 1. 项目概述

Moon Proto Lab 是面向 MoonBit protobuf 生态的动态 schema、兼容性测试与 AI 代码验证工具链。项目目标不是重复已有官方 protobuf runtime，而是提供一套可复用、可测试、可持续维护的验证基础设施：解析 `.proto` schema，构建 MoonBit descriptor，执行 Schema Doctor 诊断、动态 message 二进制/JSON roundtrip，生成 MoonBit 代码实验产物，输出 old/new schema 兼容性检查、AI verify Markdown/HTML 报告，并使用 Python/Go 官方 protobuf 作为 cross-language oracle。

仓库地址：

- GitHub: https://github.com/dsadsasdaddas/moon_proto
- Gitlink: https://gitlink.org.cn/wangyue111/moon_proto

## 2. 与已有生态的关系

提交前已检查 MoonBit/Mooncakes 生态，已有 `moonbitlang/protobuf`（https://mooncakes.io/docs/moonbitlang/protobuf）和 `moonbitlang/protoc-gen-mbt`（https://github.com/moonbitlang/protoc-gen-mbt）等 protobuf 相关项目。因此本项目做明确差异化：

- 不宣称替代已有 protobuf 包；
- 不把主要卖点放在完整生产级 runtime 竞争上；
- 重点提供动态 schema lab、Schema Doctor、schema validation、compatibility fixtures、protobuf JSON mapping 检查、schema 兼容性检查、AI verify 报告、generated-code compile check 和 AI 生成代码验证；
- 后续可以作为官方 protobuf 包的 differential testing harness、schema 调试器或 conformance-lite 数据源。

这个定位更贴合比赛关于 MoonBit 开源生态建设和 AI 时代代码可验证性的要求。

## 3. 当前完成范围

当前版本已经形成从 schema 解析、动态 runtime、JSON mapping、代码生成、CLI 包装到跨语言 oracle 测试的闭环：

- protobuf wire model：`Varint`、`Fixed32`、`Fixed64`、`LengthDelimited`；
- key packing/parsing：`(field_number << 3) | wire_type`；
- UInt64 varint 编解码；
- zig-zag signed integer mapping；
- fixed32/fixed64 little-endian helper；
- length-delimited bytes/string helper；
- proto3 schema model：message、field、label、scalar type、enum、named message、map、oneof；
- `.proto` lexer/parser：syntax、点分 package、import、option、真实 reserved number/name descriptor、extensions、message、enum、optional/repeated、map、oneof、字段/枚举值 options、标量字段和点分 named type；
- schema validation diagnostics 与 Schema Doctor CLI：字段号范围、重复字段名/号、proto3 enum 首值、顶层命名冲突、map 约束、reserved number/name 复用检查，输出稳定诊断路径；
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
- file-based lab CLI：`python3 scripts/moon_proto_lab.py doctor/inspect/compat/verify schema.proto --report report.md`；
- official differential harness：`python3 scripts/moon_proto_official_diff.py --report generated/official_diff_report.md`，并在 CI 中克隆 `moonbitlang/protoc-gen-mbt` 校验官方源码/文档契约；
- descriptor/reflection bridge：`python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md`；
- descriptor-set compatibility：`python3 scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md`，覆盖新增字段、removed-but-reserved 与破坏性类型变化报告；
- Python/Go 官方 protobuf oracle fixtures，用于验证 scalar/repeated/map/oneof/32-bit numeric/float/double/special float golden bytes 与 JSON 兼容性。

## 4. 工程结构

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
│   └── MoonBit CLI smoke generator, doctor and inspect commands
├── scripts/moon_proto_gen.py / scripts/moon_proto_lab.py / scripts/moon_proto_official_diff.py / scripts/moon_proto_descriptor.py
│   └── file-based generator, Schema Doctor, compatibility checks, AI verify, official differential and descriptor reports
├── tests/oracle/
│   └── Python / Go official protobuf oracle scripts
├── tests/fixtures/
│   └── checked-in golden binary/hex/JSON fixtures
├── tests/codegen/compile_generated.sh
│   └── generated code compile check and file-based CLI test
└── docs/
    ├── ECOSYSTEM_POSITIONING.md
    ├── TESTING.md
    ├── DEVELOPMENT_REPORT.md
    └── SUBMISSION_CHECKLIST.md
```

## 5. 测试与质量保障

项目采用 verification-first 策略。每个新增能力都至少配套以下一种验证：

- golden bytes：手写或官方 protobuf 生成的二进制结果；
- roundtrip：encode -> decode、JSON encode -> JSON decode；
- parser/codegen snapshot：验证 `.proto` 输入产生稳定 AST 和 MoonBit 源码；
- negative tests：验证错误输入、类型不匹配、oneof 冲突、非法 map key 等被拒绝；
- cross-language oracle：Python `google.protobuf` 与 Go `google.golang.org/protobuf`；
- generated-code compile check：实际生成 `.mbt` 文件并执行 `moon check`；
- AI verify report：生成 Markdown/HTML 报告，记录 doctor、inspect、codegen 和 compile 结果；
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
python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry.proto
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md
python3 scripts/moon_proto_official_diff.py --report generated/official_diff_report.md
python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md
python3 scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md
tests/codegen/compile_generated.sh
```

最近一次验证结果：

- MoonBit tests: `42/42 passed`；
- `moon test --target all`: wasm、wasm-gc、js、native 全通过；
- generated-code compile check 通过；
- Schema Doctor、AI verify report、official differential report、descriptor verify/compat report 与 CI 官方源码契约检查通过；
- GitHub Actions CI 通过。

## 6. 跨语言兼容 fixtures

`tests/fixtures/` 当前包含三类官方 oracle fixtures：

| Fixture | 覆盖能力 |
| --- | --- |
| `user_full.*` | scalar、bytes、repeated、packed repeated、JSON 64-bit string form |
| `bag_maps.*` | proto3 map binary encoding 与 JSON object mapping |
| `contact_oneof.*` | oneof binary/JSON 输出 |
| `numbers32.*` | uint32、int32、sint32、fixed32、sfixed32 边界值 binary/JSON 输出 |
| `floats.*` | float、double binary/JSON 输出 |
| `float_specials.*` | float/double NaN、Infinity、-Infinity protobuf JSON 字符串语义 |

Python 与 Go oracle 均会重新构造官方 protobuf descriptors，并验证 checked-in binary/hex/JSON 文件未漂移。

## 7. AI 协作与可维护性实践

本项目适合 AI 协作开发，但每次 AI 生成或修改代码后都通过确定性验证收口：

- 使用小步提交，每个提交对应一个可解释能力；
- 对 parser/runtime/codegen 的行为使用 snapshot/golden tests 锁定；
- 对二进制格式使用跨语言 oracle 降低“看起来可用但不兼容”的风险；
- 对 schema validation 与 JSON parser 加 negative tests，减少 silent failure；
- 对生成代码执行真实 `moon check`，验证 AI 生成代码不只是在文本层面像 MoonBit；
- `verify --report` 将 doctor、schema summary、codegen 和 compile check 汇总为 Markdown/HTML，便于代码审查和比赛展示；
- 文档、申报 PDF、README、CI 同步更新，避免代码能力和项目说明脱节。

## 8. 已知边界与后续方向

当前项目定位为 MoonBit protobuf ecosystem lab 的可用 MVP，不直接宣称完整替代官方 protobuf 全量实现。后续可继续扩展：

- 在官方仓库依赖图可解析且安装 `protoc` 的环境中执行更深的 official generator differential tests；
- schema registry imports and richer descriptor-set registry workflows；
- 更完整的 conformance-lite 语料和官方 MoonBit protobuf differential tests；
- conformance suite 子集接入；
- schema 兼容性对比继续扩展到更多 reserved/enum 迁移策略；
- 原生 MoonBit file IO 稳定后，将 Python wrapper 下沉为纯 MoonBit CLI；
- 更强的 typed struct encode/decode 生成，而不只依赖 dynamic `MessageValue` helper。

## 9. 验收交付物

- 公开 GitHub 仓库；
- 公开 Gitlink 仓库；
- MoonBit 源码与测试；
- README 使用说明；
- `docs/ECOSYSTEM_POSITIONING.md` 生态定位说明；
- `docs/SCHEMA_DOCTOR.md` Schema Doctor 与 verify 报告说明；
- `docs/OFFICIAL_DIFFERENTIAL.md` 官方 MoonBit protobuf differential harness 说明；
- `docs/DESCRIPTOR_SET.md` FileDescriptorSet / reflection bridge 与 descriptor compatibility 说明；
- `docs/TESTING.md` 测试说明；
- `docs/DEVELOPMENT_REPORT.md` 开发报告；
- `docs/SUBMISSION_CHECKLIST.md` 提交清单；
- GitHub Actions CI；
- 申报 PDF：`output/pdf/MoonProto_王越的战队_项目申报书.pdf`。
