///|
test "varint golden vectors" {
  assert_eq(encode_varint_u64(0UL), b"\x00")
  assert_eq(encode_varint_u64(1UL), b"\x01")
  assert_eq(encode_varint_u64(127UL), b"\x7f")
  assert_eq(encode_varint_u64(128UL), b"\x80\x01")
  assert_eq(encode_varint_u64(300UL), b"\xac\x02")
  assert_true(decode_varint_u64(b"\xac\x02") == U64Ok(300UL, 2))
}

///|
test "zigzag golden vectors" {
  assert_eq(encode_zigzag_i64(0L), 0UL)
  assert_eq(encode_zigzag_i64(-1L), 1UL)
  assert_eq(encode_zigzag_i64(1L), 2UL)
  assert_eq(encode_zigzag_i64(-2L), 3UL)
  assert_eq(decode_zigzag_i64(3UL), -2L)
}

///|
test "key encode parse" {
  let raw = make_key(15, LengthDelimited)
  assert_eq(raw, 122UL)
  assert_eq(encode_key(15, LengthDelimited), b"z")
  assert_true(parse_key(raw) == KeyOk(15, LengthDelimited))
}

///|
test "fixed little endian" {
  assert_eq(encode_fixed32(0x12345678U), b"\x78\x56\x34\x12")
  assert_true(decode_fixed32(b"\x78\x56\x34\x12") == U32Ok(0x12345678U, 4))
  assert_eq(
    encode_fixed64(0x0102030405060708UL),
    b"\x08\x07\x06\x05\x04\x03\x02\x01",
  )
}

///|
test "length delimited and string" {
  assert_eq(encode_string("abc"), b"\x03abc")
  assert_true(decode_string_lossy(b"\x03abc") == StringOk("abc", 4))
}

///|
test "field encoding matches protobuf bytes" {
  let user = concat_bytes([
    encode_uint64_field(1, 150UL),
    encode_string_field(2, "Alice"),
    encode_bool_field(3, true),
  ])
  assert_eq(user, b"\x08\x96\x01\x12\x05Alice\x18\x01")
}

///|
test "proto lexer" {
  let toks = lex_proto("syntax = \"proto3\"; message User { uint32 id = 1; }")
  assert_true(toks[0] == Ident("syntax"))
  assert_true(toks[2] == StrLit("proto3"))
  assert_true(toks[4] == Ident("message"))
}

///|
test "parse simple proto" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|message User {
    #|  uint32 id = 1;
    #|  string name = 2;
    #|  repeated string tags = 3;
    #|}
  match parse_proto(src) {
    ProtoOk(file) => {
      assert_eq(file.syntax, "proto3")
      assert_eq(file.package_name, "demo")
      assert_eq(file.messages.length(), 1)
      assert_eq(file.messages[0].name, "User")
      assert_eq(file.messages[0].fields.length(), 3)
      assert_true(file.messages[0].fields[2].label == Repeated)
      assert_eq(file.enums.length(), 0)
    }
    ProtoErr(_) => fail("expected parser to accept simple proto")
  }
}

///|
test "schema driven message encode golden bytes" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "name",
        typ: StringType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "active",
        typ: BoolType,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "tags",
        typ: StringType,
        number: 4,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "score",
        typ: SInt64Type,
        number: 5,
        label: Singular,
      },
      FieldDescriptor::{
        name: "blob",
        typ: BytesType,
        number: 6,
        label: Singular,
      },
    ],
  }
  let msg = message_value([
    message_field("id", UInt64Value(150UL)),
    message_field("name", StringValue("Alice")),
    message_field("active", BoolValue(true)),
    repeated_message_field("tags", [StringValue("admin"), StringValue("tester")]),
    message_field("score", Int64Value(-2L)),
    message_field("blob", BytesValue(b"\xff\x00")),
  ])
  match encode_message(desc, msg) {
    EncodeMessageOk(bytes) =>
      assert_eq(
        bytes, b"\x08\x96\x01\x12\x05Alice\x18\x01\x22\x05admin\x22\x06tester\x28\x03\x32\x02\xff\x00",
      )
    EncodeMessageErr(_) => fail("dynamic encode failed")
  }
}

///|
test "schema driven message decode roundtrip" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "name",
        typ: StringType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "active",
        typ: BoolType,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "tags",
        typ: StringType,
        number: 4,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "score",
        typ: SInt64Type,
        number: 5,
        label: Singular,
      },
      FieldDescriptor::{
        name: "blob",
        typ: BytesType,
        number: 6,
        label: Singular,
      },
    ],
  }
  let msg = message_value([
    message_field("id", UInt64Value(150UL)),
    message_field("name", StringValue("Alice")),
    message_field("active", BoolValue(true)),
    repeated_message_field("tags", [StringValue("admin"), StringValue("tester")]),
    message_field("score", Int64Value(-2L)),
    message_field("blob", BytesValue(b"\xff\x00")),
  ])
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("dynamic encode failed")
    EncodeMessageOk(bytes) =>
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("dynamic decode failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
  }
}

///|
test "message decode skips unknown fields" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "name",
        typ: StringType,
        number: 2,
        label: Singular,
      },
    ],
  }
  let bytes = concat_bytes([
    encode_uint64_field(99, 1234UL),
    encode_string_field(2, "Bob"),
    encode_uint64_field(1, 7UL),
  ])
  match decode_message(desc, bytes) {
    DecodeMessageErr(_) => fail("decode with unknown field failed")
    DecodeMessageOk(decoded, next) => {
      assert_eq(next, bytes.length())
      assert_true(
        decoded ==
        message_value([
          message_field("name", StringValue("Bob")),
          message_field("id", UInt64Value(7UL)),
        ]),
      )
    }
  }
}

///|
test "message encode rejects bad dynamic values" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
    ],
  }
  match
    encode_message(
      desc,
      message_value([message_field("id", StringValue("wrong"))]),
    ) {
    EncodeMessageOk(_) => fail("bad value should be rejected")
    EncodeMessageErr(Unsupported(_)) => ()
    EncodeMessageErr(_) => fail("unexpected error")
  }
}

///|
test "codegen emits moonbit struct and descriptor" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|message User {
    #|  uint64 id = 1;
    #|  string name = 2;
    #|  repeated string tags = 3;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("parser failed before codegen")
    ProtoOk(file) => {
      let generated = generate_moonbit_source(file)
      let expected =
        #|pub(all) struct User {
        #|  id : UInt64
        #|  name : String
        #|  tags : Array[String]
        #|} derive(Debug, Eq)
        #|
        #|pub fn descriptor_User() -> MessageDescriptor {
        #|  MessageDescriptor::{
        #|    name : "User",
        #|    fields : [
        #|      FieldDescriptor::{ name : "id", typ : UInt64Type, number : 1, label : Singular },
        #|      FieldDescriptor::{ name : "name", typ : StringType, number : 2, label : Singular },
        #|      FieldDescriptor::{ name : "tags", typ : StringType, number : 3, label : Repeated },
        #|    ],
        #|  }
        #|}
      assert_eq(generated, expected)
    }
  }
}

///|
test "parse enum and codegen enum descriptor" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|enum Color {
    #|  COLOR_UNSPECIFIED = 0;
    #|  RED = 1;
    #|  BLUE = 2;
    #|}
    #|message Paint {
    #|  Color color = 1;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("enum parser failed")
    ProtoOk(file) => {
      assert_eq(file.enums.length(), 1)
      assert_eq(file.enums[0].name, "Color")
      assert_eq(file.enums[0].values.length(), 3)
      assert_eq(file.enums[0].values[2].name, "BLUE")
      assert_true(file.messages[0].fields[0].typ == EnumType("Color"))
      let generated = generate_moonbit_source(file)
      let expected =
        #|pub(all) enum Color {
        #|  COLOR_UNSPECIFIED
        #|  RED
        #|  BLUE
        #|} derive(Debug, Eq)
        #|
        #|pub fn descriptor_Color() -> EnumDescriptor {
        #|  EnumDescriptor::{
        #|    name : "Color",
        #|    values : [
        #|      EnumValueDescriptor::{ name : "COLOR_UNSPECIFIED", number : 0 },
        #|      EnumValueDescriptor::{ name : "RED", number : 1 },
        #|      EnumValueDescriptor::{ name : "BLUE", number : 2 },
        #|    ],
        #|  }
        #|}
        #|
        #|pub(all) struct Paint {
        #|  color : Color
        #|} derive(Debug, Eq)
        #|
        #|pub fn descriptor_Paint() -> MessageDescriptor {
        #|  MessageDescriptor::{
        #|    name : "Paint",
        #|    fields : [
        #|      FieldDescriptor::{ name : "color", typ : EnumType("Color"), number : 1, label : Singular },
        #|    ],
        #|  }
        #|}
      assert_eq(generated, expected)
    }
  }
}

///|
test "enum fields encode as protobuf varints" {
  let desc = MessageDescriptor::{
    name: "Paint",
    fields: [
      FieldDescriptor::{
        name: "color",
        typ: EnumType("Color"),
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "history",
        typ: EnumType("Color"),
        number: 2,
        label: Repeated,
      },
    ],
  }
  let msg = message_value([
    message_field("color", Int64Value(2L)),
    repeated_message_field("history", [Int64Value(1L), Int64Value(2L)]),
  ])
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("enum encode failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, b"\x08\x02\x12\x02\x01\x02")
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("enum decode failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
    }
  }
  match message_to_json(desc, msg) {
    JsonErr(_) => fail("enum json failed")
    JsonOk(json) => assert_eq(json, "{\"color\":2,\"history\":[1,2]}")
  }
  match json_to_message(desc, "{\"history\":[1,2],\"color\":2}") {
    JsonDecodeErr(_) => fail("enum json parse failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
}

///|
test "proto3 repeated numeric fields use packed encoding" {
  let desc = MessageDescriptor::{
    name: "Metrics",
    fields: [
      FieldDescriptor::{
        name: "samples",
        typ: UInt64Type,
        number: 7,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "deltas",
        typ: SInt64Type,
        number: 8,
        label: Repeated,
      },
    ],
  }
  let msg = message_value([
    repeated_message_field("samples", [UInt64Value(1UL), UInt64Value(150UL)]),
    repeated_message_field("deltas", [Int64Value(-1L), Int64Value(2L)]),
  ])
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("packed encode failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, b"\x3a\x03\x01\x96\x01\x42\x02\x01\x04")
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("packed decode failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
    }
  }
}

///|
test "packed decoder also accepts unpacked repeated numeric fields" {
  let desc = MessageDescriptor::{
    name: "Metrics",
    fields: [
      FieldDescriptor::{
        name: "samples",
        typ: UInt64Type,
        number: 7,
        label: Repeated,
      },
    ],
  }
  let unpacked = concat_bytes([
    encode_uint64_field(7, 1UL),
    encode_uint64_field(7, 150UL),
  ])
  match decode_message(desc, unpacked) {
    DecodeMessageErr(_) => fail("unpacked repeated numeric decode failed")
    DecodeMessageOk(decoded, next) => {
      assert_eq(next, unpacked.length())
      assert_true(
        decoded ==
        message_value([
          repeated_message_field("samples", [
            UInt64Value(1UL),
            UInt64Value(150UL),
          ]),
        ]),
      )
    }
  }
}

///|
test "json string escaping and base64" {
  assert_eq(json_escape_string("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"")
  assert_eq(base64_encode(b""), "")
  assert_eq(base64_encode(b"\xff\x00"), "/wA=")
  assert_eq(base64_encode(b"abc"), "YWJj")
  assert_true(base64_decode("/wA=") == BytesOk(b"\xff\x00", 4))
  assert_true(base64_decode("YWJj") == BytesOk(b"abc", 4))
}

///|
test "message to protobuf style json" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "name",
        typ: StringType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "active",
        typ: BoolType,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "tags",
        typ: StringType,
        number: 4,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "score",
        typ: SInt64Type,
        number: 5,
        label: Singular,
      },
      FieldDescriptor::{
        name: "blob",
        typ: BytesType,
        number: 6,
        label: Singular,
      },
    ],
  }
  let msg = message_value([
    message_field("blob", BytesValue(b"\xff\x00")),
    repeated_message_field("tags", [StringValue("admin"), StringValue("tester")]),
    message_field("active", BoolValue(true)),
    message_field("name", StringValue("Alice \"A\"")),
    message_field("score", Int64Value(-2L)),
    message_field("id", UInt64Value(150UL)),
  ])
  match message_to_json(desc, msg) {
    JsonErr(_) => fail("JSON mapping failed")
    JsonOk(json) =>
      assert_eq(
        json, "{\"id\":\"150\",\"name\":\"Alice \\\"A\\\"\",\"active\":true,\"tags\":[\"admin\",\"tester\"],\"score\":\"-2\",\"blob\":\"/wA=\"}",
      )
  }
}

///|
test "message to json rejects unknown or mismatched fields" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
    ],
  }
  match
    message_to_json(
      desc,
      message_value([message_field("oops", UInt64Value(1UL))]),
    ) {
    JsonOk(_) => fail("unknown field should be rejected")
    JsonErr(Unsupported(_)) => ()
    JsonErr(_) => fail("unexpected json error")
  }
  match
    message_to_json(
      desc,
      message_value([message_field("id", StringValue("wrong"))]),
    ) {
    JsonOk(_) => fail("bad field value should be rejected")
    JsonErr(Unsupported(_)) => ()
    JsonErr(_) => fail("unexpected json error")
  }
}

///|
test "protobuf style json parser roundtrip" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "name",
        typ: StringType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "active",
        typ: BoolType,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "tags",
        typ: StringType,
        number: 4,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "score",
        typ: SInt64Type,
        number: 5,
        label: Singular,
      },
      FieldDescriptor::{
        name: "blob",
        typ: BytesType,
        number: 6,
        label: Singular,
      },
    ],
  }
  let json = "{\"blob\":\"/wA=\",\"tags\":[\"admin\",\"tester\"],\"active\":true,\"name\":\"Alice \\\"A\\\"\",\"score\":\"-2\",\"id\":\"150\"}"
  match json_to_message(desc, json) {
    JsonDecodeErr(_) => fail("JSON parser failed")
    JsonDecodeOk(msg) => {
      let expected = message_value([
        message_field("id", UInt64Value(150UL)),
        message_field("name", StringValue("Alice \"A\"")),
        message_field("active", BoolValue(true)),
        repeated_message_field("tags", [
          StringValue("admin"),
          StringValue("tester"),
        ]),
        message_field("score", Int64Value(-2L)),
        message_field("blob", BytesValue(b"\xff\x00")),
      ])
      assert_true(msg == expected)
      match message_to_json(desc, msg) {
        JsonErr(_) => fail("JSON writer failed after parse")
        JsonOk(canonical) =>
          assert_eq(
            canonical, "{\"id\":\"150\",\"name\":\"Alice \\\"A\\\"\",\"active\":true,\"tags\":[\"admin\",\"tester\"],\"score\":\"-2\",\"blob\":\"/wA=\"}",
          )
      }
    }
  }
}

///|
test "json parser rejects duplicate and invalid values" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "active",
        typ: BoolType,
        number: 2,
        label: Singular,
      },
    ],
  }
  match json_to_message(desc, "{\"id\":\"1\",\"id\":\"2\"}") {
    JsonDecodeOk(_) => fail("duplicate JSON field should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected duplicate-field error")
  }
  match json_to_message(desc, "{\"active\":\"true\"}") {
    JsonDecodeOk(_) => fail("quoted bool should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected bool error")
  }
}

///|
test "official python protobuf oracle full user bytes and json" {
  let desc = MessageDescriptor::{
    name: "User",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "name",
        typ: StringType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "active",
        typ: BoolType,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "tags",
        typ: StringType,
        number: 4,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "score",
        typ: SInt64Type,
        number: 5,
        label: Singular,
      },
      FieldDescriptor::{
        name: "blob",
        typ: BytesType,
        number: 6,
        label: Singular,
      },
      FieldDescriptor::{
        name: "samples",
        typ: UInt64Type,
        number: 7,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "deltas",
        typ: SInt64Type,
        number: 8,
        label: Repeated,
      },
    ],
  }
  let msg = message_value([
    message_field("id", UInt64Value(150UL)),
    message_field("name", StringValue("Alice \"A\"")),
    message_field("active", BoolValue(true)),
    repeated_message_field("tags", [StringValue("admin"), StringValue("tester")]),
    message_field("score", Int64Value(-2L)),
    message_field("blob", BytesValue(b"\xff\x00")),
    repeated_message_field("samples", [UInt64Value(1UL), UInt64Value(150UL)]),
    repeated_message_field("deltas", [Int64Value(-1L), Int64Value(2L)]),
  ])
  let python_oracle_bytes = b"\x08\x96\x01\x12\x09Alice \x22A\x22\x18\x01\x22\x05admin\x22\x06tester\x28\x03\x32\x02\xff\x00\x3a\x03\x01\x96\x01\x42\x02\x01\x04"
  let python_oracle_json = "{\"id\":\"150\",\"name\":\"Alice \\\"A\\\"\",\"active\":true,\"tags\":[\"admin\",\"tester\"],\"score\":\"-2\",\"blob\":\"/wA=\",\"samples\":[\"1\",\"150\"],\"deltas\":[\"-1\",\"2\"]}"
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("encoding python oracle user failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, python_oracle_bytes)
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("decoding python oracle user failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
    }
  }
  match message_to_json(desc, msg) {
    JsonErr(_) => fail("python oracle JSON render failed")
    JsonOk(json) => assert_eq(json, python_oracle_json)
  }
  match json_to_message(desc, python_oracle_json) {
    JsonDecodeErr(_) => fail("python oracle JSON parse failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
}

///|
test "schema validator accepts parsed supported proto" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|enum Color {
    #|  COLOR_UNSPECIFIED = 0;
    #|  RED = 1;
    #|}
    #|message Paint {
    #|  uint64 id = 1;
    #|  Color color = 2;
    #|  repeated string tags = 3;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("schema parse failed")
    ProtoOk(file) => {
      assert_true(schema_is_valid(file))
      assert_true(validate_proto_file(file) == SchemaValid)
    }
  }
}

///|
test "schema validator reports duplicate and reserved fields" {
  let msg = MessageDescriptor::{
    name: "Bad",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "id",
        typ: StringType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "reserved",
        typ: BoolType,
        number: 19000,
        label: Singular,
      },
      FieldDescriptor::{
        name: "again",
        typ: BoolType,
        number: 1,
        label: Singular,
      },
    ],
  }
  match validate_message_descriptor(msg) {
    SchemaValid => fail("invalid message should fail validation")
    SchemaInvalid(issues) => {
      assert_eq(issues.length(), 3)
      assert_eq(issues[0].message, "duplicate field name")
      assert_eq(issues[1].message, "invalid protobuf field number")
      assert_eq(issues[2].message, "duplicate field number")
    }
  }
}

///|
test "schema validator reports enum and top level issues" {
  let file = ProtoFile::{
    syntax: "proto2",
    package_name: "demo",
    messages: [
      MessageDescriptor::{ name: "Thing", fields: [] },
      MessageDescriptor::{ name: "Thing", fields: [] },
    ],
    enums: [
      EnumDescriptor::{
        name: "Thing",
        values: [
          EnumValueDescriptor::{ name: "RED", number: 1 },
          EnumValueDescriptor::{ name: "RED", number: 1 },
        ],
      },
    ],
  }
  match validate_proto_file(file) {
    SchemaValid => fail("invalid proto file should fail validation")
    SchemaInvalid(issues) => {
      assert_eq(issues.length(), 6)
      assert_eq(issues[0].path, "syntax")
      assert_eq(issues[1].message, "duplicate top-level message name")
      assert_eq(issues[2].message, "proto3 enum first value must be zero")
      assert_eq(issues[3].message, "duplicate enum value name")
      assert_eq(issues[4].message, "duplicate enum value number")
      assert_eq(
        issues[5].message,
        "top-level enum name conflicts with message name",
      )
    }
  }
}

///|
test "nested message binary and json roundtrip" {
  let address_desc = MessageDescriptor::{
    name: "Address",
    fields: [
      FieldDescriptor::{
        name: "street",
        typ: StringType,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "zip",
        typ: UInt64Type,
        number: 2,
        label: Singular,
      },
    ],
  }
  let person_desc = MessageDescriptor::{
    name: "Person",
    fields: [
      FieldDescriptor::{
        name: "name",
        typ: StringType,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "address",
        typ: NamedType("Address"),
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "previous",
        typ: NamedType("Address"),
        number: 3,
        label: Repeated,
      },
    ],
  }
  let address = message_value([
    message_field("street", StringValue("Main")),
    message_field("zip", UInt64Value(94107UL)),
  ])
  let previous = message_value([
    message_field("street", StringValue("Old")),
    message_field("zip", UInt64Value(1UL)),
  ])
  let person = message_value([
    message_field("name", StringValue("Bob")),
    message_field("address", NestedMessageValue(address)),
    repeated_message_field("previous", [NestedMessageValue(previous)]),
  ])
  let address_bytes = concat_bytes([
    encode_string_field(1, "Main"),
    encode_uint64_field(2, 94107UL),
  ])
  let previous_bytes = concat_bytes([
    encode_string_field(1, "Old"),
    encode_uint64_field(2, 1UL),
  ])
  let expected = concat_bytes([
    encode_string_field(1, "Bob"),
    concat_bytes([
      encode_key(2, LengthDelimited),
      encode_length_delimited(address_bytes),
    ]),
    concat_bytes([
      encode_key(3, LengthDelimited),
      encode_length_delimited(previous_bytes),
    ]),
  ])
  let descriptors = [address_desc]
  match encode_message_with_descriptors(person_desc, descriptors, person) {
    EncodeMessageErr(_) => fail("nested message encode failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, expected)
      match decode_message_with_descriptors(person_desc, descriptors, bytes) {
        DecodeMessageErr(_) => fail("nested message decode failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == person)
        }
      }
    }
  }
  let expected_json = "{\"name\":\"Bob\",\"address\":{\"street\":\"Main\",\"zip\":\"94107\"},\"previous\":[{\"street\":\"Old\",\"zip\":\"1\"}]}"
  match message_to_json_with_descriptors(person_desc, descriptors, person) {
    JsonErr(_) => fail("nested message json encode failed")
    JsonOk(json) => assert_eq(json, expected_json)
  }
  match
    json_to_message_with_descriptors(person_desc, descriptors, expected_json) {
    JsonDecodeErr(_) => fail("nested message json decode failed")
    JsonDecodeOk(decoded) => assert_true(decoded == person)
  }
}
