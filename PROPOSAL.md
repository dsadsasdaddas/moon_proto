# Moon Proto 项目申报书

## 基本信息

- **项目名称**：Moon Proto：面向 MoonBit 的 proto3 Protocol Buffers 编解码与代码生成工具链
- **参赛者 / 队伍**：王越的战队（王越）
- **联系方式**：15372503381
- **GitHub 仓库链接**：https://github.com/dsadsasdaddas/moon_proto
- **Gitlink 仓库链接**：https://gitlink.org.cn/wangyue111/moon_proto
- **项目方向**：MoonBit 基础序列化工具 / 云与边缘计算数据交换基础设施
- **是否为移植或参考项目**：参考成熟标准 Protocol Buffers，从零实现 MoonBit 运行时与工具链

## 项目简介

Moon Proto 计划为 MoonBit 生态补齐 Protocol Buffers 基础能力，使 MoonBit 程序能够按照 `.proto` schema 高效读写标准 protobuf 二进制数据，并逐步提供 MoonBit 类型代码生成、JSON mapping 和跨语言兼容性测试。项目面向 WebAssembly 服务、云边协同、RPC-like 协议、数据文件交换、AI agent 工具协议等场景，强调标准兼容、强测试、可维护和可复用。

## 当前已完成内容

项目已形成从 schema 子集解析到二进制编解码、动态 message runtime、代码生成雏形的可验证闭环：

- protobuf wire type、key packing/parsing；
- UInt64 varint 编解码；
- zig-zag 有符号整数映射；
- fixed32/fixed64 小端编解码；
- length-delimited bytes/string 编解码；
- 常用字段编码 helper：uint64、bool、sint64、string、bytes；
- schema-driven 动态 message 编解码，覆盖 uint64、bool、sint64、string、bytes 等常见字段；
- repeated 字段编码与解码聚合；
- proto3 数值型 repeated 字段 packed 编码/解码；
- 解码时跳过 unknown fields，便于向前/向后兼容；
- protobuf-style JSON writer/parser，支持标量、repeated、bytes base64、64-bit 整数字符串化；
- proto3 schema AST，覆盖 message、field、top-level enum；
- proto3 map 字段支持：解析 `map<K,V>`、动态二进制编解码、JSON object mapping、schema key/value 校验；
- proto3 oneof 字段支持：解析 oneof block、生成 oneof descriptor、编码前冲突校验、二进制解码 last-one-wins 语义、JSON 冲突拒绝；
- `.proto` lexer/parser 子集：syntax、package、message、enum、optional/repeated、map、oneof、标量字段；
- MoonBit 代码生成雏形：根据 message/enum descriptor 生成 struct、enum 与 descriptor 函数；
- enum 字段解析后会解析为 varint runtime 类型，支持二进制与 JSON 数值 roundtrip；
- schema validator 可检查字段号范围、重复字段名/号、proto3 enum 首值为 0、顶层命名冲突等问题，增强 AI 生成 schema/codegen 的可验证性；
- descriptor registry 支持 message-valued nested field 的二进制与 JSON roundtrip；
- codegen 默认生成 message descriptor registry 与 encode/decode/JSON helper，并提供 `moon run cmd/main -- gen --example` CLI smoke 入口；
- `scripts/moon_proto_gen.py` 提供文件版生成入口，可执行 `python3 scripts/moon_proto_gen.py gen schema.proto -o generated/`；
- `tests/codegen/compile_generated.sh` 会实际生成 MoonBit 源码并执行 `moon check`，验证生成代码可编译；
- 官方 Python `google.protobuf` 与 Go `google.golang.org/protobuf` oracle fixtures，用于验证 MoonBit scalar/repeated/map/oneof golden bytes/JSON 与成熟生态一致；
- deterministic property-style tests 批量覆盖 varint、zig-zag、动态 message 二进制和 JSON roundtrip；
- golden tests 覆盖 varint 向量、field bytes、schema parser、动态 message roundtrip、unknown field、packed repeated、map、oneof、codegen 快照、JSON 转义/输出/解析、enum parser/codegen、Python/Go oracle 兼容样例。

## 核心功能规划

1. **Runtime 编解码**：支持 varint、fixed32、fixed64、length-delimited、zig-zag、repeated、packed repeated、map、oneof、unknown field preservation。
2. **Schema Parser**：解析 proto3 message、enum、nested message、oneof、import、option 的可用子集。
3. **MoonBit 代码生成**：根据 `.proto` 生成 struct、enum、encode/decode、JSON mapping。
4. **跨语言兼容测试**：使用 Python/Go protobuf 作为 oracle，验证 MoonBit 编码输出可被其他语言读取，其他语言输出可被 MoonBit 读取。
5. **CLI 工具**：提供文件版 `python3 scripts/moon_proto_gen.py gen user.proto -o generated/` 与示例工程。

## 为什么值得做

Protocol Buffers 是云计算、RPC、边缘通信和多语言系统中最常见的数据交换格式之一。MoonBit 面向 WebAssembly、云计算和边缘计算时，需要标准、紧凑、强类型、可验证的序列化基础设施。Moon Proto 可作为 MoonBit 生态中的底层基础库，服务后续网络协议、数据库绑定、AI 工具协议和跨语言互操作。

## 测试与质量保障

项目采用测试驱动开发：每个 wire primitive 均有 golden vector；每个新增 schema 能力均有 parser 或 codegen 快照测试；runtime 使用手写 protobuf golden bytes 与 roundtrip 测试；当前验证命令为 `moon check && moon build && moon test && moon test --target all`，覆盖 wasm、wasm-gc、js、native target。后续跨语言兼容由 Python/Go 官方 protobuf 生成 fixtures 作为 oracle。

## 许可证

本项目采用 MIT License。Protocol Buffers 为公开数据格式标准，本项目为 MoonBit 原生实现。
