# Engineering Record

This document explains how Moon Proto Lab keeps the contest-required engineering
history public and traceable.  The earliest development phase was tracked mainly
through Git commits and CI; the public issues #2-#5 below are **retrospective
traceability records**, not pre-existing sprint tickets.  They are intentionally
marked as completed records so reviewers can see the mapping from commits to work
packages without implying that the issues were opened before the work started.

The real-time process from this point forward is: open issue -> branch -> pull
request -> CI -> merge -> Gitlink sync.  PR #1 and issue #6 are the first records
created with that live process.

## Public tracking locations

- GitHub repository: <https://github.com/dsadsasdaddas/moon_proto>
- Gitlink repository: <https://gitlink.org.cn/wangyue111/moon_proto>
- GitHub issues: <https://github.com/dsadsasdaddas/moon_proto/issues>
- GitHub pull requests: <https://github.com/dsadsasdaddas/moon_proto/pulls>
- GitHub Actions: <https://github.com/dsadsasdaddas/moon_proto/actions>
- Changelog: [`CHANGELOG.md`](../CHANGELOG.md)
- Reviewer demo: [`docs/DEMO.md`](DEMO.md)
- Development report: [`docs/DEVELOPMENT_REPORT.md`](DEVELOPMENT_REPORT.md)
- Submission checklist: [`docs/SUBMISSION_CHECKLIST.md`](SUBMISSION_CHECKLIST.md)


## Public issue tracker records

The following public GitHub issues make the main work packages visible in the
issue tracker.  Issues #2-#5 are retrospective records created after the initial
implementation, while #6 is tracked by an actual PR workflow.

| Issue | Purpose | Status |
| --- | --- | --- |
| [#2](https://github.com/dsadsasdaddas/moon_proto/issues/2) | Runtime primitives and golden vectors | Retrospective completed record |
| [#3](https://github.com/dsadsasdaddas/moon_proto/issues/3) | Schema parser, validation and Schema Doctor | Retrospective completed record |
| [#4](https://github.com/dsadsasdaddas/moon_proto/issues/4) | JSON mapping, dynamic runtime and MoonBit codegen | Retrospective completed record |
| [#5](https://github.com/dsadsasdaddas/moon_proto/issues/5) | Oracle, conformance, official differential and descriptor registry gates | Retrospective completed record |
| [#6](https://github.com/dsadsasdaddas/moon_proto/issues/6) | Contest submission engineering records and release hygiene | Live issue tracked by PR [#1](https://github.com/dsadsasdaddas/moon_proto/pull/1) |

## Work-package traceability

| Work package | Scope | Representative commits | Evidence |
| --- | --- | --- | --- |
| WP0 project bootstrap | Repository metadata, MoonBit package layout, CI skeleton and proposal materials | `d3a149d`, `5cd4ff2`, `d6eba92`, `b78e7f2` | README, proposal PDF, GitHub/Gitlink mirrors |
| WP1 protobuf primitives | Wire types, varint, zig-zag, fixed-width and field encoders | `ddb3bbf`..`1787a1f` | `golden_wbtest.mbt`, `moon test` |
| WP2 schema parser | Proto3 descriptors, lexer/parser, decorated schema tolerance | `dd121ab`, `627cdc4`, `82a9548`..`8d78a2a` | parser tests, example `.proto` files |
| WP3 validation and doctor | Schema validator, reserved contracts, diagnostic CLI and verify reports | `6d50012`, `4e88bf3`, `d16c366` | `doctor`, `verify`, JUnit XML reports |
| WP4 runtime and JSON mapping | Dynamic message runtime, nested/map/oneof support and protobuf JSON behavior | `3a6a1ef`..`269d782`, `bb6ae7e`..`adcae4f` | `moon test`, JSON roundtrip CLI |
| WP5 code generation | MoonBit source generation, file generator and generated-code compile checks | `c7fd09d`, `980780a`, `97deb37`, `938bf33` | `tests/codegen/compile_generated.sh` |
| WP6 compatibility and conformance | Python/Go oracle, official differential, conformance-lite and coverage gates | `7be37d0`, `f0b38c7`, `9470434`..`d0f0e52` | oracle scripts, conformance reports, CI |
| WP7 descriptor registry | Descriptor-set bridge, registry release gates, policy DSL and publish/pull adapters | `7fb538a`..`28da0c1` | descriptor reports and registry tests |
| WP8 contest readiness | Ecosystem positioning, development report, checklist and reviewer demo | `6ba9cb5`, `7824fbb`, `3f7bf87`, `cd5d403` | docs and final validation logs |

## Definition of done for future work

Every future change should follow this flow:

1. Create or reference a public issue.
2. Use a branch with the `wangyue/` prefix.
3. Keep the change small and focused.
4. Add or update a regression test before changing behavior.
5. Run the relevant verification commands.
6. Update `CHANGELOG.md` and docs if user-visible behavior changes.
7. Open a pull request and complete the PR checklist.
8. Merge only after CI and manual smoke checks pass.
9. Sync Gitlink after GitHub `main` is updated.

## Minimum verification commands

```bash
moon check
moon build
moon test
moon test --target all
tests/codegen/compile_generated.sh
python3 scripts/moon_proto_lab.py verify examples/simple/user.proto --report generated/verify_report.md --junit-out generated/verify_report.xml
python3 scripts/moon_proto_lab.py compat examples/simple/user.proto examples/simple/user_v2.proto --report generated/compat_report.md --junit-out generated/compat_report.xml
python3 scripts/moon_proto_conformance.py --report generated/conformance_lite_report.md --json-out generated/conformance_lite.json --junit-out generated/conformance_lite.xml
```

## Regression policy

A bug is considered fixed only when a test or fixture captures the failing case.
Good regression candidates include:

- reserved field/name reuse;
- duplicate field numbers or names;
- invalid map key types;
- oneof selection and duplicate JSON fields;
- lowerCamel JSON aliases;
- numeric map-key canonicalization;
- descriptor-set compatibility edges;
- generated MoonBit source compile failures.

## Contest submission status

The current submission line is frozen at the completed 0.1.0 scope.  Additional
work before review should be limited to bug fixes, documentation, test evidence,
presentation materials and repository hygiene.
