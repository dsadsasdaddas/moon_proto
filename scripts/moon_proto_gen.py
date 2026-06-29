#!/usr/bin/env python3
"""Moon Proto Lab file-based CLI.

MoonBit's portable core library intentionally keeps file-system APIs minimal in
this toolchain snapshot, while Moon Proto Lab still needs ergonomic project
workflows.  This wrapper provides file-based commands by reading `.proto` files,
delegating schema parsing/codegen/inspection to the MoonBit CLI, and adding
verification/report orchestration around generated MoonBit source.
"""
from __future__ import annotations

import argparse
import html
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class VerifyStep:
    name: str
    ok: bool
    details: str


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def output_file_for(proto_path: Path, output: str | None) -> Path | None:
    if output is None:
        return None
    out = Path(output)
    if (
        str(output).endswith(('/', '\\'))
        or (out.exists() and out.is_dir())
        or out.suffix == ''
    ):
        return out / (proto_path.stem + '.mbt')
    return out


def resolve_proto_path(proto_arg: str) -> Path:
    proto = Path(proto_arg)
    if not proto.is_absolute():
        proto = Path.cwd() / proto
    return proto


def read_schema(proto_arg: str) -> tuple[Path, str]:
    proto = resolve_proto_path(proto_arg)
    if not proto.exists():
        raise FileNotFoundError(f'schema file not found: {proto}')
    return proto, proto.read_text(encoding='utf-8')


def run_moon_cli(cli_args: list[str], moon_bin: str, root: Path) -> str:
    proc = subprocess.run(
        [moon_bin, 'run', 'cmd/main', '--', *cli_args],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        message = proc.stderr.strip() or proc.stdout.strip() or 'moon command failed'
        raise RuntimeError(message)
    if proc.stdout.startswith('error:'):
        raise RuntimeError(proc.stdout.strip())
    return proc.stdout


def run_moon_codegen(schema: str, moon_bin: str, root: Path) -> str:
    return run_moon_cli(['gen', '--schema', schema], moon_bin, root)


def run_moon_doctor(schema: str, moon_bin: str, root: Path) -> str:
    return run_moon_cli(['doctor', '--schema', schema], moon_bin, root)


def run_moon_inspect(schema: str, moon_bin: str, root: Path) -> str:
    return run_moon_cli(['inspect', '--schema', schema], moon_bin, root)


def run_moon_compat(old_schema: str, new_schema: str, moon_bin: str, root: Path) -> str:
    return run_moon_cli(
        ['compat', '--old-schema', old_schema, '--new-schema', new_schema],
        moon_bin,
        root,
    )


def schema_is_valid(doctor_output: str) -> bool:
    return doctor_output.splitlines()[0:1] == ['schema valid']


def schema_is_compatible(compat_output: str) -> bool:
    return compat_output.splitlines()[0:1] == ['schema compatible']


def command_gen(args: argparse.Namespace) -> int:
    root = repo_root()
    try:
        proto, schema = read_schema(args.proto)
        generated = run_moon_codegen(schema, args.moon_bin, root)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1 if isinstance(exc, RuntimeError) else 2

    out_path = output_file_for(proto, args.output)
    if args.stdout or out_path is None:
        print(generated, end='')
    if out_path is not None:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(generated, encoding='utf-8')
        if not args.quiet:
            print(out_path)
    return 0


def command_doctor(args: argparse.Namespace) -> int:
    root = repo_root()
    try:
        _, schema = read_schema(args.proto)
        output = run_moon_doctor(schema, args.moon_bin, root)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1 if isinstance(exc, RuntimeError) else 2
    print(output, end='' if output.endswith('\n') else '\n')
    return 0 if schema_is_valid(output) else 1


def command_inspect(args: argparse.Namespace) -> int:
    root = repo_root()
    try:
        _, schema = read_schema(args.proto)
        output = run_moon_inspect(schema, args.moon_bin, root)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1 if isinstance(exc, RuntimeError) else 2
    print(output, end='' if output.endswith('\n') else '\n')
    return 0


def command_compat(args: argparse.Namespace) -> int:
    root = repo_root()
    try:
        old_proto, old_schema = read_schema(args.old_proto)
        new_proto, new_schema = read_schema(args.new_proto)
        output = run_moon_compat(old_schema, new_schema, args.moon_bin, root)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1 if isinstance(exc, RuntimeError) else 2
    ok = schema_is_compatible(output)
    print(output, end='' if output.endswith('\n') else '\n')
    if args.report:
        write_compat_report(Path(args.report), old_proto, new_proto, ok, output)
        print(f'report: {args.report}')
    return 0 if ok else 1


def copy_repo_for_compile(root: Path, tmp_path: Path) -> None:
    def ignore(_dir: str, names: list[str]) -> set[str]:
        ignored = {'.git', '_build', '.mooncakes', 'generated', 'tmp'}
        return {name for name in names if name in ignored or name == '.DS_Store'}

    shutil.copytree(root, tmp_path, dirs_exist_ok=True, ignore=ignore)


def compile_generated_source(generated: str, moon_bin: str, root: Path) -> str:
    with tempfile.TemporaryDirectory(prefix='moon_proto_lab_verify_') as tmp:
        tmp_path = Path(tmp)
        copy_repo_for_compile(root, tmp_path)
        generated_path = tmp_path / 'generated_verify_check.mbt'
        generated_path.write_text(generated, encoding='utf-8')
        proc = subprocess.run(
            [moon_bin, 'check'],
            cwd=tmp_path,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        output = (proc.stdout + proc.stderr).strip()
        if proc.returncode != 0:
            raise RuntimeError(output or 'moon check failed for generated source')
        return output or 'moon check passed for generated source'


def markdown_report(
    proto: Path,
    status: bool,
    steps: list[VerifyStep],
    doctor_output: str,
    inspect_output: str,
    generated: str,
) -> str:
    generated_lines = generated.count('\n') + (1 if generated else 0)
    generated_bytes = len(generated.encode('utf-8'))
    lines = [
        '# Moon Proto Lab verification report',
        '',
        f'- Schema: `{proto}`',
        f'- Generated at: `{datetime.now(timezone.utc).isoformat()}`',
        f'- Overall status: **{"PASS" if status else "FAIL"}**',
        f'- Generated source lines: `{generated_lines}`',
        f'- Generated source bytes: `{generated_bytes}`',
        '',
        '## Verification steps',
        '',
        '| Step | Status | Details |',
        '| --- | --- | --- |',
    ]
    for step in steps:
        detail = step.details.replace('\n', '<br>')
        lines.append(f'| {step.name} | {"PASS" if step.ok else "FAIL"} | {detail} |')
    lines.extend([
        '',
        '## Schema Doctor output',
        '',
        '```text',
        doctor_output.strip(),
        '```',
    ])
    if inspect_output:
        lines.extend([
            '',
            '## Schema summary',
            '',
            '```text',
            inspect_output.strip(),
            '```',
        ])
    if generated:
        preview = '\n'.join(generated.splitlines()[:120])
        lines.extend([
            '',
            '## Generated MoonBit source preview',
            '',
            '```moonbit',
            preview,
            '```',
        ])
    return '\n'.join(lines) + '\n'


def html_report(
    proto: Path,
    status: bool,
    steps: list[VerifyStep],
    doctor_output: str,
    inspect_output: str,
    generated: str,
) -> str:
    md = markdown_report(proto, status, steps, doctor_output, inspect_output, generated)
    # Keep the HTML renderer intentionally dependency-free and predictable.
    escaped_blocks = html.escape(md)
    color = '#16833a' if status else '#b42318'
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Moon Proto Lab verification report</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; color: #1f2937; }}
pre {{ white-space: pre-wrap; background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 8px; padding: 16px; }}
.badge {{ display: inline-block; padding: 4px 10px; border-radius: 999px; color: #fff; background: {color}; }}
</style>
</head>
<body>
<h1>Moon Proto Lab verification report <span class="badge">{'PASS' if status else 'FAIL'}</span></h1>
<pre>{escaped_blocks}</pre>
</body>
</html>
'''


def compat_markdown_report(
    old_proto: Path,
    new_proto: Path,
    status: bool,
    compat_output: str,
) -> str:
    lines = [
        '# Moon Proto Lab schema compatibility report',
        '',
        f'- Old schema: `{old_proto}`',
        f'- New schema: `{new_proto}`',
        f'- Generated at: `{datetime.now(timezone.utc).isoformat()}`',
        f'- Overall status: **{"PASS" if status else "FAIL"}**',
        '',
        '## Compatibility output',
        '',
        '```text',
        compat_output.strip(),
        '```',
    ]
    return '\n'.join(lines) + '\n'


def compat_html_report(
    old_proto: Path,
    new_proto: Path,
    status: bool,
    compat_output: str,
) -> str:
    md = compat_markdown_report(old_proto, new_proto, status, compat_output)
    escaped_blocks = html.escape(md)
    color = '#16833a' if status else '#b42318'
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Moon Proto Lab schema compatibility report</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; color: #1f2937; }}
pre {{ white-space: pre-wrap; background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 8px; padding: 16px; }}
.badge {{ display: inline-block; padding: 4px 10px; border-radius: 999px; color: #fff; background: {color}; }}
</style>
</head>
<body>
<h1>Moon Proto Lab schema compatibility report <span class="badge">{'PASS' if status else 'FAIL'}</span></h1>
<pre>{escaped_blocks}</pre>
</body>
</html>
'''


def write_compat_report(
    path: Path,
    old_proto: Path,
    new_proto: Path,
    status: bool,
    compat_output: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() in {'.html', '.htm'}:
        text = compat_html_report(old_proto, new_proto, status, compat_output)
    else:
        text = compat_markdown_report(old_proto, new_proto, status, compat_output)
    path.write_text(text, encoding='utf-8')


def write_report(
    path: Path,
    proto: Path,
    status: bool,
    steps: list[VerifyStep],
    doctor_output: str,
    inspect_output: str,
    generated: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() in {'.html', '.htm'}:
        text = html_report(proto, status, steps, doctor_output, inspect_output, generated)
    else:
        text = markdown_report(proto, status, steps, doctor_output, inspect_output, generated)
    path.write_text(text, encoding='utf-8')


def command_verify(args: argparse.Namespace) -> int:
    root = repo_root()
    steps: list[VerifyStep] = []
    doctor_output = ''
    inspect_output = ''
    generated = ''
    proto = resolve_proto_path(args.proto)
    overall_ok = False

    try:
        proto, schema = read_schema(args.proto)
    except FileNotFoundError as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 2

    try:
        doctor_output = run_moon_doctor(schema, args.moon_bin, root)
        valid = schema_is_valid(doctor_output)
        steps.append(VerifyStep('schema doctor', valid, 'schema valid' if valid else 'schema invalid'))
    except RuntimeError as exc:
        doctor_output = str(exc)
        steps.append(VerifyStep('schema doctor', False, str(exc)))
        valid = False

    if valid:
        try:
            inspect_output = run_moon_inspect(schema, args.moon_bin, root)
            steps.append(VerifyStep('schema inspect', True, 'schema summary generated'))
        except RuntimeError as exc:
            steps.append(VerifyStep('schema inspect', False, str(exc)))
            valid = False

    if valid:
        try:
            generated = run_moon_codegen(schema, args.moon_bin, root)
            steps.append(VerifyStep('codegen', True, f'{len(generated.splitlines())} generated lines'))
        except RuntimeError as exc:
            steps.append(VerifyStep('codegen', False, str(exc)))
            valid = False

    if valid and not args.skip_compile:
        try:
            compile_output = compile_generated_source(generated, args.moon_bin, root)
            steps.append(VerifyStep('generated-code compile', True, compile_output))
        except RuntimeError as exc:
            steps.append(VerifyStep('generated-code compile', False, str(exc)))
            valid = False
    elif valid and args.skip_compile:
        steps.append(VerifyStep('generated-code compile', True, 'skipped by --skip-compile'))

    overall_ok = valid and all(step.ok for step in steps)

    if args.report:
        report_path = Path(args.report)
        write_report(report_path, proto, overall_ok, steps, doctor_output, inspect_output, generated)
        print(f'report: {report_path}')

    print('Moon Proto Lab verify: ' + ('PASS' if overall_ok else 'FAIL'))
    for step in steps:
        print(f'- {step.name}: {"PASS" if step.ok else "FAIL"} - {step.details.splitlines()[0]}')
    return 0 if overall_ok else 1


def add_common_moon_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        '--moon-bin',
        default='moon',
        help='MoonBit CLI executable name/path (default: moon)',
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='moon_proto_lab.py',
        description='Moon Proto Lab: schema doctor, verification reports, and MoonBit codegen for .proto files.',
    )
    sub = parser.add_subparsers(dest='command', required=True)

    gen = sub.add_parser('gen', help='generate MoonBit source')
    gen.add_argument('proto', help='input .proto schema path')
    gen.add_argument(
        '-o', '--output',
        help='output .mbt file or output directory; defaults to stdout',
    )
    gen.add_argument(
        '--stdout',
        action='store_true',
        help='also write generated source to stdout when -o is used',
    )
    gen.add_argument(
        '-q', '--quiet',
        action='store_true',
        help='do not print output path after writing a file',
    )
    add_common_moon_arg(gen)
    gen.set_defaults(func=command_gen)

    doctor = sub.add_parser('doctor', help='run schema diagnostics')
    doctor.add_argument('proto', help='input .proto schema path')
    add_common_moon_arg(doctor)
    doctor.set_defaults(func=command_doctor)

    inspect = sub.add_parser('inspect', help='print a compact schema summary')
    inspect.add_argument('proto', help='input .proto schema path')
    add_common_moon_arg(inspect)
    inspect.set_defaults(func=command_inspect)

    compat = sub.add_parser('compat', help='check old/new schema compatibility')
    compat.add_argument('old_proto', help='old .proto schema path')
    compat.add_argument('new_proto', help='new .proto schema path')
    compat.add_argument('--report', help='write a Markdown or HTML compatibility report')
    add_common_moon_arg(compat)
    compat.set_defaults(func=command_compat)

    verify = sub.add_parser('verify', help='run schema doctor, codegen, compile check, and optional report')
    verify.add_argument('proto', help='input .proto schema path')
    verify.add_argument('--report', help='write a Markdown or HTML verification report')
    verify.add_argument('--skip-compile', action='store_true', help='skip generated-code moon check')
    add_common_moon_arg(verify)
    verify.set_defaults(func=command_verify)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    raise SystemExit(main())
