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
BAG_BIN = FIXTURES / "bag_maps.bin"
BAG_HEX = FIXTURES / "bag_maps.hex"
BAG_JSON = FIXTURES / "bag_maps.json"
CONTACT_BIN = FIXTURES / "contact_oneof.bin"
CONTACT_HEX = FIXTURES / "contact_oneof.hex"
CONTACT_JSON = FIXTURES / "contact_oneof.json"


def _field(
    message,
    name: str,
    number: int,
    typ: int,
    label: int,
    oneof_index: int | None = None,
) -> None:
    field = message.field.add()
    field.name = name
    field.number = number
    field.type = typ
    field.label = label
    if oneof_index is not None:
        field.oneof_index = oneof_index


def _message_field(
    message,
    name: str,
    number: int,
    type_name: str,
    label: int,
) -> None:
    field = message.field.add()
    field.name = name
    field.number = number
    field.type = descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE
    field.type_name = type_name
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


def make_bag_message_class():
    file_desc = descriptor_pb2.FileDescriptorProto(
        name="moon_proto_map_oracle.proto",
        package="demo",
        syntax="proto3",
    )
    msg = file_desc.message_type.add()
    msg.name = "Bag"
    label_optional = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    label_repeated = descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED

    scores_entry = msg.nested_type.add()
    scores_entry.name = "ScoresEntry"
    scores_entry.options.map_entry = True
    _field(
        scores_entry,
        "key",
        1,
        descriptor_pb2.FieldDescriptorProto.TYPE_STRING,
        label_optional,
    )
    _field(
        scores_entry,
        "value",
        2,
        descriptor_pb2.FieldDescriptorProto.TYPE_UINT64,
        label_optional,
    )

    labels_entry = msg.nested_type.add()
    labels_entry.name = "LabelsEntry"
    labels_entry.options.map_entry = True
    _field(
        labels_entry,
        "key",
        1,
        descriptor_pb2.FieldDescriptorProto.TYPE_INT64,
        label_optional,
    )
    _field(
        labels_entry,
        "value",
        2,
        descriptor_pb2.FieldDescriptorProto.TYPE_STRING,
        label_optional,
    )

    _message_field(msg, "scores", 1, ".demo.Bag.ScoresEntry", label_repeated)
    _message_field(msg, "labels", 2, ".demo.Bag.LabelsEntry", label_repeated)

    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_desc)
    descriptor = pool.FindMessageTypeByName("demo.Bag")
    factory = message_factory.MessageFactory(pool)
    return factory.GetPrototype(descriptor)


def make_bag():
    Bag = make_bag_message_class()
    bag = Bag()
    bag.scores["alice"] = 150
    bag.scores["bob"] = 7
    bag.labels[2] = "two"
    bag.labels[7] = "seven"
    return bag


def make_contact_message_class():
    file_desc = descriptor_pb2.FileDescriptorProto(
        name="moon_proto_oneof_oracle.proto",
        package="demo",
        syntax="proto3",
    )
    msg = file_desc.message_type.add()
    msg.name = "Contact"
    msg.oneof_decl.add().name = "reach"
    label_optional = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    _field(msg, "id", 1, descriptor_pb2.FieldDescriptorProto.TYPE_UINT64, label_optional)
    _field(
        msg,
        "email",
        2,
        descriptor_pb2.FieldDescriptorProto.TYPE_STRING,
        label_optional,
        oneof_index=0,
    )
    _field(
        msg,
        "phone",
        3,
        descriptor_pb2.FieldDescriptorProto.TYPE_STRING,
        label_optional,
        oneof_index=0,
    )

    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_desc)
    descriptor = pool.FindMessageTypeByName("demo.Contact")
    factory = message_factory.MessageFactory(pool)
    return factory.GetPrototype(descriptor)


def make_contact():
    Contact = make_contact_message_class()
    return Contact(id=1, phone="123")


def oracle_values():
    user = make_user()
    binary = user.SerializeToString(deterministic=True)
    data = json_format.MessageToDict(user, preserving_proto_field_name=True)
    canonical_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    return binary, binary.hex() + "\n", canonical_json


def bag_oracle_values():
    bag = make_bag()
    binary = bag.SerializeToString(deterministic=True)
    data = json_format.MessageToDict(bag, preserving_proto_field_name=True)
    canonical_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    return binary, binary.hex() + "\n", canonical_json


def contact_oracle_values():
    contact = make_contact()
    binary = contact.SerializeToString(deterministic=True)
    data = json_format.MessageToDict(contact, preserving_proto_field_name=True)
    canonical_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    return binary, binary.hex() + "\n", canonical_json


def write_fixtures() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    binary, hex_text, json_text = oracle_values()
    BIN.write_bytes(binary)
    HEX.write_text(hex_text, encoding="utf-8")
    JSON.write_text(json_text, encoding="utf-8")
    bag_binary, bag_hex_text, bag_json_text = bag_oracle_values()
    BAG_BIN.write_bytes(bag_binary)
    BAG_HEX.write_text(bag_hex_text, encoding="utf-8")
    BAG_JSON.write_text(bag_json_text, encoding="utf-8")
    contact_binary, contact_hex_text, contact_json_text = contact_oracle_values()
    CONTACT_BIN.write_bytes(contact_binary)
    CONTACT_HEX.write_text(contact_hex_text, encoding="utf-8")
    CONTACT_JSON.write_text(contact_json_text, encoding="utf-8")


def verify_fixtures() -> None:
    binary, hex_text, json_text = oracle_values()
    bag_binary, bag_hex_text, bag_json_text = bag_oracle_values()
    contact_binary, contact_hex_text, contact_json_text = contact_oracle_values()
    checks = [
        (BIN, binary, BIN.read_bytes() if BIN.exists() else None),
        (HEX, hex_text, HEX.read_text(encoding="utf-8") if HEX.exists() else None),
        (JSON, json_text, JSON.read_text(encoding="utf-8") if JSON.exists() else None),
        (BAG_BIN, bag_binary, BAG_BIN.read_bytes() if BAG_BIN.exists() else None),
        (
            BAG_HEX,
            bag_hex_text,
            BAG_HEX.read_text(encoding="utf-8") if BAG_HEX.exists() else None,
        ),
        (
            BAG_JSON,
            bag_json_text,
            BAG_JSON.read_text(encoding="utf-8") if BAG_JSON.exists() else None,
        ),
        (
            CONTACT_BIN,
            contact_binary,
            CONTACT_BIN.read_bytes() if CONTACT_BIN.exists() else None,
        ),
        (
            CONTACT_HEX,
            contact_hex_text,
            CONTACT_HEX.read_text(encoding="utf-8") if CONTACT_HEX.exists() else None,
        ),
        (
            CONTACT_JSON,
            contact_json_text,
            CONTACT_JSON.read_text(encoding="utf-8") if CONTACT_JSON.exists() else None,
        ),
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
    print("bag_maps.hex", bag_hex_text.strip())
    print("bag_maps.json", bag_json_text.strip())
    print("contact_oneof.hex", contact_hex_text.strip())
    print("contact_oneof.json", contact_json_text.strip())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="rewrite checked-in fixtures")
    args = parser.parse_args()
    if args.write:
        write_fixtures()
    verify_fixtures()


if __name__ == "__main__":
    main()
