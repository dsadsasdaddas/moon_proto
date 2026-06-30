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

if not hasattr(message_factory.MessageFactory, "GetPrototype"):
    def _message_factory_get_prototype(self, descriptor):
        return message_factory.GetMessageClass(descriptor)

    message_factory.MessageFactory.GetPrototype = _message_factory_get_prototype

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
NUMBERS32_BIN = FIXTURES / "numbers32.bin"
NUMBERS32_HEX = FIXTURES / "numbers32.hex"
NUMBERS32_JSON = FIXTURES / "numbers32.json"
FLOATS_BIN = FIXTURES / "floats.bin"
FLOATS_HEX = FIXTURES / "floats.hex"
FLOATS_JSON = FIXTURES / "floats.json"
FLOAT_SPECIALS_BIN = FIXTURES / "float_specials.bin"
FLOAT_SPECIALS_HEX = FIXTURES / "float_specials.hex"
FLOAT_SPECIALS_JSON = FIXTURES / "float_specials.json"


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


def make_numbers32_message_class():
    file_desc = descriptor_pb2.FileDescriptorProto(
        name="moon_proto_numbers32_oracle.proto",
        package="demo",
        syntax="proto3",
    )
    msg = file_desc.message_type.add()
    msg.name = "Numbers32"
    label_optional = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    _field(msg, "u", 1, descriptor_pb2.FieldDescriptorProto.TYPE_UINT32, label_optional)
    _field(msg, "i", 2, descriptor_pb2.FieldDescriptorProto.TYPE_INT32, label_optional)
    _field(msg, "s", 3, descriptor_pb2.FieldDescriptorProto.TYPE_SINT32, label_optional)
    _field(msg, "f", 4, descriptor_pb2.FieldDescriptorProto.TYPE_FIXED32, label_optional)
    _field(msg, "sf", 5, descriptor_pb2.FieldDescriptorProto.TYPE_SFIXED32, label_optional)

    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_desc)
    descriptor = pool.FindMessageTypeByName("demo.Numbers32")
    factory = message_factory.MessageFactory(pool)
    return factory.GetPrototype(descriptor)


def make_numbers32():
    Numbers32 = make_numbers32_message_class()
    return Numbers32(u=4294967295, i=-1, s=-2, f=4294967295, sf=-3)


def make_floats_message_class():
    file_desc = descriptor_pb2.FileDescriptorProto(
        name="moon_proto_floats_oracle.proto",
        package="demo",
        syntax="proto3",
    )
    msg = file_desc.message_type.add()
    msg.name = "Floats"
    label_optional = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    _field(msg, "f", 1, descriptor_pb2.FieldDescriptorProto.TYPE_FLOAT, label_optional)
    _field(msg, "d", 2, descriptor_pb2.FieldDescriptorProto.TYPE_DOUBLE, label_optional)

    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_desc)
    descriptor = pool.FindMessageTypeByName("demo.Floats")
    factory = message_factory.MessageFactory(pool)
    return factory.GetPrototype(descriptor)


def make_floats():
    Floats = make_floats_message_class()
    return Floats(f=1.5, d=-2.25)


def make_float_specials_message_class():
    file_desc = descriptor_pb2.FileDescriptorProto(
        name="moon_proto_float_specials_oracle.proto",
        package="demo",
        syntax="proto3",
    )
    msg = file_desc.message_type.add()
    msg.name = "FloatSpecials"
    label_optional = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    _field(msg, "f_nan", 1, descriptor_pb2.FieldDescriptorProto.TYPE_FLOAT, label_optional)
    _field(msg, "f_inf", 2, descriptor_pb2.FieldDescriptorProto.TYPE_FLOAT, label_optional)
    _field(msg, "d_neg_inf", 3, descriptor_pb2.FieldDescriptorProto.TYPE_DOUBLE, label_optional)

    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_desc)
    descriptor = pool.FindMessageTypeByName("demo.FloatSpecials")
    factory = message_factory.MessageFactory(pool)
    return factory.GetPrototype(descriptor)


def make_float_specials():
    FloatSpecials = make_float_specials_message_class()
    return FloatSpecials(f_nan=float("nan"), f_inf=float("inf"), d_neg_inf=float("-inf"))


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


def numbers32_oracle_values():
    numbers = make_numbers32()
    binary = numbers.SerializeToString(deterministic=True)
    data = json_format.MessageToDict(numbers, preserving_proto_field_name=True)
    canonical_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    return binary, binary.hex() + "\n", canonical_json


def floats_oracle_values():
    floats = make_floats()
    binary = floats.SerializeToString(deterministic=True)
    data = json_format.MessageToDict(floats, preserving_proto_field_name=True)
    canonical_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    return binary, binary.hex() + "\n", canonical_json


def float_specials_oracle_values():
    specials = make_float_specials()
    binary = specials.SerializeToString(deterministic=True)
    data = json_format.MessageToDict(specials, preserving_proto_field_name=True)
    canonical_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    return binary, binary.hex() + "\n", canonical_json


def message_dict(message_class, data: bytes):
    message = message_class()
    message.ParseFromString(data)
    return json_format.MessageToDict(message, preserving_proto_field_name=True)


def binary_equivalent(message_class, left: bytes, right: bytes) -> bool:
    return message_dict(message_class, left) == message_dict(message_class, right)


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
    numbers32_binary, numbers32_hex_text, numbers32_json_text = numbers32_oracle_values()
    NUMBERS32_BIN.write_bytes(numbers32_binary)
    NUMBERS32_HEX.write_text(numbers32_hex_text, encoding="utf-8")
    NUMBERS32_JSON.write_text(numbers32_json_text, encoding="utf-8")
    floats_binary, floats_hex_text, floats_json_text = floats_oracle_values()
    FLOATS_BIN.write_bytes(floats_binary)
    FLOATS_HEX.write_text(floats_hex_text, encoding="utf-8")
    FLOATS_JSON.write_text(floats_json_text, encoding="utf-8")
    specials_binary, specials_hex_text, specials_json_text = float_specials_oracle_values()
    FLOAT_SPECIALS_BIN.write_bytes(specials_binary)
    FLOAT_SPECIALS_HEX.write_text(specials_hex_text, encoding="utf-8")
    FLOAT_SPECIALS_JSON.write_text(specials_json_text, encoding="utf-8")


def verify_fixtures() -> None:
    binary, hex_text, json_text = oracle_values()
    bag_binary, bag_hex_text, bag_json_text = bag_oracle_values()
    contact_binary, contact_hex_text, contact_json_text = contact_oracle_values()
    numbers32_binary, numbers32_hex_text, numbers32_json_text = numbers32_oracle_values()
    floats_binary, floats_hex_text, floats_json_text = floats_oracle_values()
    specials_binary, specials_hex_text, specials_json_text = float_specials_oracle_values()
    checks = [
        (BIN, binary, BIN.read_bytes() if BIN.exists() else None),
        (HEX, hex_text, HEX.read_text(encoding="utf-8") if HEX.exists() else None),
        (JSON, json_text, JSON.read_text(encoding="utf-8") if JSON.exists() else None),
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
        (
            NUMBERS32_BIN,
            numbers32_binary,
            NUMBERS32_BIN.read_bytes() if NUMBERS32_BIN.exists() else None,
        ),
        (
            NUMBERS32_HEX,
            numbers32_hex_text,
            NUMBERS32_HEX.read_text(encoding="utf-8") if NUMBERS32_HEX.exists() else None,
        ),
        (
            NUMBERS32_JSON,
            numbers32_json_text,
            NUMBERS32_JSON.read_text(encoding="utf-8") if NUMBERS32_JSON.exists() else None,
        ),
        (
            FLOATS_BIN,
            floats_binary,
            FLOATS_BIN.read_bytes() if FLOATS_BIN.exists() else None,
        ),
        (
            FLOATS_HEX,
            floats_hex_text,
            FLOATS_HEX.read_text(encoding="utf-8") if FLOATS_HEX.exists() else None,
        ),
        (
            FLOATS_JSON,
            floats_json_text,
            FLOATS_JSON.read_text(encoding="utf-8") if FLOATS_JSON.exists() else None,
        ),
        (
            FLOAT_SPECIALS_BIN,
            specials_binary,
            FLOAT_SPECIALS_BIN.read_bytes() if FLOAT_SPECIALS_BIN.exists() else None,
        ),
        (
            FLOAT_SPECIALS_HEX,
            specials_hex_text,
            FLOAT_SPECIALS_HEX.read_text(encoding="utf-8") if FLOAT_SPECIALS_HEX.exists() else None,
        ),
        (
            FLOAT_SPECIALS_JSON,
            specials_json_text,
            FLOAT_SPECIALS_JSON.read_text(encoding="utf-8") if FLOAT_SPECIALS_JSON.exists() else None,
        ),
    ]
    failures = []
    actual_bag_binary = BAG_BIN.read_bytes() if BAG_BIN.exists() else None
    actual_bag_hex_text = BAG_HEX.read_text(encoding="utf-8") if BAG_HEX.exists() else None
    if actual_bag_binary is None:
        failures.append(str(BAG_BIN.relative_to(ROOT)))
    if actual_bag_hex_text is None:
        failures.append(str(BAG_HEX.relative_to(ROOT)))
    if actual_bag_binary is not None and actual_bag_hex_text is not None:
        try:
            actual_bag_from_hex = bytes.fromhex(actual_bag_hex_text.strip())
        except ValueError:
            actual_bag_from_hex = None
            failures.append(str(BAG_HEX.relative_to(ROOT)))
        if actual_bag_from_hex != actual_bag_binary:
            failures.append(str(BAG_HEX.relative_to(ROOT)))
        elif actual_bag_binary != bag_binary and not binary_equivalent(
            make_bag_message_class(),
            actual_bag_binary,
            bag_binary,
        ):
            failures.append(str(BAG_BIN.relative_to(ROOT)))
    actual_bag_json_text = BAG_JSON.read_text(encoding="utf-8") if BAG_JSON.exists() else None
    if actual_bag_json_text is None:
        failures.append(str(BAG_JSON.relative_to(ROOT)))
    else:
        try:
            if json.loads(actual_bag_json_text) != json.loads(bag_json_text):
                failures.append(str(BAG_JSON.relative_to(ROOT)))
        except json.JSONDecodeError:
            failures.append(str(BAG_JSON.relative_to(ROOT)))
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
    print("numbers32.hex", numbers32_hex_text.strip())
    print("numbers32.json", numbers32_json_text.strip())
    print("floats.hex", floats_hex_text.strip())
    print("floats.json", floats_json_text.strip())
    print("float_specials.hex", specials_hex_text.strip())
    print("float_specials.json", specials_json_text.strip())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="rewrite checked-in fixtures")
    args = parser.parse_args()
    if args.write:
        write_fixtures()
    verify_fixtures()


if __name__ == "__main__":
    main()
