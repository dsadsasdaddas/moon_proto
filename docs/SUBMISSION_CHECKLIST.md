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
| 项目规模 4k+ MoonBit LOC | 当前 MoonBit 源码约 `6663` 行 |
| 清晰工程结构 | wire/schema/runtime/json/codegen/cli/tests/docs 分层 |
| 示例 schema | `examples/simple/user.proto`、`examples/decorated/telemetry.proto` |
| 文件版生成入口 | `scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/` |
| Schema Doctor / compat / verify / official diff / conformance-lite / descriptor verify/compat/registry/policy | `scripts/moon_proto_lab.py doctor examples/simple/user.proto` / `compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md` / `verify --report generated/verify_report.md` / `scripts/moon_proto_official_diff.py --report generated/official_diff_report.md --junit-out generated/official_diff_report.xml` / `scripts/moon_proto_official_diff.py --run-official-generator --official-plugin-bin protoc-gen-mbt --protoc-bin protoc --report generated/official_installed_plugin_diff_report.md --junit-out generated/official_installed_plugin_diff_report.xml` / `scripts/moon_proto_conformance.py --report generated/conformance_lite_report.md --json-out generated/conformance_lite.json --junit-out generated/conformance_lite.xml` / `scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md` / `scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md` / `scripts/moon_proto_descriptor.py registry tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --name demo-user --report generated/descriptor_registry_report.md --json-out generated/descriptor_registry.json` |
| 生态定位说明 | `docs/ECOSYSTEM_POSITIONING.md` |

## 核心能力

- protobuf wire type、key packing/parsing；
- varint、zig-zag、fixed32/fixed64、length-delimited bytes/string；
- proto3 schema parser 和 descriptor model，支持点分 package/type、import、option、真实 reserved number/name descriptor、extensions 与字段/枚举值 option 容错解析；
- schema validation diagnostics，包含 reserved number/name 复用检查；
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
- Schema Doctor CLI；
- old/new schema compatibility checker，包含 removed-but-reserved 与 reserved 契约保留检查；
- official MoonBit protobuf differential harness manifest/report、CI source-contract check、预生成官方输出 contract check 与 installed-plugin live-generator smoke path；
- FileDescriptorSet descriptor/reflection bridge、descriptor verify report、old/new descriptor compatibility report、descriptor registry release gate、JSON release-policy DSL/warning check、file/HTTP/authenticated/profile/GitHub Contents managed-backend registry adapter publish/push/pull 与 JUnit XML CI report；
- AI verify Markdown/HTML report generator；
- Python/Go official protobuf oracle fixtures, including 32-bit numeric boundary, float/double and special float fixtures；
- conformance-lite Markdown/JSON/JUnit evidence report，含 expected-fail mutation self-checks 与 semantic-axis coverage gates；
- generated-code compile check，适合验证 AI 生成代码。

## 测试与 CI

| 检查 | 状态 |
| --- | --- |
| Python oracle | `python3 tests/oracle/python_protobuf_oracle.py` |
| Go oracle | `(cd tests/oracle && go run .)` |
| MoonBit check | `moon check` |
| MoonBit build | `moon build` |
| MoonBit tests | `moon test`，当前 `42/42 passed` |
| All targets | `moon test --target all` 覆盖 wasm/wasm-gc/js/native |
| CLI smoke | `moon run cmd/main -- gen --example` |
| File-based generator | `python3 scripts/moon_proto_gen.py gen examples/simple/user.proto -o generated/` |
| Generated code compile | `tests/codegen/compile_generated.sh` |
| Schema Doctor | `python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto` |
| Compatibility report | `python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md --junit-out generated/compat_report.xml` |
| Verify report | `python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md --junit-out generated/verify_report.xml` |
| Official differential report | `python3 scripts/moon_proto_official_diff.py --report generated/official_diff_report.md --junit-out generated/official_diff_report.xml` / `python3 scripts/moon_proto_official_diff.py --official-generated-dir tests/differential/official_generated_fixture --report generated/official_generated_diff_report.md --junit-out generated/official_generated_diff_report.xml` / `python3 scripts/moon_proto_official_diff.py --run-official-generator --official-plugin-bin protoc-gen-mbt --protoc-bin protoc --report generated/official_installed_plugin_diff_report.md --junit-out generated/official_installed_plugin_diff_report.xml` / CI also runs `--official-repo /tmp/protoc-gen-mbt --require-official` |
| Conformance-lite report | `python3 scripts/moon_proto_conformance.py --report generated/conformance_lite_report.md --json-out generated/conformance_lite.json --junit-out generated/conformance_lite.xml`，报告包含 positive oracle cases、expected-fail mutation self-checks 和 coverage gates |
| Descriptor verify/compat/registry/policy/adapter/JUnit report | `python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md --junit-out generated/descriptor_verify_report.xml` / `python3 scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md --junit-out generated/descriptor_compat_report.xml` / `python3 scripts/moon_proto_descriptor.py registry tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --name demo-user --report generated/descriptor_registry_report.md --json-out generated/descriptor_registry.json --policy tests/fixtures/descriptor_registry_policy.json --junit-out generated/descriptor_registry_report.xml` / `python3 scripts/moon_proto_descriptor.py policy generated/descriptor_registry.json tests/fixtures/descriptor_registry_policy.json --report generated/descriptor_policy_report.md --json-out generated/descriptor_policy.json --junit-out generated/descriptor_policy_report.xml` / `python3 scripts/moon_proto_descriptor.py publish generated/descriptor_registry.json --store generated/schema_registry_store --base-dir . --report generated/descriptor_registry_publish_report.md --junit-out generated/descriptor_registry_publish_report.xml` / `python3 scripts/moon_proto_descriptor.py push generated/schema_registry_store --base-url https://schemas.example.test/ --registry demo-user.json --report generated/descriptor_registry_push_report.md --junit-out generated/descriptor_registry_push_report.xml` / `python3 scripts/moon_proto_descriptor.py pull generated/schema_registry_store/registries/demo-user.json --output-dir generated/schema_registry_pull --report generated/descriptor_registry_pull_report.md --junit-out generated/descriptor_registry_pull_report.xml` |
| GitHub Actions | GitHub Actions 最新 main 分支 CI 需为 success：https://github.com/dsadsasdaddas/moon_proto/actions |

## 文档与交付物

| 交付物 | 路径 |
| --- | --- |
| README | `README.md` |
| 生态定位说明 | `docs/ECOSYSTEM_POSITIONING.md` |
| Schema Doctor 文档 | `docs/SCHEMA_DOCTOR.md` |
| Official differential 文档 | `docs/OFFICIAL_DIFFERENTIAL.md` |
| Descriptor set 文档 | `docs/DESCRIPTOR_SET.md` |
| Descriptor registry 文档 | `docs/SCHEMA_REGISTRY.md` |
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
python3 scripts/moon_proto_lab.py doctor examples/simple/user.proto
python3 scripts/moon_proto_lab.py doctor examples/decorated/telemetry.proto
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md --junit-out generated/compat_report.xml
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md --junit-out generated/verify_report.xml
python3 scripts/moon_proto_official_diff.py --report generated/official_diff_report.md --junit-out generated/official_diff_report.xml
python3 scripts/moon_proto_official_diff.py --official-generated-dir tests/differential/official_generated_fixture --report generated/official_generated_diff_report.md --junit-out generated/official_generated_diff_report.xml
python3 scripts/moon_proto_descriptor.py verify tests/fixtures/user_descriptor_set.hex --report generated/descriptor_verify_report.md --junit-out generated/descriptor_verify_report.xml
python3 scripts/moon_proto_descriptor.py compat tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --report generated/descriptor_compat_report.md --junit-out generated/descriptor_compat_report.xml
python3 scripts/moon_proto_descriptor.py registry tests/fixtures/user_descriptor_set.hex tests/fixtures/user_descriptor_set_reserved_v2.hex --name demo-user --report generated/descriptor_registry_report.md --json-out generated/descriptor_registry.json --policy tests/fixtures/descriptor_registry_policy.json --junit-out generated/descriptor_registry_report.xml
python3 scripts/moon_proto_descriptor.py publish generated/descriptor_registry.json --store generated/schema_registry_store --base-dir . --report generated/descriptor_registry_publish_report.md --json-out generated/descriptor_registry_published.json --junit-out generated/descriptor_registry_publish_report.xml
python3 scripts/moon_proto_descriptor.py pull generated/schema_registry_store/registries/demo-user.json --output-dir generated/schema_registry_pull --report generated/descriptor_registry_pull_report.md --json-out generated/descriptor_registry_pulled.json --junit-out generated/descriptor_registry_pull_report.xml
python3 scripts/moon_proto_descriptor.py policy generated/descriptor_registry.json tests/fixtures/descriptor_registry_policy.json --report generated/descriptor_policy_report.md --json-out generated/descriptor_policy.json --junit-out generated/descriptor_policy_report.xml
tests/codegen/compile_generated.sh
```
