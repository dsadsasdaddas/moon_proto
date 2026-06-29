#!/usr/bin/env python3
"""File-based moon_proto generator wrapper.

MoonBit's portable core library intentionally keeps file-system APIs minimal in
this toolchain snapshot, while `moon_proto` still needs an ergonomic project
workflow.  This wrapper provides the file-based CLI layer by reading a `.proto`
file, delegating schema parsing/codegen to the MoonBit CLI, and writing the
resulting MoonBit source to a file or directory.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


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


def run_moon_codegen(schema: str, moon_bin: str, root: Path) -> str:
    proc = subprocess.run(
        [moon_bin, 'run', 'cmd/main', '--', 'gen', '--schema', schema],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        message = proc.stderr.strip() or proc.stdout.strip() or 'moon codegen failed'
        raise RuntimeError(message)
    if proc.stdout.startswith('error:'):
        raise RuntimeError(proc.stdout.strip())
    return proc.stdout


def command_gen(args: argparse.Namespace) -> int:
    root = repo_root()
    proto = Path(args.proto)
    if not proto.is_absolute():
        proto = Path.cwd() / proto
    if not proto.exists():
        print(f'error: schema file not found: {proto}', file=sys.stderr)
        return 2
    schema = proto.read_text(encoding='utf-8')
    try:
        generated = run_moon_codegen(schema, args.moon_bin, root)
    except RuntimeError as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1

    out_path = output_file_for(proto, args.output)
    if args.stdout or out_path is None:
        print(generated, end='')
    if out_path is not None:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(generated, encoding='utf-8')
        if not args.quiet:
            print(out_path)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='moon_proto_gen.py',
        description='Generate MoonBit source from a .proto schema file.',
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
        '--moon-bin',
        default='moon',
        help='MoonBit CLI executable name/path (default: moon)',
    )
    gen.add_argument(
        '-q', '--quiet',
        action='store_true',
        help='do not print output path after writing a file',
    )
    gen.set_defaults(func=command_gen)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    raise SystemExit(main())
