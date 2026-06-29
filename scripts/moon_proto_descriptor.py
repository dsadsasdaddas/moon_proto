#!/usr/bin/env python3
"""FileDescriptorSet import/export utilities for Moon Proto Lab.

This script gives the project a descriptor/reflection bridge: protobuf descriptor
sets can be inspected, converted back to a Moon Proto Lab supported `.proto`
subset, and fed into the existing doctor/codegen/compile verification pipeline.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from google.protobuf import descriptor_pb2, json_format

from moon_proto_gen import (
    compile_generated_source,
    repo_root,
    run_moon_codegen,
    run_moon_compat,
    run_moon_doctor,
    run_moon_inspect,
    schema_is_compatible,
    schema_is_valid,
)


@dataclass
class DescriptorStep:
    name: str
    ok: bool
    details: str


@dataclass
class RegistryVersion:
    index: int
    path: Path
    ok: bool
    digest: str
    files: list[str]
    packages: list[str]
    messages: list[str]
    enums: list[str]
    proto_text: str
    details: str


@dataclass
class RegistryEdge:
    old_index: int
    new_index: int
    old_path: Path
    new_path: Path
    compatible: bool
    output: str


PROTO_TYPE_NAMES = {
    descriptor_pb2.FieldDescriptorProto.TYPE_DOUBLE: 'double',
    descriptor_pb2.FieldDescriptorProto.TYPE_FLOAT: 'float',
    descriptor_pb2.FieldDescriptorProto.TYPE_INT32: 'int32',
    descriptor_pb2.FieldDescriptorProto.TYPE_INT64: 'int64',
    descriptor_pb2.FieldDescriptorProto.TYPE_UINT32: 'uint32',
    descriptor_pb2.FieldDescriptorProto.TYPE_UINT64: 'uint64',
    descriptor_pb2.FieldDescriptorProto.TYPE_SINT32: 'sint32',
    descriptor_pb2.FieldDescriptorProto.TYPE_SINT64: 'sint64',
    descriptor_pb2.FieldDescriptorProto.TYPE_FIXED32: 'fixed32',
    descriptor_pb2.FieldDescriptorProto.TYPE_FIXED64: 'fixed64',
    descriptor_pb2.FieldDescriptorProto.TYPE_SFIXED32: 'sfixed32',
    descriptor_pb2.FieldDescriptorProto.TYPE_SFIXED64: 'sfixed64',
    descriptor_pb2.FieldDescriptorProto.TYPE_BOOL: 'bool',
    descriptor_pb2.FieldDescriptorProto.TYPE_STRING: 'string',
    descriptor_pb2.FieldDescriptorProto.TYPE_BYTES: 'bytes',
}


def canonical_json(message) -> str:
    return json_format.MessageToJson(
        message,
        preserving_proto_field_name=True,
        sort_keys=True,
        indent=2,
    )


def load_descriptor_set(path: Path) -> descriptor_pb2.FileDescriptorSet:
    data = path.read_bytes()
    fds = descriptor_pb2.FileDescriptorSet()
    suffix = path.suffix.lower()
    if suffix == '.json':
        json_format.Parse(data.decode('utf-8'), fds)
    elif suffix == '.hex':
        fds.ParseFromString(bytes.fromhex(data.decode('utf-8').strip()))
    else:
        fds.ParseFromString(data)
    return fds


def write_descriptor_set(path: Path, fds: descriptor_pb2.FileDescriptorSet) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    suffix = path.suffix.lower()
    if suffix == '.json':
        path.write_text(canonical_json(fds) + '\n', encoding='utf-8')
    elif suffix == '.hex':
        path.write_text(fds.SerializeToString().hex() + '\n', encoding='utf-8')
    else:
        path.write_bytes(fds.SerializeToString())


def descriptor_digest(fds: descriptor_pb2.FileDescriptorSet) -> str:
    return hashlib.sha256(fds.SerializeToString()).hexdigest()


def collect_schema_names(fds: descriptor_pb2.FileDescriptorSet) -> tuple[list[str], list[str], list[str], list[str]]:
    files: list[str] = []
    packages: list[str] = []
    messages: list[str] = []
    enums: list[str] = []

    def visit_message(message: descriptor_pb2.DescriptorProto, prefix: str) -> None:
        name = f'{prefix}.{message.name}' if prefix else message.name
        if not message.options.map_entry:
            messages.append(name)
        for enum_desc in message.enum_type:
            enums.append(f'{name}.{enum_desc.name}')
        for nested in message.nested_type:
            visit_message(nested, name)

    for file_desc in fds.file:
        files.append(file_desc.name)
        if file_desc.package and file_desc.package not in packages:
            packages.append(file_desc.package)
        for enum_desc in file_desc.enum_type:
            enums.append(enum_desc.name)
        for message in file_desc.message_type:
            visit_message(message, '')
    return files, packages, messages, enums


def markdown_table_cell(text: str) -> str:
    return text.replace('|', '\\|').replace('\n', '<br>')


def type_name_tail(type_name: str, package: str) -> str:
    name = type_name.lstrip('.')
    if package and name.startswith(package + '.'):
        name = name[len(package) + 1:]
    return name.split('.')[-1]


def build_map_entry_index(file_desc: descriptor_pb2.FileDescriptorProto) -> dict[str, descriptor_pb2.DescriptorProto]:
    package_prefix = f'.{file_desc.package}.' if file_desc.package else '.'
    out: dict[str, descriptor_pb2.DescriptorProto] = {}

    def visit(message: descriptor_pb2.DescriptorProto, parents: list[str]) -> None:
        fq = package_prefix + '.'.join([*parents, message.name])
        if message.options.map_entry:
            out[fq] = message
        for nested in message.nested_type:
            visit(nested, [*parents, message.name])

    for message in file_desc.message_type:
        visit(message, [])
    return out


def field_type_text(
    field: descriptor_pb2.FieldDescriptorProto,
    file_desc: descriptor_pb2.FileDescriptorProto,
    map_entries: dict[str, descriptor_pb2.DescriptorProto],
) -> str:
    if field.type in PROTO_TYPE_NAMES:
        return PROTO_TYPE_NAMES[field.type]
    if field.type == descriptor_pb2.FieldDescriptorProto.TYPE_ENUM:
        return type_name_tail(field.type_name, file_desc.package)
    if field.type == descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE:
        if field.type_name in map_entries:
            entry = map_entries[field.type_name]
            key = entry.field[0]
            value = entry.field[1]
            return 'map<' + field_type_text(key, file_desc, map_entries) + ', ' + field_type_text(value, file_desc, map_entries) + '>'
        return type_name_tail(field.type_name, file_desc.package)
    raise ValueError(f'unsupported descriptor field type {field.type} for {field.name}')


def reserved_lines(prefix: str, reserved_ranges, reserved_names) -> list[str]:
    lines: list[str] = []
    for reserved in reserved_ranges:
        start = reserved.start
        # DescriptorProto reserved ranges use exclusive `end`. Protobuf source uses inclusive end.
        end = reserved.end - 1
        if end < start:
            end = start
        text = str(start) if start == end else f'{start} to {end}'
        lines.append(f'{prefix}reserved {text};')
    if reserved_names:
        names = ', '.join(json.dumps(name) for name in reserved_names)
        lines.append(f'{prefix}reserved {names};')
    return lines


def enum_to_proto(enum_desc: descriptor_pb2.EnumDescriptorProto) -> list[str]:
    lines = [f'enum {enum_desc.name} {{']
    lines.extend(reserved_lines('  ', enum_desc.reserved_range, enum_desc.reserved_name))
    for value in enum_desc.value:
        lines.append(f'  {value.name} = {value.number};')
    lines.append('}')
    return lines


def message_to_proto(
    message: descriptor_pb2.DescriptorProto,
    file_desc: descriptor_pb2.FileDescriptorProto,
    map_entries: dict[str, descriptor_pb2.DescriptorProto],
) -> list[str]:
    lines = [f'message {message.name} {{']
    lines.extend(reserved_lines('  ', message.reserved_range, message.reserved_name))
    oneof_names = [oneof.name for oneof in message.oneof_decl]
    fields_by_oneof: dict[int, list[descriptor_pb2.FieldDescriptorProto]] = {}
    emitted_oneof: set[int] = set()
    for field in message.field:
        if field.HasField('oneof_index') and not getattr(field, 'proto3_optional', False):
            fields_by_oneof.setdefault(field.oneof_index, []).append(field)
    for field in message.field:
        if field.type == descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE and field.type_name in map_entries:
            # Emit as `map<...>` instead of leaking synthetic map-entry messages.
            pass
        label = ''
        if field.label == descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED:
            label = 'repeated '
        elif getattr(field, 'proto3_optional', False):
            label = 'optional '
        if field.HasField('oneof_index') and not getattr(field, 'proto3_optional', False):
            idx = field.oneof_index
            if idx in emitted_oneof:
                continue
            emitted_oneof.add(idx)
            group = oneof_names[idx] if idx < len(oneof_names) else f'oneof_{idx}'
            lines.append(f'  oneof {group} {{')
            for oneof_field in fields_by_oneof.get(idx, []):
                typ = field_type_text(oneof_field, file_desc, map_entries)
                lines.append(f'    {typ} {oneof_field.name} = {oneof_field.number};')
            lines.append('  }')
        else:
            typ = field_type_text(field, file_desc, map_entries)
            if typ.startswith('map<'):
                label = ''
            lines.append(f'  {label}{typ} {field.name} = {field.number};')
    lines.append('}')
    return lines


def descriptor_set_to_proto_text(fds: descriptor_pb2.FileDescriptorSet) -> str:
    if not fds.file:
        raise ValueError('descriptor set contains no files')
    chunks: list[str] = []
    for file_desc in fds.file:
        syntax = file_desc.syntax or 'proto3'
        chunks.append(f'syntax = {json.dumps(syntax)};')
        if file_desc.package:
            chunks.append(f'package {file_desc.package};')
        chunks.append('')
        map_entries = build_map_entry_index(file_desc)
        for enum_desc in file_desc.enum_type:
            chunks.extend(enum_to_proto(enum_desc))
            chunks.append('')
        for message in file_desc.message_type:
            if message.options.map_entry:
                continue
            chunks.extend(message_to_proto(message, file_desc, map_entries))
            chunks.append('')
    return '\n'.join(chunks).strip() + '\n'


FIXTURE_VARIANTS = ('user', 'user_v2', 'user_reserved_v2', 'user_breaking')


def fixture_user_descriptor_set(variant: str = 'user') -> descriptor_pb2.FileDescriptorSet:
    if variant not in FIXTURE_VARIANTS:
        raise ValueError(f'unknown fixture variant: {variant}')
    f = descriptor_pb2.FileDescriptorProto(
        name=f'examples/simple/{variant}.proto',
        package='demo',
        syntax='proto3',
    )
    user = f.message_type.add(name='User')
    id_type = descriptor_pb2.FieldDescriptorProto.TYPE_STRING if variant == 'user_breaking' else descriptor_pb2.FieldDescriptorProto.TYPE_UINT32
    user.field.add(name='id', number=1, label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL, type=id_type)
    user.field.add(name='name', number=2, label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL, type=descriptor_pb2.FieldDescriptorProto.TYPE_STRING)
    user.field.add(name='tags', number=3, label=descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED, type=descriptor_pb2.FieldDescriptorProto.TYPE_STRING)
    counters = user.nested_type.add(name='CountersEntry')
    counters.options.map_entry = True
    counters.field.add(name='key', number=1, label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL, type=descriptor_pb2.FieldDescriptorProto.TYPE_STRING)
    counters.field.add(name='value', number=2, label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL, type=descriptor_pb2.FieldDescriptorProto.TYPE_UINT64)
    user.field.add(
        name='counters',
        number=4,
        label=descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED,
        type=descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE,
        type_name='.demo.User.CountersEntry',
    )
    user.oneof_decl.add(name='contact')
    user.field.add(name='email', number=5, label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL, type=descriptor_pb2.FieldDescriptorProto.TYPE_STRING, oneof_index=0)
    if variant == 'user_reserved_v2':
        reserved = user.reserved_range.add()
        reserved.start = 6
        reserved.end = 7  # Descriptor ranges are exclusive at the end.
        user.reserved_name.append('phone')
    else:
        user.field.add(name='phone', number=6, label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL, type=descriptor_pb2.FieldDescriptorProto.TYPE_STRING, oneof_index=0)
    if variant in {'user_v2', 'user_reserved_v2'}:
        user.field.add(name='created_at', number=9, label=descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL, type=descriptor_pb2.FieldDescriptorProto.TYPE_UINT64)
    return descriptor_pb2.FileDescriptorSet(file=[f])


def summary(fds: descriptor_pb2.FileDescriptorSet) -> str:
    lines = ['descriptor set valid', f'files: {len(fds.file)}']
    for file_desc in fds.file:
        lines.append(f'file: {file_desc.name}')
        lines.append(f'  syntax: {file_desc.syntax or "proto3"}')
        lines.append(f'  package: {file_desc.package}')
        lines.append(f'  messages: {len(file_desc.message_type)}')
        lines.append(f'  enums: {len(file_desc.enum_type)}')
        for message in file_desc.message_type:
            lines.append(f'  message {message.name} fields={len(message.field)} nested={len(message.nested_type)} oneofs={len(message.oneof_decl)}')
        for enum_desc in file_desc.enum_type:
            lines.append(f'  enum {enum_desc.name} values={len(enum_desc.value)}')
    return '\n'.join(lines) + '\n'


def descriptor_report(path: Path, fds: descriptor_pb2.FileDescriptorSet, proto_text: str, steps: list[DescriptorStep]) -> str:
    ok = all(step.ok for step in steps)
    lines = [
        '# Moon Proto Lab descriptor set report',
        '',
        f'- Descriptor input: `{path}`',
        f'- Generated at: `{datetime.now(timezone.utc).isoformat()}`',
        f'- Overall status: **{"PASS" if ok else "FAIL"}**',
        f'- Files: `{len(fds.file)}`',
        '',
        '## Steps',
        '',
        '| Step | Status | Details |',
        '| --- | --- | --- |',
    ]
    for step in steps:
        details = step.details.replace('|', '\\|').replace('\n', '<br>')
        lines.append(f'| {step.name} | {"PASS" if step.ok else "FAIL"} | {details} |')
    lines.extend([
        '',
        '## Descriptor summary',
        '',
        '```text',
        summary(fds).strip(),
        '```',
        '',
        '## Reconstructed proto preview',
        '',
        '```proto',
        proto_text.strip(),
        '```',
    ])
    return '\n'.join(lines) + '\n'


def descriptor_compat_report(
    old_path: Path,
    new_path: Path,
    old_fds: descriptor_pb2.FileDescriptorSet,
    new_fds: descriptor_pb2.FileDescriptorSet,
    old_proto: str,
    new_proto: str,
    compat_output: str,
    steps: list[DescriptorStep],
) -> str:
    ok = all(step.ok for step in steps)
    lines = [
        '# Moon Proto Lab descriptor set compatibility report',
        '',
        f'- Old descriptor input: `{old_path}`',
        f'- New descriptor input: `{new_path}`',
        f'- Generated at: `{datetime.now(timezone.utc).isoformat()}`',
        f'- Overall status: **{"PASS" if ok else "FAIL"}**',
        f'- Old files: `{len(old_fds.file)}`',
        f'- New files: `{len(new_fds.file)}`',
        '',
        '## Steps',
        '',
        '| Step | Status | Details |',
        '| --- | --- | --- |',
    ]
    for step in steps:
        details = step.details.replace('|', '\\|').replace('\n', '<br>')
        lines.append(f'| {step.name} | {"PASS" if step.ok else "FAIL"} | {details} |')
    lines.extend([
        '',
        '## Compatibility output',
        '',
        '```text',
        compat_output.strip(),
        '```',
        '',
        '## Old descriptor summary',
        '',
        '```text',
        summary(old_fds).strip(),
        '```',
        '',
        '## New descriptor summary',
        '',
        '```text',
        summary(new_fds).strip(),
        '```',
        '',
        '## Old reconstructed proto preview',
        '',
        '```proto',
        old_proto.strip(),
        '```',
        '',
        '## New reconstructed proto preview',
        '',
        '```proto',
        new_proto.strip(),
        '```',
    ])
    return '\n'.join(lines) + '\n'


def registry_manifest(
    name: str,
    versions: list[RegistryVersion],
    edges: list[RegistryEdge],
) -> dict:
    return {
        'name': name,
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'overall_status': 'PASS' if all(v.ok for v in versions) and all(e.compatible for e in edges) else 'FAIL',
        'versions': [
            {
                'index': version.index,
                'path': str(version.path),
                'status': 'PASS' if version.ok else 'FAIL',
                'sha256': version.digest,
                'files': version.files,
                'packages': version.packages,
                'messages': version.messages,
                'enums': version.enums,
                'details': version.details,
            }
            for version in versions
        ],
        'compatibility_edges': [
            {
                'old_index': edge.old_index,
                'new_index': edge.new_index,
                'old_path': str(edge.old_path),
                'new_path': str(edge.new_path),
                'status': 'PASS' if edge.compatible else 'FAIL',
                'output': edge.output,
            }
            for edge in edges
        ],
    }


def descriptor_registry_report(
    name: str,
    versions: list[RegistryVersion],
    edges: list[RegistryEdge],
) -> str:
    ok = all(version.ok for version in versions) and all(edge.compatible for edge in edges)
    lines = [
        '# Moon Proto Lab descriptor registry report',
        '',
        f'- Registry: `{name}`',
        f'- Generated at: `{datetime.now(timezone.utc).isoformat()}`',
        f'- Overall status: **{"PASS" if ok else "FAIL"}**',
        f'- Versions: `{len(versions)}`',
        f'- Compatibility edges: `{len(edges)}`',
        '',
        '## Imported versions',
        '',
        '| Version | Status | Input | SHA-256 | Files | Packages | Messages | Enums | Details |',
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    ]
    for version in versions:
        lines.append(
            '| '
            + ' | '.join([
                str(version.index),
                'PASS' if version.ok else 'FAIL',
                f'`{version.path}`',
                f'`{version.digest[:16]}`',
                markdown_table_cell(', '.join(version.files)),
                markdown_table_cell(', '.join(version.packages)),
                markdown_table_cell(', '.join(version.messages)),
                markdown_table_cell(', '.join(version.enums)),
                markdown_table_cell(version.details),
            ])
            + ' |'
        )
    lines.extend([
        '',
        '## Adjacent compatibility checks',
        '',
        '| Old | New | Status | Diagnostics |',
        '| --- | --- | --- | --- |',
    ])
    for edge in edges:
        diagnostics = edge.output.strip() or 'no output'
        lines.append(
            f'| {edge.old_index} `{edge.old_path.name}` | '
            f'{edge.new_index} `{edge.new_path.name}` | '
            f'{"PASS" if edge.compatible else "FAIL"} | '
            f'{markdown_table_cell(diagnostics)} |'
        )
    lines.extend([
        '',
        '## Reconstructed proto previews',
    ])
    for version in versions:
        preview = '\n'.join(version.proto_text.splitlines()[:80])
        lines.extend([
            '',
            f'### Version {version.index}: `{version.path}`',
            '',
            '```proto',
            preview.strip(),
            '```',
        ])
    return '\n'.join(lines) + '\n'


def write_text_report(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() in {'.html', '.htm'}:
        path.write_text('<!doctype html>\n<pre>' + html.escape(text) + '</pre>\n', encoding='utf-8')
    else:
        path.write_text(text, encoding='utf-8')


def command_fixture(args: argparse.Namespace) -> int:
    fds = fixture_user_descriptor_set(args.variant)
    if args.output:
        write_descriptor_set(Path(args.output), fds)
        print(args.output)
    if args.json_out:
        write_descriptor_set(Path(args.json_out), fds)
        print(args.json_out)
    if args.hex_out:
        write_descriptor_set(Path(args.hex_out), fds)
        print(args.hex_out)
    if not args.output and not args.json_out and not args.hex_out:
        print(fds.SerializeToString().hex())
    return 0


def command_inspect(args: argparse.Namespace) -> int:
    fds = load_descriptor_set(Path(args.descriptor))
    text = summary(fds)
    print(text, end='')
    if args.report:
        proto_text = descriptor_set_to_proto_text(fds)
        write_text_report(Path(args.report), descriptor_report(Path(args.descriptor), fds, proto_text, [DescriptorStep('descriptor parse', True, 'descriptor set parsed')]))
        print(f'report: {args.report}')
    return 0


def command_to_proto(args: argparse.Namespace) -> int:
    fds = load_descriptor_set(Path(args.descriptor))
    proto_text = descriptor_set_to_proto_text(fds)
    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(proto_text, encoding='utf-8')
        print(out)
    else:
        print(proto_text, end='')
    return 0


def command_compat(args: argparse.Namespace) -> int:
    root = repo_root()
    old_path = Path(args.old_descriptor)
    new_path = Path(args.new_descriptor)
    steps: list[DescriptorStep] = []
    compat_output = ''
    try:
        old_fds = load_descriptor_set(old_path)
        steps.append(DescriptorStep('old descriptor parse', True, f'{len(old_fds.file)} file(s) parsed'))
        new_fds = load_descriptor_set(new_path)
        steps.append(DescriptorStep('new descriptor parse', True, f'{len(new_fds.file)} file(s) parsed'))
        old_proto = descriptor_set_to_proto_text(old_fds)
        steps.append(DescriptorStep('old descriptor to proto', True, f'{len(old_proto.splitlines())} proto lines'))
        new_proto = descriptor_set_to_proto_text(new_fds)
        steps.append(DescriptorStep('new descriptor to proto', True, f'{len(new_proto.splitlines())} proto lines'))
    except Exception as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 2

    compatible = False
    try:
        compat_output = run_moon_compat(old_proto, new_proto, args.moon_bin, root)
        compatible = schema_is_compatible(compat_output)
        first_line = compat_output.splitlines()[0] if compat_output else 'no output'
        steps.append(DescriptorStep('schema compatibility', compatible, first_line))
    except RuntimeError as exc:
        compat_output = str(exc)
        steps.append(DescriptorStep('schema compatibility', False, compat_output))

    if args.report:
        write_text_report(
            Path(args.report),
            descriptor_compat_report(
                old_path,
                new_path,
                old_fds,
                new_fds,
                old_proto,
                new_proto,
                compat_output,
                steps,
            ),
        )
        print(f'report: {args.report}')
    print(compat_output, end='' if compat_output.endswith('\n') else '\n')
    print('Moon Proto Lab descriptor compat: ' + ('PASS' if compatible else 'FAIL'))
    return 0 if compatible else 1


DESCRIPTOR_INPUT_SUFFIXES = {'.bin', '.pb', '.hex', '.json'}


def expand_registry_inputs(inputs: list[str]) -> list[Path]:
    paths: list[Path] = []
    for item in inputs:
        path = Path(item)
        if path.is_dir():
            for child in sorted(path.iterdir()):
                if child.is_file() and child.suffix.lower() in DESCRIPTOR_INPUT_SUFFIXES:
                    paths.append(child)
        else:
            paths.append(path)
    return paths


def command_registry(args: argparse.Namespace) -> int:
    root = repo_root()
    paths = expand_registry_inputs(args.descriptors)
    if not paths:
        print('error: descriptor registry input is empty', file=sys.stderr)
        return 2

    versions: list[RegistryVersion] = []
    for index, path in enumerate(paths):
        try:
            fds = load_descriptor_set(path)
            proto_text = descriptor_set_to_proto_text(fds)
            files, packages, messages, enums = collect_schema_names(fds)
            doctor = run_moon_doctor(proto_text, args.moon_bin, root)
            ok = schema_is_valid(doctor)
            details = doctor.splitlines()[0] if doctor else 'no output'
            versions.append(RegistryVersion(
                index=index,
                path=path,
                ok=ok,
                digest=descriptor_digest(fds),
                files=files,
                packages=packages,
                messages=messages,
                enums=enums,
                proto_text=proto_text,
                details=details,
            ))
        except Exception as exc:
            versions.append(RegistryVersion(
                index=index,
                path=path,
                ok=False,
                digest='',
                files=[],
                packages=[],
                messages=[],
                enums=[],
                proto_text='',
                details=str(exc),
            ))

    edges: list[RegistryEdge] = []
    for index in range(1, len(versions)):
        old = versions[index - 1]
        new = versions[index]
        if old.ok and new.ok:
            try:
                output = run_moon_compat(old.proto_text, new.proto_text, args.moon_bin, root)
                compatible = schema_is_compatible(output)
            except RuntimeError as exc:
                output = str(exc)
                compatible = False
        else:
            output = 'skipped because one side failed descriptor import or schema doctor'
            compatible = False
        edges.append(RegistryEdge(
            old_index=old.index,
            new_index=new.index,
            old_path=old.path,
            new_path=new.path,
            compatible=compatible,
            output=output,
        ))

    ok = all(version.ok for version in versions) and all(edge.compatible for edge in edges)
    if args.report:
        write_text_report(Path(args.report), descriptor_registry_report(args.name, versions, edges))
        print(f'report: {args.report}')
    if args.json_out:
        out = Path(args.json_out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(registry_manifest(args.name, versions, edges), indent=2, sort_keys=True) + '\n', encoding='utf-8')
        print(f'json: {args.json_out}')

    print('Moon Proto Lab descriptor registry: ' + ('PASS' if ok else 'FAIL'))
    print(f'versions: {len(versions)}')
    print(f'compatibility edges: {len(edges)}')
    for version in versions:
        print(f'- version {version.index}: {"PASS" if version.ok else "FAIL"} {version.path} {version.details}')
    for edge in edges:
        first = edge.output.splitlines()[0] if edge.output else 'no output'
        print(f'- edge {edge.old_index}->{edge.new_index}: {"PASS" if edge.compatible else "FAIL"} {first}')
    return 0 if ok else 1


def command_verify(args: argparse.Namespace) -> int:
    root = repo_root()
    descriptor_path = Path(args.descriptor)
    steps: list[DescriptorStep] = []
    try:
        fds = load_descriptor_set(descriptor_path)
        steps.append(DescriptorStep('descriptor parse', True, f'{len(fds.file)} file(s) parsed'))
        proto_text = descriptor_set_to_proto_text(fds)
        steps.append(DescriptorStep('descriptor to proto', True, f'{len(proto_text.splitlines())} proto lines'))
    except Exception as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1

    valid = False
    try:
        doctor = run_moon_doctor(proto_text, args.moon_bin, root)
        valid = schema_is_valid(doctor)
        steps.append(DescriptorStep('schema doctor', valid, doctor.splitlines()[0] if doctor else 'no output'))
    except RuntimeError as exc:
        steps.append(DescriptorStep('schema doctor', False, str(exc)))

    if valid:
        try:
            inspect = run_moon_inspect(proto_text, args.moon_bin, root)
            steps.append(DescriptorStep('schema inspect', True, inspect.splitlines()[0] if inspect else 'summary generated'))
        except RuntimeError as exc:
            steps.append(DescriptorStep('schema inspect', False, str(exc)))
            valid = False

    if valid:
        try:
            generated = run_moon_codegen(proto_text, args.moon_bin, root)
            steps.append(DescriptorStep('codegen', True, f'{len(generated.splitlines())} generated lines'))
            if not args.skip_compile:
                compile_out = compile_generated_source(generated, args.moon_bin, root)
                steps.append(DescriptorStep('generated-code compile', True, compile_out.splitlines()[0] if compile_out else 'moon check passed'))
            else:
                steps.append(DescriptorStep('generated-code compile', True, 'skipped by --skip-compile'))
        except RuntimeError as exc:
            steps.append(DescriptorStep('codegen/compile', False, str(exc)))

    ok = all(step.ok for step in steps)
    if args.report:
        write_text_report(Path(args.report), descriptor_report(descriptor_path, fds, proto_text, steps))
        print(f'report: {args.report}')
    print('Moon Proto Lab descriptor verify: ' + ('PASS' if ok else 'FAIL'))
    for step in steps:
        print(f'- {step.name}: {"PASS" if step.ok else "FAIL"} - {step.details.splitlines()[0]}')
    return 0 if ok else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Moon Proto Lab FileDescriptorSet utilities')
    sub = parser.add_subparsers(dest='command', required=True)

    fixture = sub.add_parser('fixture', help='write a deterministic user FileDescriptorSet fixture')
    fixture.add_argument('--variant', choices=FIXTURE_VARIANTS, default='user', help='fixture variant to write')
    fixture.add_argument('--output', help='binary/json/hex descriptor output path, inferred by suffix')
    fixture.add_argument('--json-out', help='also write JSON descriptor')
    fixture.add_argument('--hex-out', help='also write hex descriptor')
    fixture.set_defaults(func=command_fixture)

    inspect = sub.add_parser('inspect', help='inspect a FileDescriptorSet')
    inspect.add_argument('descriptor')
    inspect.add_argument('--report')
    inspect.set_defaults(func=command_inspect)

    to_proto = sub.add_parser('to-proto', help='convert a FileDescriptorSet to a proto3 schema subset')
    to_proto.add_argument('descriptor')
    to_proto.add_argument('-o', '--output')
    to_proto.set_defaults(func=command_to_proto)

    compat = sub.add_parser('compat', help='compare two FileDescriptorSet inputs for protobuf schema compatibility')
    compat.add_argument('old_descriptor')
    compat.add_argument('new_descriptor')
    compat.add_argument('--report')
    compat.add_argument('--moon-bin', default='moon')
    compat.set_defaults(func=command_compat)

    registry = sub.add_parser('registry', help='import descriptor versions into a small registry and check adjacent compatibility')
    registry.add_argument('descriptors', nargs='+', help='descriptor files or directories, ordered from oldest to newest')
    registry.add_argument('--name', default='moon-proto-lab-registry')
    registry.add_argument('--report')
    registry.add_argument('--json-out')
    registry.add_argument('--moon-bin', default='moon')
    registry.set_defaults(func=command_registry)

    verify = sub.add_parser('verify', help='convert descriptor set and run doctor/codegen/compile checks')
    verify.add_argument('descriptor')
    verify.add_argument('--report')
    verify.add_argument('--skip-compile', action='store_true')
    verify.add_argument('--moon-bin', default='moon')
    verify.set_defaults(func=command_verify)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    raise SystemExit(main())
