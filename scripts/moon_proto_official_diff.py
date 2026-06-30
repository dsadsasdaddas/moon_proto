#!/usr/bin/env python3
"""Differential harness around the official MoonBit protobuf stack.

The default mode is intentionally dependency-light: it verifies that Moon Proto
Lab can parse, inspect, generate and compile representative schemas that overlap
with the public `moonbitlang/protoc-gen-mbt` feature surface.  If `protoc`, a
MoonBit toolchain and an official `protoc-gen-mbt` checkout are available, the
same harness can also invoke the official generator and include that result in
the report.
"""
from __future__ import annotations

import argparse
import html
import json
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from moon_proto_gen import (
    compile_generated_source,
    read_schema,
    repo_root,
    run_moon_codegen,
    run_moon_doctor,
    run_moon_inspect,
    schema_is_valid,
)


@dataclass
class StepResult:
    name: str
    status: str
    details: str

    @property
    def ok(self) -> bool:
        return self.status == 'PASS'

    @property
    def blocking(self) -> bool:
        return self.status == 'FAIL'


@dataclass
class CaseResult:
    name: str
    proto: Path
    steps: list[StepResult]
    inspect_output: str

    @property
    def ok(self) -> bool:
        return all(not step.blocking for step in self.steps)


OFFICIAL_SPEC_SUMMARY = [
    'scalars map to MoonBit numeric/string/bool/bytes types',
    'optional maps to Option-style fields',
    'repeated maps to Array',
    'oneof maps to an enum in the official generator',
    'map fields map to Map in the official generator',
    'extensions and custom options are documented as ignored by the official generator',
]


def load_manifest(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8'))


def step(name: str, status: str, details: str) -> StepResult:
    return StepResult(name=name, status=status, details=details)


def check_expected_inspect(inspect_output: str, snippets: list[str]) -> StepResult:
    missing = [snippet for snippet in snippets if snippet not in inspect_output]
    if missing:
        return step('inspect contract', 'FAIL', 'missing: ' + ', '.join(missing))
    return step('inspect contract', 'PASS', f'{len(snippets)} expected snippets found')


def check_official_generated_output(generated_dir_arg: str | None, case: dict) -> StepResult:
    snippets = case.get('expected_official_generated', [])
    if not generated_dir_arg:
        return step(
            'official generated output contract',
            'SKIP',
            'pass --official-generated-dir to validate pre-generated official MoonBit output',
        )
    generated_dir = Path(generated_dir_arg)
    if not generated_dir.exists():
        return step('official generated output contract', 'FAIL', f'generated directory not found: {generated_dir}')
    files = sorted(generated_dir.glob('**/*.mbt'))
    if not files:
        return step('official generated output contract', 'FAIL', f'no .mbt files found under {generated_dir}')
    merged = '\n'.join(path.read_text(encoding='utf-8', errors='replace') for path in files)
    missing = [snippet for snippet in snippets if snippet not in merged]
    if missing:
        return step(
            'official generated output contract',
            'FAIL',
            'missing: ' + ', '.join(missing),
        )
    return step(
        'official generated output contract',
        'PASS',
        f'{len(snippets)} expected snippets found in {len(files)} official generated file(s)',
    )


def official_plugin_path(repo: Path) -> Path | None:
    candidates = [
        repo / 'cli' / '_build' / 'native' / 'release' / 'build' / 'protoc-gen-mbt.exe',
        repo / 'cli' / '_build' / 'native' / 'debug' / 'build' / 'protoc-gen-mbt.exe',
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    built = sorted((repo / 'cli' / '_build').glob('**/protoc-gen-mbt.exe')) if (repo / 'cli' / '_build').exists() else []
    return built[0] if built else None



def git_head(repo: Path) -> str | None:
    git_dir = repo / '.git'
    if not git_dir.exists():
        return None
    proc = subprocess.run(
        ['git', '-C', str(repo), 'rev-parse', 'HEAD'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def check_official_source_contract(repo_arg: str | None, official: dict) -> StepResult:
    if not repo_arg:
        return step('official source contract', 'SKIP', 'pass --official-repo to validate an official checkout')
    repo = Path(repo_arg)
    if not repo.exists():
        return step('official source contract', 'FAIL', f'checkout not found: {repo}')
    missing_files: list[str] = []
    missing_snippets: list[str] = []
    required = official.get('required_source_snippets', {})
    for rel, snippets in required.items():
        path = repo / rel
        if not path.exists():
            missing_files.append(rel)
            continue
        text = path.read_text(encoding='utf-8', errors='replace')
        for snippet in snippets:
            if snippet not in text:
                missing_snippets.append(f'{rel}: {snippet}')
    if missing_files or missing_snippets:
        details = []
        if missing_files:
            details.append('missing files: ' + ', '.join(missing_files))
        if missing_snippets:
            details.append('missing snippets: ' + ', '.join(missing_snippets))
        return step('official source contract', 'FAIL', '; '.join(details))
    head = git_head(repo)
    observed = official.get('observed_commit', '')
    if head and observed and head != observed:
        return step(
            'official source contract',
            'PASS',
            f'source contract matched; checkout HEAD {head} differs from observed {observed}',
        )
    suffix = f'; checkout HEAD {head}' if head else ''
    return step('official source contract', 'PASS', 'source contract matched' + suffix)


def run_official_generator(
    proto: Path,
    repo: Path,
    moon_bin: str,
    protoc_bin: str,
    root: Path,
) -> StepResult:
    if not repo.exists():
        return step('official protoc-gen-mbt', 'SKIP', f'checkout not found: {repo}')
    if shutil.which(protoc_bin) is None:
        return step('official protoc-gen-mbt', 'SKIP', f'{protoc_bin} not found')
    if shutil.which(moon_bin) is None and not Path(moon_bin).exists():
        return step('official protoc-gen-mbt', 'SKIP', f'{moon_bin} not found')

    build = subprocess.run(
        [moon_bin, '-C', str(repo / 'cli'), 'build', '--release'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if build.returncode != 0:
        return step('official protoc-gen-mbt', 'FAIL', (build.stdout + build.stderr).strip() or 'official plugin build failed')

    plugin = official_plugin_path(repo)
    if plugin is None:
        return step('official protoc-gen-mbt', 'FAIL', 'built plugin not found under cli/_build')

    with tempfile.TemporaryDirectory(prefix='moon_proto_official_diff_') as tmp:
        out_root = Path(tmp)
        project = 'official_diff_gen'
        (out_root / project).mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(
            [
                protoc_bin,
                f'--plugin=protoc-gen-mbt={plugin}',
                f'--mbt_out={out_root}',
                f'--mbt_opt=paths=source_relative,project_name={project},json=true,async=false',
                f'-I{root}',
                str(proto),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if proc.returncode != 0:
            return step('official protoc-gen-mbt', 'FAIL', (proc.stdout + proc.stderr).strip() or 'official generator failed')
        generated_files = list((out_root / project).glob('**/*.mbt'))
        if not generated_files:
            return step('official protoc-gen-mbt', 'FAIL', 'official generator produced no .mbt files')
        rels = ', '.join(str(path.relative_to(out_root / project)) for path in generated_files[:5])
        return step('official protoc-gen-mbt', 'PASS', f'generated {len(generated_files)} file(s): {rels}')


def run_case(args: argparse.Namespace, case: dict, root: Path) -> CaseResult:
    proto = root / case['proto']
    steps: list[StepResult] = []
    inspect_output = ''
    try:
        _, schema = read_schema(str(proto))
    except FileNotFoundError as exc:
        return CaseResult(case['name'], proto, [step('read schema', 'FAIL', str(exc))], '')

    try:
        doctor_output = run_moon_doctor(schema, args.moon_bin, root)
        if schema_is_valid(doctor_output):
            steps.append(step('schema doctor', 'PASS', doctor_output.splitlines()[0]))
        else:
            steps.append(step('schema doctor', 'FAIL', doctor_output.splitlines()[0] if doctor_output else 'schema invalid'))
    except RuntimeError as exc:
        steps.append(step('schema doctor', 'FAIL', str(exc)))
        return CaseResult(case['name'], proto, steps, inspect_output)

    try:
        inspect_output = run_moon_inspect(schema, args.moon_bin, root)
        steps.append(step('schema inspect', 'PASS', 'schema summary generated'))
        steps.append(check_expected_inspect(inspect_output, case.get('expected_inspect', [])))
    except RuntimeError as exc:
        steps.append(step('schema inspect', 'FAIL', str(exc)))

    try:
        generated = run_moon_codegen(schema, args.moon_bin, root)
        steps.append(step('Moon Proto Lab codegen', 'PASS', f'{len(generated.splitlines())} generated lines'))
        if not args.skip_compile:
            compile_out = compile_generated_source(generated, args.moon_bin, root)
            steps.append(step('generated-code compile', 'PASS', compile_out.splitlines()[0] if compile_out else 'moon check passed'))
        else:
            steps.append(step('generated-code compile', 'PASS', 'skipped by --skip-compile'))
    except RuntimeError as exc:
        steps.append(step('Moon Proto Lab codegen/compile', 'FAIL', str(exc)))

    if args.official_repo and args.run_official_generator:
        steps.append(
            run_official_generator(
                proto,
                Path(args.official_repo),
                args.moon_bin,
                args.protoc_bin,
                root,
            )
        )
    elif args.official_repo:
        steps.append(step('official protoc-gen-mbt', 'SKIP', 'official generator not requested; pass --run-official-generator to execute it'))
    else:
        steps.append(step('official protoc-gen-mbt', 'SKIP', 'pass --official-repo and --run-official-generator to run the optional generator check'))

    steps.append(check_official_generated_output(args.official_generated_dir, case))

    return CaseResult(case['name'], proto, steps, inspect_output)


def markdown_report(
    manifest: dict,
    source_step: StepResult,
    results: list[CaseResult],
    require_official: bool,
    run_generator: bool,
    generated_dir: str | None,
) -> str:
    official = manifest['official']
    blocking_failures = [step for result in results for step in result.steps if step.blocking]
    if source_step.blocking or (require_official and source_step.status != 'PASS'):
        blocking_failures.append(source_step)
    if require_official and run_generator:
        blocking_failures.extend(
            step for result in results for step in result.steps
            if step.name == 'official protoc-gen-mbt' and step.status != 'PASS'
        )
    status = 'PASS' if not blocking_failures else 'FAIL'
    lines = [
        '# Moon Proto Lab official differential report',
        '',
        f'- Generated at: `{datetime.now(timezone.utc).isoformat()}`',
        f'- Overall status: **{status}**',
        f'- Official project: [{official["name"]}]({official["repository"]})',
        f'- Observed official commit: `{official["observed_commit"]}`',
        f'- Runtime package: `{official["runtime_package"]}`',
        f'- Official source required: `{str(require_official).lower()}`',
        f'- Official generator requested: `{str(run_generator).lower()}`',
        f'- Official generated output directory: `{generated_dir or ""}`',
        '',
        '## Official feature contract used by this harness',
        '',
    ]
    for item in OFFICIAL_SPEC_SUMMARY:
        lines.append(f'- {item};')
    for note in official.get('notes', []):
        lines.append(f'- source note: {note}')
    source_details = source_step.details.replace('|', '\\|').replace('\n', '<br>')
    lines.extend([
        '',
        '## Official source checkout',
        '',
        '| Step | Status | Details |',
        '| --- | --- | --- |',
        f'| {source_step.name} | {source_step.status} | {source_details} |',
        '',
        '## Case results',
        '',
        '| Case | Proto | Step | Status | Details |',
        '| --- | --- | --- | --- | --- |',
    ])
    for result in results:
        for s in result.steps:
            details = s.details.replace('|', '\\|').replace('\n', '<br>')
            lines.append(f'| {result.name} | `{result.proto}` | {s.name} | {s.status} | {details} |')
    lines.extend(['', '## Interpretation', ''])
    lines.append('`PASS` means Moon Proto Lab can independently verify the schema/codegen contract for that case.')
    lines.append('The official source contract step is blocking when `--require-official` is used. The generator step is only blocking when both `--require-official` and `--run-official-generator` are used.')
    lines.append('Intentional differences are expected: Moon Proto Lab keeps descriptor-driven `MessageValue` helpers for dynamic verification, while the official generator emits production typed structs, maps and oneof enums.')
    return '\n'.join(lines) + '\n'


def html_report(md: str) -> str:
    return f'''<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Moon Proto Lab official differential report</title></head>
<body><pre>{html.escape(md)}</pre></body>
</html>
'''


def xml_escape(text: str) -> str:
    return html.escape(text, quote=True)


def source_step_is_failure(source_step: StepResult, require_official: bool) -> bool:
    return source_step.blocking or (require_official and source_step.status != 'PASS')


def case_step_is_failure(step_result: StepResult, require_official: bool, run_generator: bool) -> bool:
    if step_result.blocking:
        return True
    return (
        require_official
        and run_generator
        and step_result.name == 'official protoc-gen-mbt'
        and step_result.status != 'PASS'
    )


def junit_cases(
    source_step: StepResult,
    results: list[CaseResult],
    require_official: bool,
    run_generator: bool,
) -> list[tuple[str, StepResult, bool]]:
    cases: list[tuple[str, StepResult, bool]] = [
        (
            'official source checkout / ' + source_step.name,
            source_step,
            source_step_is_failure(source_step, require_official),
        )
    ]
    for result in results:
        for step_result in result.steps:
            cases.append(
                (
                    f'{result.name} / {step_result.name}',
                    step_result,
                    case_step_is_failure(step_result, require_official, run_generator),
                )
            )
    return cases


def write_junit_report(
    path: Path,
    source_step: StepResult,
    results: list[CaseResult],
    require_official: bool,
    run_generator: bool,
) -> None:
    cases = junit_cases(source_step, results, require_official, run_generator)
    failures = sum(1 for _name, _step_result, is_failure in cases if is_failure)
    skipped = sum(
        1
        for _name, step_result, is_failure in cases
        if step_result.status == 'SKIP' and not is_failure
    )
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        (
            '<testsuite name="moon-proto-lab.official-differential" '
            f'tests="{len(cases)}" failures="{failures}" skipped="{skipped}">'
        ),
    ]
    for name, step_result, is_failure in cases:
        lines.append(
            f'  <testcase name="{xml_escape(name)}" classname="moon-proto-lab.official-differential">'
        )
        if is_failure:
            first = step_result.details.splitlines()[0] if step_result.details else 'failed'
            lines.append(
                f'    <failure message="{xml_escape(first)}">'
                + xml_escape(step_result.details)
                + '</failure>'
            )
        elif step_result.status == 'SKIP':
            lines.append(f'    <skipped message="{xml_escape(step_result.details)}" />')
        else:
            lines.append(f'    <system-out>{xml_escape(step_result.details)}</system-out>')
        lines.append('  </testcase>')
    lines.append('</testsuite>')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def write_report(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() in {'.html', '.htm'}:
        path.write_text(html_report(text), encoding='utf-8')
    else:
        path.write_text(text, encoding='utf-8')


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description='Run Moon Proto Lab differential checks against the public moonbitlang/protoc-gen-mbt feature contract.',
    )
    parser.add_argument('--manifest', default='tests/differential/official_cases.json')
    parser.add_argument('--report', help='write Markdown/HTML report')
    parser.add_argument('--junit-out', help='write CI-readable JUnit XML report')
    parser.add_argument('--moon-bin', default='moon')
    parser.add_argument('--protoc-bin', default='protoc')
    parser.add_argument('--official-repo', help='optional path to a moonbitlang/protoc-gen-mbt checkout')
    parser.add_argument('--official-generated-dir', help='optional directory containing pre-generated official .mbt output to validate against the manifest contract')
    parser.add_argument('--require-official', action='store_true', help='fail if the official source contract is skipped or fails; also require generator success when --run-official-generator is used')
    parser.add_argument('--run-official-generator', action='store_true', help='build and run the official protoc-gen-mbt plugin when --official-repo is available')
    parser.add_argument('--skip-compile', action='store_true', help='skip Moon Proto Lab generated-code compile checks')
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = repo_root()
    manifest = load_manifest(root / args.manifest)
    source_step = check_official_source_contract(args.official_repo, manifest['official'])
    results = [run_case(args, case, root) for case in manifest['cases']]
    md = markdown_report(
        manifest,
        source_step,
        results,
        args.require_official,
        args.run_official_generator,
        args.official_generated_dir,
    )
    if args.report:
        write_report(Path(args.report), md)
        print(f'report: {args.report}')
    if args.junit_out:
        write_junit_report(
            Path(args.junit_out),
            source_step,
            results,
            args.require_official,
            args.run_official_generator,
        )
        print(f'junit: {args.junit_out}')
    print(md, end='')
    has_failures = any(step.blocking for result in results for step in result.steps)
    has_failures = has_failures or source_step.blocking
    if args.require_official:
        has_failures = has_failures or source_step.status != 'PASS'
        if args.run_official_generator:
            has_failures = has_failures or any(
                step.name == 'official protoc-gen-mbt' and step.status != 'PASS'
                for result in results for step in result.steps
            )
    return 1 if has_failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
