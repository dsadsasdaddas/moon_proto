# Moon Proto Lab 提交清单

本清单用于比赛申报/验收时快速核对仓库、文档、测试和交付物状态。

## 仓库信息

| 项目 | 状态 |
| --- | --- |
| GitHub | https://github.com/dsadsasdaddas/moon_proto |
| Gitlink | https://gitlink.org.cn/wangyue111/moon_proto |
| 默认分支 | GitHub `main` / Gitlink `master` |
| 最新同步提交 | 以仓库当前 HEAD 为准；GitHub/Gitlink 推送后通过 `git ls-remote` 核对 |
| 许可证 | MIT |
| 项目名称 | Moon Proto Lab |
| 项目方向 | MoonBit protobuf 生态工具 / 动态 schema、兼容性测试与 AI 代码验证 |
| 差异化说明 | 不替代 `moonbitlang/protobuf` / `protoc-gen-mbt`，重点做验证、fixtures、动态调试与生成代码可编译检查 |

## 代码与规模

| 要求 | 证据 |
| --- | --- |
| MoonBit 为主要实现语言 | `*.mbt` runtime/parser/codegen/tests 共 15 个源文件 |
| 项目规模 4k+ MoonBit LOC | 当前 MoonBit 源码约 `4945` 行 |
| 清晰工程结构 | wire/schema/runtime/json/codegen/cli/tests/docs 分层 |
| 示例 schema | `examples/simple/user.proto` |
| 文件版生成入口 | `scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/` |
| 生态定位说明 | `docs/ECOSYSTEM_POSITIONING.md` |

## 核心能力

- protobuf wire type、key packing/parsing；
- varint、zig-zag、fixed32/fixed64、length-delimited bytes/string；
- proto3 schema parser 和 descriptor model；
- schema validation diagnostics；
- descriptor-driven dynamic message binary encode/decode；
- repeated 与 proto3 packed repeated；
- unknown field skipping；
- enum parser/codegen/runtime/JSON；
- nested message descriptor registry；
- proto3 map parser/runtime/JSON/validation；
- proto3 oneof parser/codegen/runtime/JSON conflict handling；
- protobuf-style JSON writer/parser；
- MoonBit source code generator；
- file-based generator wrapper；
- Python/Go official protobuf oracle fixtures；
- generated-code compile check，适合验证 AI 生成代码。

## 测试与 CI

| 检查 | 状态 |
| --- | --- |
| Python oracle | `python3 tests/oracle/python_protobuf_oracle.py` |
| Go oracle | `(cd tests/oracle && go run .)` |
| MoonBit check | `moon check` |
| MoonBit build | `moon build` |
| MoonBit tests | `moon test`，当前 `36/36 passed` |
| All targets | `moon test --target all` 覆盖 wasm/wasm-gc/js/native |
| CLI smoke | `moon run cmd/main -- gen --example` |
| File-based generator | `python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/` |
| Generated code compile | `tests/codegen/compile_generated.sh` |
| GitHub Actions | GitHub Actions 最新 main 分支 CI 需为 success：https://github.com/dsadsasdaddas/moon_proto/actions |

## 文档与交付物

| 交付物 | 路径 |
| --- | --- |
| README | `README.md` |
| 生态定位说明 | `docs/ECOSYSTEM_POSITIONING.md` |
| 测试说明 | `docs/TESTING.md` |
| 开发报告 | `docs/DEVELOPMENT_REPORT.md` |
| 提交清单 | `docs/SUBMISSION_CHECKLIST.md` |
| 项目申报书 Markdown | `PROPOSAL.md` |
| 项目申报书 PDF | `output/pdf/MoonProto_王越的战队_项目申报书.pdf` |
| CI workflow | `.github/workflows/ci.yml` |

## 可复现命令

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
