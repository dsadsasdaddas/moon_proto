# Moon Proto Lab 项目申报书

## 基本信息

- **项目名称**：Moon Proto Lab：MoonBit protobuf 生态的动态 schema、兼容性测试与 AI 代码验证工具链
- **参赛者 / 队伍**：王越的战队（王越）
- **联系方式**：15372503381
- **GitHub 仓库链接**：https://github.com/dsadsasdaddas/moon_proto
- **Gitlink 仓库链接**：https://gitlink.org.cn/wangyue111/moon_proto
- **项目方向**：MoonBit 基础软件生态工具 / protobuf schema 验证、兼容性测试与代码生成辅助设施
- **是否为移植或参考项目**：参考 Protocol Buffers 公开标准与成熟实现，从零实现 MoonBit 动态 schema、测试 oracle 和代码生成实验工具；不直接重复已有 `moonbitlang/protobuf` / `protoc-gen-mbt` 的官方运行时定位。

## 项目简介

Moon Proto Lab 面向 MoonBit protobuf 生态，提供动态 `.proto` schema 解析、Schema Doctor 诊断、schema validation、动态 message 二进制/JSON 编解码、MoonBit 代码生成实验、AI verify 报告、old/new schema 兼容性检查、跨语言 oracle fixture 和生成代码可编译检查。项目不定位为官方 protobuf runtime 的替代品，而是作为 MoonBit protobuf 生态的验证与工具层，帮助开发者在云计算、边缘计算、WebAssembly 服务、AI agent 工具协议和多语言数据交换场景中更可靠地使用 protobuf。

项目特别关注 AI 时代的软件工程痛点：AI 可以快速生成 `.proto` schema 或 MoonBit 代码，但这些输出经常难以验证、难以维护。本项目通过 parser、validator、golden fixtures、Python/Go 官方 protobuf oracle、CI 和 generated-code compile check，把“看起来正确”的输出转化为可测试、可复现、可长期维护的工程资产。

## 与已有 MoonBit protobuf 项目的关系

提交前已检查 Mooncakes/MoonBit 生态，已有 `moonbitlang/protobuf`（https://mooncakes.io/docs/moonbitlang/protobuf）与 `moonbitlang/protoc-gen-mbt`（https://github.com/moonbitlang/protoc-gen-mbt）等 protobuf 相关项目。因此本项目做差异化定位：

- 不宣称替代官方 protobuf 包；
- 不把重点放在完整生产级 runtime 竞争上；
- 重点提供动态 schema lab、Schema Doctor、兼容性 fixture、AI verify 报告、schema 兼容性检查、JSON mapping 测试和 generated-code compile check；
- 后续可以作为官方 protobuf 包的 differential testing harness 或 schema/debugging 辅助工具。

## 当前已完成内容

项目已形成从 schema 子集解析到二进制编解码、动态 message runtime、JSON mapping、代码生成、CLI 包装和跨语言 oracle 测试的可验证闭环：

- protobuf wire type、key packing/parsing；
- UInt64 varint 编解码；
- zig-zag 有符号整数映射；
- fixed32/fixed64 小端编解码；
- length-delimited bytes/string 编解码；
- 常用字段编码 helper：uint64、bool、sint64、string、bytes；
- proto3 schema AST：message、field、label、scalar type、enum、named message、map type、oneof group；
- `.proto` lexer/parser 子集：syntax、点分 package、import、option、真实 reserved number/name descriptor、extensions、message、enum、optional/repeated、map、oneof、字段/枚举值 options、标量字段和点分 named type；
- schema validator 与 Schema Doctor：字段号范围、重复字段名/号、proto3 enum 首值为 0、顶层命名冲突、map key/value 约束、reserved number/name 复用检查，并输出稳定诊断路径；
- schema-driven 动态 message 编解码，覆盖标量、repeated、packed repeated、enum、nested message、map、oneof；
- 解码时跳过 unknown fields，便于向前/向后兼容；
- protobuf-style JSON writer/parser，支持标量、repeated、bytes base64、64-bit 整数字符串化、nested message、map object mapping、oneof 冲突拒绝；
- MoonBit 代码生成：根据 message/enum descriptor 生成 struct、enum、descriptor registry、encode/decode/JSON helper；
- `scripts/moon_proto_gen.py` 文件版生成入口：`python3 scripts/moon_proto_gen.py gen schema.proto -o generated/`；
- `scripts/moon_proto_lab.py doctor/inspect/compat/verify` 提供文件版 Schema Doctor、schema summary、old/new schema 兼容性检查、AI verify 与 Markdown/HTML 报告生成；
- `scripts/moon_proto_official_diff.py` 提供面向 `moonbitlang/protoc-gen-mbt` / `moonbitlang/protobuf` 的 differential harness manifest 与报告入口；
- `tests/codegen/compile_generated.sh` 实际生成 MoonBit 源码并执行 `moon check`，验证生成代码可编译；
- Python `google.protobuf` 与 Go `google.golang.org/protobuf` oracle fixtures，用于验证 scalar/repeated/map/oneof/32-bit numeric/float/double/special float golden bytes/JSON 与成熟生态一致；
- deterministic property-style tests 覆盖 varint、zig-zag、动态 message 二进制和 JSON roundtrip；
- GitHub Actions CI 覆盖 oracle、check、build、test、多 target、CLI smoke 和 generated-code compile check。

## 核心功能范围

1. **动态 schema lab**：解析 proto3 schema 子集，构建 MoonBit descriptor，支持开发者快速检查 schema 结构。
2. **Schema Doctor / schema validation**：检查字段号、重复定义、enum 规则、map 约束、oneof 冲突、reserved number/name 复用等常见错误，输出稳定诊断路径，适合验证 AI 生成 schema。
3. **动态 message runtime**：在不依赖生成 typed struct 的情况下，对 descriptor-driven message 进行二进制和 JSON roundtrip。
4. **兼容性 oracle 与官方生态对接**：使用 Python/Go 官方 protobuf 生成和验证 fixtures，并提供 MoonBit 官方 protobuf/protoc-gen-mbt differential harness，减少“实现能跑但不兼容”的风险。
5. **schema 兼容性检查**：比较 old/new `.proto`，发现字段号复用、字段类型变化、字段迁移、enum 值变化、package 变化、reserved 契约弱化或复用等破坏性修改。
6. **AI verify 报告**：一条命令完成 doctor、inspect、codegen、generated-code compile check，并输出 Markdown/HTML 报告。
7. **真实 schema 容错解析**：支持常见 import、option、reserved、field option 与点分类型，并把 reserved 升级为可验证的 schema/compat 契约，使工具能处理更接近生产项目的 `.proto`。
8. **代码生成实验**：生成 MoonBit struct、enum、descriptor 和 helper，并通过 compile check 保证生成结果可构建。
9. **工程化交付**：README、测试说明、开发报告、提交清单、official differential 文档、公开 GitHub/Gitlink 仓库和 CI。

## 为什么值得做

Protocol Buffers 是云计算、RPC、边缘通信和多语言系统中最常见的数据交换格式之一。MoonBit 面向 WebAssembly、云计算和边缘计算时，除了 runtime/codegen 本身，还需要可靠的验证工具、兼容性测试数据和 AI 协作下的质量保障机制。Moon Proto Lab 的价值在于把 protobuf 使用过程中的 schema、runtime、JSON、codegen 和 cross-language compatibility 串成一个可复现的验证闭环，补齐 MoonBit 生态中“工具链质量保障”和“AI 生成代码可验证性”的空白。

## 测试与质量保障

项目采用 verification-first 开发方式：每个 wire primitive 有 golden vector；每个 parser/codegen 能力有 snapshot 或 compile check；runtime 使用手写 golden bytes、roundtrip、negative tests 和 Python/Go 官方 oracle 共同验证。当前验证命令为：

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
tests/codegen/compile_generated.sh
```

## 许可证

本项目采用 MIT License。Protocol Buffers 为公开数据格式标准，本项目为 MoonBit 原生实现的验证与工具链项目。
