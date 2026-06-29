#!/usr/bin/env python3
"""Official Python protobuf oracle for moon_proto golden fixtures.

The script builds descriptors programmatically, so CI does not need protoc.
It verifies that the checked-in binary/JSON fixtures match google.protobuf's
canonical encoder for the same schema and value.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from google.protobuf import descriptor_pb2, descriptor_pool, json_format, message_factory

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests" / "fixtures"
BIN = FIXTURES / "user_full.bin"
HEX = FIXTURES / "user_full.hex"
JSON = FIXTURES / "user_full.json"


def _field(message, name: str, number: int, typ: int, label: int) -> None:
    field = message.field.add()
    field.name = name
    field.number = number
    field.type = typ
    field.label = label


def make_user_message_class():
    file_desc = descriptor_pb2.FileDescriptorProto(
        name="moon_proto_oracle.proto",
        package="demo",
        syntax="proto3",
    )
    msg = file_desc.message_type.add()
    msg.name = "User"
    label_optional = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    label_repeated = descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED
    _field(msg, "id", 1, descriptor_pb2.FieldDescriptorProto.TYPE_UINT64, label_optional)
    _field(msg, "name", 2, descriptor_pb2.FieldDescriptorProto.TYPE_STRING, label_optional)
    _field(msg, "active", 3, descriptor_pb2.FieldDescriptorProto.TYPE_BOOL, label_optional)
    _field(msg, "tags", 4, descriptor_pb2.FieldDescriptorProto.TYPE_STRING, label_repeated)
    _field(msg, "score", 5, descriptor_pb2.FieldDescriptorProto.TYPE_SINT64, label_optional)
    _field(msg, "blob", 6, descriptor_pb2.FieldDescriptorProto.TYPE_BYTES, label_optional)
    _field(msg, "samples", 7, descriptor_pb2.FieldDescriptorProto.TYPE_UINT64, label_repeated)
    _field(msg, "deltas", 8, descriptor_pb2.FieldDescriptorProto.TYPE_SINT64, label_repeated)

    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_desc)
    descriptor = pool.FindMessageTypeByName("demo.User")
    factory = message_factory.MessageFactory(pool)
    return factory.GetPrototype(descriptor)


def make_user():
    User = make_user_message_class()
    user = User(
        id=150,
        name='Alice "A"',
        active=True,
        score=-2,
        blob=b"\xff\x00",
    )
    user.tags.extend(["admin", "tester"])
    user.samples.extend([1, 150])
    user.deltas.extend([-1, 2])
    return user


def oracle_values():
    user = make_user()
    binary = user.SerializeToString()
    data = json_format.MessageToDict(user, preserving_proto_field_name=True)
    canonical_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    return binary, binary.hex() + "\n", canonical_json


def write_fixtures() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    binary, hex_text, json_text = oracle_values()
    BIN.write_bytes(binary)
    HEX.write_text(hex_text, encoding="utf-8")
    JSON.write_text(json_text, encoding="utf-8")


def verify_fixtures() -> None:
    binary, hex_text, json_text = oracle_values()
    checks = [
        (BIN, binary, BIN.read_bytes() if BIN.exists() else None),
        (HEX, hex_text, HEX.read_text(encoding="utf-8") if HEX.exists() else None),
        (JSON, json_text, JSON.read_text(encoding="utf-8") if JSON.exists() else None),
    ]
    failures = []
    for path, expected, actual in checks:
        if actual != expected:
            failures.append(str(path.relative_to(ROOT)))
    if failures:
        raise SystemExit(
            "protobuf oracle fixture mismatch: "
            + ", ".join(failures)
            + "\nRun: python3 tests/oracle/python_protobuf_oracle.py --write"
        )
    print("Python protobuf oracle fixtures verified")
    print("user_full.hex", hex_text.strip())
    print("user_full.json", json_text.strip())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="rewrite checked-in fixtures")
    args = parser.parse_args()
    if args.write:
        write_fixtures()
    verify_fixtures()


if __name__ == "__main__":
    main()
