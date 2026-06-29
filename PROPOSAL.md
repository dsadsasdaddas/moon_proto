# Moon Proto 项目申报书

## 基本信息

- **项目名称**：Moon Proto：面向 MoonBit 的 proto3 Protocol Buffers 编解码与代码生成工具链
- **参赛者**：王月
- **联系方式**：待填写
- **GitHub 仓库链接**：https://github.com/dsadsasdaddas/moon_proto
- **Gitlink 仓库链接**：https://gitlink.org.cn/wangyue111/moon_proto
- **项目方向**：MoonBit 基础序列化工具 / 云与边缘计算数据交换基础设施
- **是否为移植或参考项目**：参考成熟标准 Protocol Buffers，从零实现 MoonBit 运行时与工具链

## 项目简介

Moon Proto 计划为 MoonBit 生态补齐 Protocol Buffers 基础能力，使 MoonBit 程序能够按照 `.proto` schema 高效读写标准 protobuf 二进制数据，并逐步提供 MoonBit 类型代码生成、JSON mapping 和跨语言兼容性测试。项目面向 WebAssembly 服务、云边协同、RPC-like 协议、数据文件交换、AI agent 工具协议等场景，强调标准兼容、强测试、可维护和可复用。

## 第一阶段已完成内容

第一阶段聚焦最小可验证闭环：

- protobuf wire type、key packing/parsing；
- UInt64 varint 编解码；
- zig-zag 有符号整数映射；
- fixed32/fixed64 小端编解码；
- length-delimited bytes/string 编解码；
- 常用字段编码 helper：uint64、bool、sint64、string、bytes；
- proto3 schema AST；
- `.proto` lexer/parser 子集：syntax、package、message、optional/repeated、标量字段；
- golden tests 覆盖官方常见 varint 向量、field bytes、schema parser。

## 核心功能规划

1. **Runtime 编解码**：支持 varint、fixed32、fixed64、length-delimited、zig-zag、repeated、packed repeated、map、unknown field preservation。
2. **Schema Parser**：解析 proto3 message、enum、nested message、oneof、import、option 的可用子集。
3. **MoonBit 代码生成**：根据 `.proto` 生成 struct、enum、encode/decode、JSON mapping。
4. **跨语言兼容测试**：使用 Python/Go protobuf 作为 oracle，验证 MoonBit 编码输出可被其他语言读取，其他语言输出可被 MoonBit 读取。
5. **CLI 工具**：提供 `moon_proto gen user.proto -o generated/` 与示例工程。

## 为什么值得做

Protocol Buffers 是云计算、RPC、边缘通信和多语言系统中最常见的数据交换格式之一。MoonBit 面向 WebAssembly、云计算和边缘计算时，需要标准、紧凑、强类型、可验证的序列化基础设施。Moon Proto 可作为 MoonBit 生态中的底层基础库，服务后续网络协议、数据库绑定、AI 工具协议和跨语言互操作。

## 测试与质量保障

项目采用测试驱动开发：每个 wire primitive 均有 golden vector；每个新增 schema 能力均有 parser 快照测试；后续代码生成会使用 `moon check && moon test` 验证生成代码；跨语言兼容由 Python/Go 官方 protobuf 生成 fixtures 作为 oracle。

## 许可证

本项目采用 MIT License。Protocol Buffers 为公开数据格式标准，本项目为 MoonBit 原生实现。
