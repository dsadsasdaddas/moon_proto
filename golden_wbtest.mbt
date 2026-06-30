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
test "proto lexer supports single quotes and escaped strings" {
  let toks = lex_proto("'proto3' \"a\\\";b\" 'c\\t'")
  assert_true(toks[0] == StrLit("proto3"))
  assert_true(toks[1] == StrLit("a\";b"))
  assert_true(toks[2] == StrLit("c\t"))
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
test "parser tolerates protobuf edition declarations" {
  let src =
    #|edition = "2023";
    #|package demo.edition;
    #|message EditionEvent {
    #|  string name = 1;
    #|  repeated string tags = 2;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("edition schema should parse")
    ProtoOk(file) => {
      assert_eq(file.syntax, "proto3")
      assert_eq(file.package_name, "demo.edition")
      assert_eq(file.messages.length(), 1)
      assert_eq(file.messages[0].name, "EditionEvent")
      assert_eq(file.messages[0].fields.length(), 2)
      assert_true(file.messages[0].fields[1].label == Repeated)
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("pub(all) struct EditionEvent"))
      assert_true(generated.contains("tags : Array[String]"))
    }
  }
}

///|
test "parser tolerates imports options reserved and field options" {
  let src =
    #|syntax = "proto3";
    #|package demo.v1;
    #|import "google/protobuf/timestamp.proto";
    #|import public "shared.proto";
    #|option java_package = "demo";
    #|enum Status {
    #|  option allow_alias = true;
    #|  reserved 9 to 12;
    #|  STATUS_UNSPECIFIED = 0 [(deprecated) = true];
    #|  STATUS_OK = 1;
    #|}
    #|message Event {
    #|  option deprecated = false;
    #|  reserved 4, 6 to 9;
    #|  reserved "old_name";
    #|  uint64 id = 1 [json_name = "eventId"];
    #|  .demo.v1.External ref = 2;
    #|  map<string, .demo.v1.External> refs = 3;
    #|}
  match parse_proto(src) {
    ProtoOk(file) => {
      assert_eq(file.package_name, "demo.v1")
      assert_eq(file.enums.length(), 1)
      assert_eq(file.enums[0].values.length(), 2)
      assert_true(file.enums[0].allow_alias)
      assert_eq(file.enum_reservations.length(), 1)
      assert_eq(file.enum_reservations[0].owner, "Status")
      assert_eq(file.enum_reservations[0].numbers.length(), 1)
      assert_eq(file.enum_reservations[0].numbers[0].start, 9)
      assert_eq(file.enum_reservations[0].numbers[0].end, 12)
      assert_eq(file.messages.length(), 1)
      assert_eq(file.message_reservations.length(), 1)
      assert_eq(file.message_reservations[0].owner, "Event")
      assert_eq(file.message_reservations[0].numbers.length(), 2)
      assert_eq(file.message_reservations[0].names[0], "old_name")
      let fields = file.messages[0].fields
      assert_eq(fields.length(), 3)
      assert_true(fields[0].typ == UInt64Type)
      assert_true(fields[1].typ == NamedType(".demo.v1.External"))
      assert_true(
        fields[2].typ ==
        MapType(StringType, NamedType(".demo.v1.External")),
      )
    }
    ProtoErr(_) => fail("expected parser to accept decorated proto schema")
  }
}

///|
test "parser tolerates single quoted and escaped option strings" {
  let src =
    #|syntax = 'proto3';
    #|package demo.literals;
    #|option (demo.file) = { note: "quoted \" value; still option" };
    #|message StringLiteralCarrier {
    #|  option (demo.message) = { note: 'single quoted ; still option' };
    #|  reserved 'old_name', "legacy_name";
    #|  string text = 1 [json_name = "text_value", (demo.field) = { note: "field \" option" }];
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("string literal schema should parse")
    ProtoOk(file) => {
      assert_eq(file.syntax, "proto3")
      assert_eq(file.package_name, "demo.literals")
      assert_eq(file.messages.length(), 1)
      assert_eq(file.messages[0].name, "StringLiteralCarrier")
      assert_eq(file.messages[0].fields.length(), 1)
      assert_true(file.messages[0].fields[0].typ == StringType)
      assert_eq(file.message_reservations.length(), 1)
      assert_eq(file.message_reservations[0].names.length(), 2)
      assert_eq(file.message_reservations[0].names[0], "old_name")
      assert_eq(file.message_reservations[0].names[1], "legacy_name")
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("pub(all) struct StringLiteralCarrier"))
      assert_true(generated.contains("text : String"))
    }
  }
}

///|
test "parser tolerates negative enum values and empty statements" {
  let src =
    #|syntax = "proto3";
    #|package demo.enums;
    #|;
    #|enum SignedStatus {
    #|  ;
    #|  reserved -10 to -2;
    #|  STATUS_UNSPECIFIED = 0;
    #|  STATUS_NEGATIVE = -1 [(deprecated) = true];
    #|  STATUS_POSITIVE = 1;
    #|}
    #|message Carrier {
    #|  SignedStatus status = 1;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("negative enum schema should parse")
    ProtoOk(file) => {
      assert_eq(file.enums.length(), 1)
      assert_eq(file.enums[0].name, "SignedStatus")
      assert_eq(file.enums[0].values.length(), 3)
      assert_eq(file.enums[0].values[1].name, "STATUS_NEGATIVE")
      assert_eq(file.enums[0].values[1].number, -1)
      assert_eq(file.enum_reservations.length(), 1)
      assert_eq(file.enum_reservations[0].numbers[0].start, -10)
      assert_eq(file.enum_reservations[0].numbers[0].end, -2)
      assert_eq(file.messages.length(), 1)
      assert_true(file.messages[0].fields[0].typ == EnumType("SignedStatus"))
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("STATUS_NEGATIVE"))
      assert_true(generated.contains("number : -1"))
    }
  }
}

///|
test "parser lifts nested message and enum descriptors" {
  let src =
    #|syntax = "proto3";
    #|package demo.nested;
    #|message Envelope {
    #|  enum Kind {
    #|    KIND_UNSPECIFIED = 0;
    #|    KIND_CREATED = 1;
    #|  }
    #|  message Payload {
    #|    string body = 1;
    #|    bytes raw = 2;
    #|  }
    #|  Kind kind = 1;
    #|  Payload payload = 2;
    #|  repeated Payload history = 3;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("nested type schema should parse")
    ProtoOk(file) => {
      assert_eq(file.package_name, "demo.nested")
      assert_eq(file.enums.length(), 1)
      assert_eq(file.enums[0].name, "Kind")
      assert_eq(file.enums[0].values.length(), 2)
      assert_eq(file.messages.length(), 2)
      assert_eq(file.messages[0].name, "Payload")
      assert_eq(file.messages[1].name, "Envelope")
      assert_eq(file.messages[0].fields.length(), 2)
      assert_eq(file.messages[1].fields.length(), 3)
      assert_true(file.messages[1].fields[0].typ == EnumType("Kind"))
      assert_true(file.messages[1].fields[1].typ == NamedType("Payload"))
      assert_true(file.messages[1].fields[2].typ == NamedType("Payload"))
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("pub(all) enum Kind"))
      assert_true(generated.contains("pub(all) struct Payload"))
      assert_true(generated.contains("pub(all) struct Envelope"))
      assert_true(generated.contains("history : Array[Payload]"))
    }
  }
}

///|
test "parser resolves qualified nested type references" {
  let src =
    #|syntax = "proto3";
    #|package demo.nested;
    #|message Envelope {
    #|  enum Kind {
    #|    KIND_UNSPECIFIED = 0;
    #|    KIND_CREATED = 1;
    #|  }
    #|  message Payload {
    #|    string body = 1;
    #|  }
    #|}
    #|message Audit {
    #|  Envelope.Payload payload = 1;
    #|  .demo.nested.Envelope.Kind kind = 2;
    #|  repeated Envelope.Payload history = 3;
    #|  map<string, Envelope.Payload> by_id = 4;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("qualified nested schema should parse")
    ProtoOk(file) => {
      assert_eq(file.messages.length(), 3)
      assert_eq(file.messages[0].name, "Payload")
      assert_eq(file.messages[2].name, "Audit")
      let fields = file.messages[2].fields
      assert_true(fields[0].typ == NamedType("Payload"))
      assert_true(fields[1].typ == EnumType("Kind"))
      assert_true(fields[2].typ == NamedType("Payload"))
      assert_true(fields[3].typ == MapType(StringType, NamedType("Payload")))
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("payload : Payload"))
      assert_true(generated.contains("kind : Kind"))
      assert_true(generated.contains("history : Array[Payload]"))
      assert_true(generated.contains("MapType(StringType, NamedType(\"Payload\"))"))
    }
  }
}

///|
test "parser tolerates service rpc blocks and block comments" {
  let src =
    #|syntax = "proto3";
    #|package demo.rpc;
    #|/* block comment before messages */
    #|message Request {
    #|  uint64 id = 1;
    #|}
    #|message Reply {
    #|  bool ok = 1;
    #|}
    #|service DemoService {
    #|  option deprecated = false;
    #|  rpc Publish (Request) returns (Reply);
    #|  rpc Stream (Request) returns (stream Reply) {
    #|    option (google.api.http) = {
    #|      post: "/v1/demo:stream"
    #|      body: "*"
    #|    };
    #|  }
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("service/rpc schema should parse")
    ProtoOk(file) => {
      assert_eq(file.package_name, "demo.rpc")
      assert_eq(file.messages.length(), 2)
      assert_eq(file.messages[0].name, "Request")
      assert_eq(file.messages[1].name, "Reply")
      assert_eq(file.enums.length(), 0)
      assert_true(schema_is_valid(file))
    }
  }
}

///|
test "schema validator rejects parsed reserved reuse" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|enum BadStatus {
    #|  reserved 2;
    #|  reserved "BAD_NAME";
    #|  STATUS_UNSPECIFIED = 0;
    #|  BAD_NAME = 1;
    #|  ALSO_BAD = 2;
    #|}
    #|message Bad {
    #|  reserved 1, 5 to 6;
    #|  reserved "old_name";
    #|  uint64 id = 1;
    #|  string old_name = 2;
    #|  bool another = 5;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("reserved reuse schema should parse")
    ProtoOk(file) =>
      match validate_proto_file(file) {
        SchemaValid => fail("reserved reuse should fail validation")
        SchemaInvalid(issues) => {
          let mut saw_field_number = false
          let mut saw_field_name = false
          let mut saw_enum_number = false
          let mut saw_enum_name = false
          for issue in issues {
            if issue.message == "field uses reserved number" {
              saw_field_number = true
            }
            if issue.message == "field uses reserved name" {
              saw_field_name = true
            }
            if issue.message == "enum value uses reserved number" {
              saw_enum_number = true
            }
            if issue.message == "enum value uses reserved name" {
              saw_enum_name = true
            }
          }
          assert_true(saw_field_number)
          assert_true(saw_field_name)
          assert_true(saw_enum_number)
          assert_true(saw_enum_name)
        }
      }
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
test "32-bit numeric bounds are enforced" {
  let desc = MessageDescriptor::{
    name: "Nums",
    fields: [
      FieldDescriptor::{
        name: "u",
        typ: UInt32Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "i",
        typ: Int32Type,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "s",
        typ: SInt32Type,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "f",
        typ: Fixed32Type,
        number: 4,
        label: Singular,
      },
      FieldDescriptor::{
        name: "sf",
        typ: SFixed32Type,
        number: 5,
        label: Singular,
      },
    ],
  }
  let valid = message_value([
    message_field("u", UInt64Value(0xffffffffUL)),
    message_field("i", Int64Value(2147483647L)),
    message_field("s", Int64Value(-2147483647L - 1L)),
    message_field("f", UInt64Value(0xffffffffUL)),
    message_field("sf", Int64Value(-1L)),
  ])
  match encode_message(desc, valid) {
    EncodeMessageErr(_) => fail("valid 32-bit boundary values should encode")
    EncodeMessageOk(_) => ()
  }
  match
    encode_message(
      desc,
      message_value([message_field("u", UInt64Value(0x100000000UL))]),
    ) {
    EncodeMessageOk(_) => fail("uint32 overflow should be rejected")
    EncodeMessageErr(Unsupported(_)) => ()
    EncodeMessageErr(_) => fail("unexpected uint32 overflow error")
  }
  match
    encode_message(
      desc,
      message_value([message_field("i", Int64Value(2147483648L))]),
    ) {
    EncodeMessageOk(_) => fail("int32 overflow should be rejected")
    EncodeMessageErr(Unsupported(_)) => ()
    EncodeMessageErr(_) => fail("unexpected int32 overflow error")
  }
  match
    encode_message(
      desc,
      message_value([message_field("s", Int64Value(-2147483647L - 2L))]),
    ) {
    EncodeMessageOk(_) => fail("sint32 underflow should be rejected")
    EncodeMessageErr(Unsupported(_)) => ()
    EncodeMessageErr(_) => fail("unexpected sint32 underflow error")
  }
  match json_to_message(desc, "{\"u\":4294967296}") {
    JsonDecodeOk(_) => fail("uint32 JSON overflow should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected uint32 JSON overflow error")
  }
  match json_to_message(desc, "{\"i\":2147483648}") {
    JsonDecodeOk(_) => fail("int32 JSON overflow should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected int32 JSON overflow error")
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
        #|
        #|pub fn message_descriptors() -> Array[MessageDescriptor] {
        #|  [
        #|    descriptor_User(),
        #|  ]
        #|}
        #|
        #|pub fn enum_descriptors() -> Array[EnumDescriptor] {
        #|  [
        #|  ]
        #|}
        #|
        #|pub fn encode_User(value : MessageValue) -> EncodeMessageResult {
        #|  encode_message_with_descriptors(descriptor_User(), message_descriptors(), value)
        #|}
        #|
        #|pub fn decode_User(input : Bytes) -> DecodeMessageResult {
        #|  decode_message_with_descriptors(descriptor_User(), message_descriptors(), input)
        #|}
        #|
        #|pub fn to_json_User(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_with_schema(descriptor_User(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn to_json_lower_camel_User(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_lower_camel_with_schema(descriptor_User(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn from_json_User(input : String) -> JsonDecodeResult {
        #|  json_to_message_with_schema(descriptor_User(), message_descriptors(), enum_descriptors(), input)
        #|}
      assert_eq(generated, expected)
    }
  }
}

///|
test "parser tolerates top-level extend custom option blocks" {
  let src =
    #|syntax = "proto3";
    #|package demo.options;
    #|import "google/protobuf/descriptor.proto";
    #|extend google.protobuf.MessageOptions {
    #|  string message_note = 50001;
    #|  bool audited = 50002 [default = true];
    #|}
    #|extend .google.protobuf.FieldOptions {
    #|  string field_note = 50003;
    #|}
    #|message Annotated {
    #|  option (message_note) = "hello";
    #|  string name = 1 [(field_note) = "display"];
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("extend custom option schema should parse")
    ProtoOk(file) => {
      assert_eq(file.package_name, "demo.options")
      assert_eq(file.messages.length(), 1)
      assert_eq(file.messages[0].name, "Annotated")
      assert_eq(file.messages[0].fields.length(), 1)
      assert_true(file.messages[0].fields[0].typ == StringType)
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("pub(all) struct Annotated"))
      assert_true(generated.contains("name : String"))
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
        #|    allow_alias : false,
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
        #|
        #|pub fn message_descriptors() -> Array[MessageDescriptor] {
        #|  [
        #|    descriptor_Paint(),
        #|  ]
        #|}
        #|
        #|pub fn enum_descriptors() -> Array[EnumDescriptor] {
        #|  [
        #|    descriptor_Color(),
        #|  ]
        #|}
        #|
        #|pub fn encode_Paint(value : MessageValue) -> EncodeMessageResult {
        #|  encode_message_with_descriptors(descriptor_Paint(), message_descriptors(), value)
        #|}
        #|
        #|pub fn decode_Paint(input : Bytes) -> DecodeMessageResult {
        #|  decode_message_with_descriptors(descriptor_Paint(), message_descriptors(), input)
        #|}
        #|
        #|pub fn to_json_Paint(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_with_schema(descriptor_Paint(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn to_json_lower_camel_Paint(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_lower_camel_with_schema(descriptor_Paint(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn from_json_Paint(input : String) -> JsonDecodeResult {
        #|  json_to_message_with_schema(descriptor_Paint(), message_descriptors(), enum_descriptors(), input)
        #|}
      assert_eq(generated, expected)
    }
  }
}

///|
test "enum fields encode as protobuf varints" {
  let enum_desc = EnumDescriptor::{
    name: "Color",
    values: [
      EnumValueDescriptor::{ name: "COLOR_UNSPECIFIED", number: 0 },
      EnumValueDescriptor::{ name: "RED", number: 1 },
      EnumValueDescriptor::{ name: "BLUE", number: 2 },
    ],
    allow_alias: false,
  }
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
  match message_to_json_with_schema(desc, [], [enum_desc], msg) {
    JsonErr(_) => fail("enum-name json failed")
    JsonOk(json) =>
      assert_eq(json, "{\"color\":\"BLUE\",\"history\":[\"RED\",\"BLUE\"]}")
  }
  match
    message_to_json_with_schema(
      desc,
      [],
      [enum_desc],
      message_value([message_field("color", Int64Value(99L))]),
    ) {
    JsonErr(_) => fail("unknown enum number should remain JSON number")
    JsonOk(json) => assert_eq(json, "{\"color\":99}")
  }
  match json_to_message(desc, "{\"history\":[1,2],\"color\":2}") {
    JsonDecodeErr(_) => fail("enum json parse failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
  match
    json_to_message_with_schema(
      desc, [], [enum_desc], "{\"history\":[\"RED\",2],\"color\":\"BLUE\"}",
    ) {
    JsonDecodeErr(_) => fail("enum-name json parse failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
  match json_to_message_with_schema(desc, [], [enum_desc], "{\"color\":\"GREEN\"}") {
    JsonDecodeOk(_) => fail("unknown enum JSON name should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected enum-name JSON error")
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
  assert_true(base64_decode("/wA") == BytesOk(b"\xff\x00", 3))
  assert_true(base64_decode("_wA") == BytesOk(b"\xff\x00", 3))
  assert_true(base64_decode("-_8") == BytesOk(b"\xfb\xff", 3))
  assert_true(base64_decode("YQ") == BytesOk(b"a", 2))
  assert_true(base64_decode("YWJj") == BytesOk(b"abc", 4))
  match base64_decode("A") {
    BytesOk(_, _) => fail("invalid base64 length should be rejected")
    BytesErr(Unsupported(_)) => ()
    BytesErr(_) => fail("unexpected base64 length error")
  }
  let desc = MessageDescriptor::{
    name: "Blob",
    fields: [
      FieldDescriptor::{
        name: "payload",
        typ: BytesType,
        number: 1,
        label: Singular,
      },
    ],
  }
  match json_to_message(desc, "{\"payload\":\"_wA\"}") {
    JsonDecodeErr(_) => fail("URL-safe unpadded base64 JSON should parse")
    JsonDecodeOk(msg) =>
      assert_true(
        msg == message_value([message_field("payload", BytesValue(b"\xff\x00"))]),
      )
  }
  let text_desc = MessageDescriptor::{
    name: "Text",
    fields: [
      FieldDescriptor::{
        name: "text",
        typ: StringType,
        number: 1,
        label: Singular,
      },
    ],
  }
  let escaped_json = "{\"text\":\"A\\u002fB\\u0041\\b\\f\\u4e2d\\ud83d\\ude00\"}"
  match json_to_message(text_desc, escaped_json) {
    JsonDecodeErr(_) => fail("standard JSON string escapes should parse")
    JsonDecodeOk(msg) => {
      assert_true(
        msg == message_value([message_field("text", StringValue("A/BA\b\f中😀"))]),
      )
      match message_to_json(text_desc, msg) {
        JsonErr(_) => fail("escaped string should render")
        JsonOk(json) => assert_eq(json, "{\"text\":\"A/BA\\u0008\\u000c中😀\"}")
      }
    }
  }
  match json_to_message(text_desc, "{\"text\":\"\\u12xz\"}") {
    JsonDecodeOk(_) => fail("bad JSON unicode hex should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected bad unicode escape error")
  }
  match json_to_message(text_desc, "{\"text\":\"\\ud800x\"}") {
    JsonDecodeOk(_) => fail("unpaired JSON surrogate should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected surrogate escape error")
  }
  match json_to_message(text_desc, "{\"text\":\"line\nbreak\"}") {
    JsonDecodeOk(_) => fail("unescaped JSON control characters should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected control-character JSON error")
  }
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
test "protobuf style json parser accepts integer exponent notation" {
  let desc = MessageDescriptor::{
    name: "NumericJson",
    fields: [
      FieldDescriptor::{
        name: "u",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "i",
        typ: Int64Type,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "i32",
        typ: Int32Type,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "u32",
        typ: UInt32Type,
        number: 4,
        label: Singular,
      },
    ],
  }
  let json = "{\"u\":\"1.8446744073709551615e19\",\"i\":\"-9.223372036854775808e18\",\"i32\":\"2.147483647e9\",\"u32\":4.294967295e9}"
  match json_to_message(desc, json) {
    JsonDecodeErr(_) => fail("integer exponent JSON should parse")
    JsonDecodeOk(msg) =>
      assert_true(
        msg ==
        message_value([
          message_field("u", UInt64Value(0xffffffffffffffffUL)),
          message_field("i", Int64Value(-9223372036854775807L - 1L)),
          message_field("i32", Int64Value(2147483647L)),
          message_field("u32", UInt64Value(0xffffffffUL)),
        ]),
      )
  }
  match json_to_message(desc, "{\"i\":\"1.5\"}") {
    JsonDecodeOk(_) => fail("fractional integer JSON should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected fractional integer JSON error")
  }
  match json_to_message(desc, "{\"i\":\"1e-1\"}") {
    JsonDecodeOk(_) => fail("negative exponent integer JSON should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected negative-exponent integer JSON error")
  }
  match json_to_message(desc, "{\"u\":\"18446744073709551616\"}") {
    JsonDecodeOk(_) => fail("uint64 overflow JSON should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected uint64 overflow JSON error")
  }
  match json_to_message(desc, "{\"i\":\"9.223372036854775808e18\"}") {
    JsonDecodeOk(_) => fail("int64 overflow exponent JSON should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected int64 overflow JSON error")
  }
}

///|
test "protobuf style json parser rejects invalid number grammar" {
  let desc = MessageDescriptor::{
    name: "NumberGrammar",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "score",
        typ: DoubleType,
        number: 2,
        label: Singular,
      },
    ],
  }
  match json_to_message(desc, "{\"id\":+1}") {
    JsonDecodeOk(_) => fail("leading plus JSON number should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected plus-number JSON error")
  }
  match json_to_message(desc, "{\"id\":01}") {
    JsonDecodeOk(_) => fail("leading zero JSON number should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected leading-zero JSON error")
  }
  match json_to_message(desc, "{\"id\":1.}") {
    JsonDecodeOk(_) => fail("missing fraction digit should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected fraction JSON error")
  }
  match json_to_message(desc, "{\"id\":1e}") {
    JsonDecodeOk(_) => fail("missing exponent digit should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected exponent JSON error")
  }
  match json_to_message(desc, "{\"score\":.5}") {
    JsonDecodeOk(_) => fail("missing integer part should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected missing-integer JSON error")
  }
  match json_to_message(desc, "{\"score\":-}") {
    JsonDecodeOk(_) => fail("bare minus JSON number should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected bare-minus JSON error")
  }
  match json_to_message(desc, "{\"id\":-0}") {
    JsonDecodeErr(_) => fail("negative zero JSON number should parse")
    JsonDecodeOk(msg) =>
      assert_true(msg == message_value([message_field("id", UInt64Value(0UL))]))
  }
}

///|
test "protobuf style json parser treats null as absent" {
  let desc = MessageDescriptor::{
    name: "Contact",
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
        label: Optional,
      },
      FieldDescriptor::{
        name: "tags",
        typ: StringType,
        number: 3,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "email",
        typ: StringType,
        number: 4,
        label: Oneof("reach"),
      },
      FieldDescriptor::{
        name: "phone",
        typ: StringType,
        number: 5,
        label: Oneof("reach"),
      },
    ],
  }
  let json = "{\"id\":null,\"name\":\"Alice\",\"tags\":null,\"email\":null,\"phone\":\"123\"}"
  match json_to_message(desc, json) {
    JsonDecodeErr(_) => fail("protobuf JSON null should parse as absent")
    JsonDecodeOk(msg) => {
      assert_true(
        msg ==
        message_value([
          message_field("name", StringValue("Alice")),
          message_field("phone", StringValue("123")),
        ]),
      )
      match message_to_json(desc, msg) {
        JsonErr(_) => fail("JSON writer failed after null parse")
        JsonOk(canonical) => assert_eq(canonical, "{\"name\":\"Alice\",\"phone\":\"123\"}")
      }
    }
  }
  match json_to_message(desc, "{\"id\":null,\"id\":\"1\"}") {
    JsonDecodeOk(_) => fail("duplicate JSON field with null should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected duplicate null-field error")
  }
  match json_to_message(desc, "{\"tags\":[null]}") {
    JsonDecodeOk(_) => fail("null inside repeated JSON array should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected repeated null error")
  }
}

///|
test "protobuf style json parser accepts lower camel field names" {
  let desc = MessageDescriptor::{
    name: "Profile",
    fields: [
      FieldDescriptor::{
        name: "user_id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "display_name",
        typ: StringType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "phone_number",
        typ: StringType,
        number: 3,
        label: Oneof("contact"),
      },
    ],
  }
  match
    json_to_message(
      desc,
      "{\"displayName\":\"Alice\",\"phoneNumber\":\"123\",\"userId\":\"150\"}",
    ) {
    JsonDecodeErr(_) => fail("lowerCamel JSON field names should parse")
    JsonDecodeOk(msg) => {
      assert_true(
        msg ==
        message_value([
          message_field("user_id", UInt64Value(150UL)),
          message_field("display_name", StringValue("Alice")),
          message_field("phone_number", StringValue("123")),
        ]),
      )
      match message_to_json(desc, msg) {
        JsonErr(_) => fail("JSON writer failed after lowerCamel parse")
        JsonOk(canonical) =>
          assert_eq(
            canonical,
            "{\"user_id\":\"150\",\"display_name\":\"Alice\",\"phone_number\":\"123\"}",
          )
      }
      match message_to_json_lower_camel(desc, msg) {
        JsonErr(_) => fail("lowerCamel JSON writer failed")
        JsonOk(canonical) =>
          assert_eq(
            canonical,
            "{\"userId\":\"150\",\"displayName\":\"Alice\",\"phoneNumber\":\"123\"}",
          )
      }
    }
  }
  match json_to_message(desc, "{\"user_id\":\"1\",\"userId\":\"2\"}") {
    JsonDecodeOk(_) => fail("snake_case and lowerCamel aliases should duplicate")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected lowerCamel duplicate error")
  }
  match json_to_message(desc, "{\"displayname\":\"Alice\"}") {
    JsonDecodeOk(_) => fail("wrong JSON field case should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected lowerCamel unknown-field error")
  }
  let wrapper_desc = MessageDescriptor::{
    name: "Wrapper",
    fields: [
      FieldDescriptor::{
        name: "profile",
        typ: NamedType("Profile"),
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "audit_log",
        typ: StringType,
        number: 2,
        label: Repeated,
      },
    ],
  }
  let wrapper = message_value([
    message_field(
      "profile",
      NestedMessageValue(
        message_value([
          message_field("user_id", UInt64Value(150UL)),
          message_field("display_name", StringValue("Alice")),
        ]),
      ),
    ),
    repeated_message_field("audit_log", [StringValue("created")]),
  ])
  match
    message_to_json_lower_camel_with_descriptors(
      wrapper_desc, [desc, wrapper_desc], wrapper,
    ) {
    JsonErr(_) => fail("nested lowerCamel JSON writer failed")
    JsonOk(canonical) =>
      assert_eq(
        canonical,
        "{\"profile\":{\"userId\":\"150\",\"displayName\":\"Alice\"},\"auditLog\":[\"created\"]}",
      )
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
test "upstream-style wire decode edge vector" {
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
        name: "samples",
        typ: UInt64Type,
        number: 7,
        label: Repeated,
      },
    ],
  }
  // Duplicate singular field 1 keeps the final value, field 99 is unknown and
  // skipped, and repeated field 7 arrives once unpacked and once packed.
  let wire =
    b"\x08\x01\x98\x06\xb9\x60\x38\x01\x38\x96\x01\x3a\x02\x02\x03\x12\x03Bob\x08\x96\x01"
  match decode_message(desc, wire) {
    DecodeMessageErr(_) => fail("wire edge vector decode failed")
    DecodeMessageOk(decoded, next) => {
      assert_eq(next, wire.length())
      assert_true(
        decoded ==
        message_value([
          message_field("id", UInt64Value(150UL)),
          repeated_message_field("samples", [
            UInt64Value(1UL),
            UInt64Value(150UL),
            UInt64Value(2UL),
            UInt64Value(3UL),
          ]),
          message_field("name", StringValue("Bob")),
        ]),
      )
      match message_to_json(desc, decoded) {
        JsonErr(_) => fail("wire edge vector JSON render failed")
        JsonOk(json) =>
          assert_eq(
            json,
            "{\"id\":\"150\",\"name\":\"Bob\",\"samples\":[\"1\",\"150\",\"2\",\"3\"]}",
          )
      }
    }
  }
}

///|
test "official python protobuf oracle 32-bit numeric bytes and json" {
  let desc = MessageDescriptor::{
    name: "Numbers32",
    fields: [
      FieldDescriptor::{
        name: "u",
        typ: UInt32Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "i",
        typ: Int32Type,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "s",
        typ: SInt32Type,
        number: 3,
        label: Singular,
      },
      FieldDescriptor::{
        name: "f",
        typ: Fixed32Type,
        number: 4,
        label: Singular,
      },
      FieldDescriptor::{
        name: "sf",
        typ: SFixed32Type,
        number: 5,
        label: Singular,
      },
    ],
  }
  let msg = message_value([
    message_field("u", UInt64Value(0xffffffffUL)),
    message_field("i", Int64Value(-1L)),
    message_field("s", Int64Value(-2L)),
    message_field("f", UInt64Value(0xffffffffUL)),
    message_field("sf", Int64Value(-3L)),
  ])
  let oracle_bytes = b"\x08\xff\xff\xff\xff\x0f\x10\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01\x18\x03\x25\xff\xff\xff\xff\x2d\xfd\xff\xff\xff"
  let oracle_json = "{\"u\":4294967295,\"i\":-1,\"s\":-2,\"f\":4294967295,\"sf\":-3}"
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("encoding numbers32 oracle failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, oracle_bytes)
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("decoding numbers32 oracle failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
    }
  }
  match message_to_json(desc, msg) {
    JsonErr(_) => fail("numbers32 oracle JSON render failed")
    JsonOk(json) => assert_eq(json, oracle_json)
  }
  match json_to_message(desc, oracle_json) {
    JsonDecodeErr(_) => fail("numbers32 oracle JSON parse failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
}

///|
test "official python protobuf oracle float and double bytes and json" {
  let desc = MessageDescriptor::{
    name: "Floats",
    fields: [
      FieldDescriptor::{
        name: "f",
        typ: FloatType,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "d",
        typ: DoubleType,
        number: 2,
        label: Singular,
      },
    ],
  }
  let msg = message_value([
    message_field("f", FloatValue(Float::from_double(1.5))),
    message_field("d", DoubleValue(-2.25)),
  ])
  let oracle_bytes = b"\x0d\x00\x00\xc0\x3f\x11\x00\x00\x00\x00\x00\x00\x02\xc0"
  let oracle_json = "{\"f\":1.5,\"d\":-2.25}"
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("encoding floats oracle failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, oracle_bytes)
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("decoding floats oracle failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
    }
  }
  match message_to_json(desc, msg) {
    JsonErr(_) => fail("floats oracle JSON render failed")
    JsonOk(json) => assert_eq(json, oracle_json)
  }
  match json_to_message(desc, oracle_json) {
    JsonDecodeErr(_) => fail("floats oracle JSON parse failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
}

///|
test "official python protobuf oracle float special JSON strings" {
  let desc = MessageDescriptor::{
    name: "FloatSpecials",
    fields: [
      FieldDescriptor::{
        name: "f_nan",
        typ: FloatType,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "f_inf",
        typ: FloatType,
        number: 2,
        label: Singular,
      },
      FieldDescriptor::{
        name: "d_neg_inf",
        typ: DoubleType,
        number: 3,
        label: Singular,
      },
    ],
  }
  let msg = message_value([
    message_field("f_nan", FloatValue(Float::reinterpret_from_uint(0x7fc00000U))),
    message_field("f_inf", FloatValue(Float::reinterpret_from_uint(0x7f800000U))),
    message_field(
      "d_neg_inf",
      DoubleValue(0xfff0000000000000UL.reinterpret_as_double()),
    ),
  ])
  let oracle_bytes = b"\x0d\x00\x00\xc0\x7f\x15\x00\x00\x80\x7f\x19\x00\x00\x00\x00\x00\x00\xf0\xff"
  let oracle_json = "{\"f_nan\":\"NaN\",\"f_inf\":\"Infinity\",\"d_neg_inf\":\"-Infinity\"}"
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("encoding float specials oracle failed")
    EncodeMessageOk(bytes) => assert_eq(bytes, oracle_bytes)
  }
  match message_to_json(desc, msg) {
    JsonErr(_) => fail("float specials oracle JSON render failed")
    JsonOk(json) => assert_eq(json, oracle_json)
  }
  match json_to_message(desc, oracle_json) {
    JsonDecodeErr(_) => fail("float specials oracle JSON parse failed")
    JsonDecodeOk(decoded) => {
      match decoded.fields[0].values[0] {
        FloatValue(v) => assert_true(v.is_nan())
        _ => fail("f_nan should parse as FloatValue")
      }
      match decoded.fields[1].values[0] {
        FloatValue(v) => assert_true(v.is_pos_inf())
        _ => fail("f_inf should parse as FloatValue")
      }
      match decoded.fields[2].values[0] {
        DoubleValue(v) => assert_true(v.is_neg_inf())
        _ => fail("d_neg_inf should parse as DoubleValue")
      }
    }
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
        allow_alias: false,
        values: [
          EnumValueDescriptor::{ name: "RED", number: 1 },
          EnumValueDescriptor::{ name: "RED", number: 1 },
        ],
      },
    ],
    message_reservations: [],
    enum_reservations: [],
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
test "enum allow_alias permits duplicate enum numbers" {
  let src =
    #|syntax = "proto3";
    #|enum Status {
    #|  option allow_alias = true;
    #|  STATUS_UNSPECIFIED = 0;
    #|  STATUS_OK = 1;
    #|  STATUS_SUCCESS = 1;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("allow_alias enum should parse")
    ProtoOk(file) => {
      assert_eq(file.enums.length(), 1)
      assert_true(file.enums[0].allow_alias)
      assert_eq(file.enums[0].values.length(), 3)
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("allow_alias : true"))
      assert_true(generated.contains("STATUS_SUCCESS"))
    }
  }
}

///|
test "enum duplicate number requires allow_alias" {
  let src =
    #|syntax = "proto3";
    #|enum Status {
    #|  STATUS_UNSPECIFIED = 0;
    #|  STATUS_OK = 1;
    #|  STATUS_SUCCESS = 1;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("duplicate enum number schema should parse then validate")
    ProtoOk(file) =>
      match validate_proto_file(file) {
        SchemaValid => fail("duplicate enum number should fail without allow_alias")
        SchemaInvalid(issues) => {
          assert_eq(issues.length(), 1)
          assert_eq(issues[0].message, "duplicate enum value number")
        }
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

///|
test "parse and codegen map fields" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|message Bag {
    #|  map<string, uint64> scores = 1;
    #|  map<int64, string> labels = 2;
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("map parser failed")
    ProtoOk(file) => {
      assert_eq(file.messages.length(), 1)
      assert_eq(file.messages[0].fields.length(), 2)
      assert_true(
        file.messages[0].fields[0].typ == MapType(StringType, UInt64Type),
      )
      assert_true(file.messages[0].fields[0].label == Repeated)
      assert_true(
        file.messages[0].fields[1].typ == MapType(Int64Type, StringType),
      )
      let generated = generate_moonbit_source(file)
      let expected =
        #|pub(all) struct Bag {
        #|  scores : Array[MessageValue]
        #|  labels : Array[MessageValue]
        #|} derive(Debug, Eq)
        #|
        #|pub fn descriptor_Bag() -> MessageDescriptor {
        #|  MessageDescriptor::{
        #|    name : "Bag",
        #|    fields : [
        #|      FieldDescriptor::{ name : "scores", typ : MapType(StringType, UInt64Type), number : 1, label : Repeated },
        #|      FieldDescriptor::{ name : "labels", typ : MapType(Int64Type, StringType), number : 2, label : Repeated },
        #|    ],
        #|  }
        #|}
        #|
        #|pub fn message_descriptors() -> Array[MessageDescriptor] {
        #|  [
        #|    descriptor_Bag(),
        #|  ]
        #|}
        #|
        #|pub fn enum_descriptors() -> Array[EnumDescriptor] {
        #|  [
        #|  ]
        #|}
        #|
        #|pub fn encode_Bag(value : MessageValue) -> EncodeMessageResult {
        #|  encode_message_with_descriptors(descriptor_Bag(), message_descriptors(), value)
        #|}
        #|
        #|pub fn decode_Bag(input : Bytes) -> DecodeMessageResult {
        #|  decode_message_with_descriptors(descriptor_Bag(), message_descriptors(), input)
        #|}
        #|
        #|pub fn to_json_Bag(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_with_schema(descriptor_Bag(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn to_json_lower_camel_Bag(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_lower_camel_with_schema(descriptor_Bag(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn from_json_Bag(input : String) -> JsonDecodeResult {
        #|  json_to_message_with_schema(descriptor_Bag(), message_descriptors(), enum_descriptors(), input)
        #|}
      assert_eq(generated, expected)
    }
  }
}

///|
test "map fields binary and json roundtrip" {
  let desc = MessageDescriptor::{
    name: "Bag",
    fields: [
      FieldDescriptor::{
        name: "scores",
        typ: MapType(StringType, UInt64Type),
        number: 1,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "labels",
        typ: MapType(Int64Type, StringType),
        number: 2,
        label: Repeated,
      },
    ],
  }
  let msg = message_value([
    repeated_message_field("scores", [
      map_entry_value(StringValue("alice"), UInt64Value(150UL)),
      map_entry_value(StringValue("bob"), UInt64Value(7UL)),
    ]),
    repeated_message_field("labels", [
      map_entry_value(Int64Value(2L), StringValue("two")),
      map_entry_value(Int64Value(7L), StringValue("seven")),
    ]),
  ])
  let alice_entry = concat_bytes([
    encode_string_field(1, "alice"),
    encode_uint64_field(2, 150UL),
  ])
  let bob_entry = concat_bytes([
    encode_string_field(1, "bob"),
    encode_uint64_field(2, 7UL),
  ])
  let two_entry = concat_bytes([
    encode_uint64_field(1, 2UL),
    encode_string_field(2, "two"),
  ])
  let seven_entry = concat_bytes([
    encode_uint64_field(1, 7UL),
    encode_string_field(2, "seven"),
  ])
  let expected_bytes = concat_bytes([
    encode_key(1, LengthDelimited),
    encode_length_delimited(alice_entry),
    encode_key(1, LengthDelimited),
    encode_length_delimited(bob_entry),
    encode_key(2, LengthDelimited),
    encode_length_delimited(two_entry),
    encode_key(2, LengthDelimited),
    encode_length_delimited(seven_entry),
  ])
  assert_eq(
    expected_bytes, b"\x0a\x0a\x0a\x05alice\x10\x96\x01\x0a\x07\x0a\x03bob\x10\x07\x12\x07\x08\x02\x12\x03two\x12\x09\x08\x07\x12\x05seven",
  )
  match encode_message(desc, msg) {
    EncodeMessageErr(_) => fail("map encode failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, expected_bytes)
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("map decode failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
    }
  }
  let json = "{\"scores\":{\"alice\":\"150\",\"bob\":\"7\"},\"labels\":{\"2\":\"two\",\"7\":\"seven\"}}"
  match message_to_json(desc, msg) {
    JsonErr(_) => fail("map JSON encode failed")
    JsonOk(encoded) => assert_eq(encoded, json)
  }
  match json_to_message(desc, json) {
    JsonDecodeErr(_) => fail("map JSON decode failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
}

///|
test "map enum values use schema-aware json names" {
  let enum_desc = EnumDescriptor::{
    name: "Color",
    values: [
      EnumValueDescriptor::{ name: "COLOR_UNSPECIFIED", number: 0 },
      EnumValueDescriptor::{ name: "RED", number: 1 },
      EnumValueDescriptor::{ name: "BLUE", number: 2 },
    ],
    allow_alias: false,
  }
  let desc = MessageDescriptor::{
    name: "Palette",
    fields: [
      FieldDescriptor::{
        name: "favorite_colors",
        typ: MapType(StringType, EnumType("Color")),
        number: 1,
        label: Repeated,
      },
    ],
  }
  let msg = message_value([
    repeated_message_field("favorite_colors", [
      map_entry_value(StringValue("primary"), Int64Value(2L)),
      map_entry_value(StringValue("backup"), Int64Value(1L)),
    ]),
  ])
  match message_to_json_with_schema(desc, [], [enum_desc], msg) {
    JsonErr(_) => fail("map enum JSON encode failed")
    JsonOk(json) =>
      assert_eq(
        json,
        "{\"favorite_colors\":{\"primary\":\"BLUE\",\"backup\":\"RED\"}}",
      )
  }
  match message_to_json_lower_camel_with_schema(desc, [], [enum_desc], msg) {
    JsonErr(_) => fail("map enum lowerCamel JSON encode failed")
    JsonOk(json) =>
      assert_eq(
        json,
        "{\"favoriteColors\":{\"primary\":\"BLUE\",\"backup\":\"RED\"}}",
      )
  }
  match
    json_to_message_with_schema(
      desc,
      [],
      [enum_desc],
      "{\"favoriteColors\":{\"primary\":\"BLUE\",\"backup\":1}}",
    ) {
    JsonDecodeErr(_) => fail("map enum JSON decode failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
  match
    json_to_message_with_schema(
      desc, [], [enum_desc], "{\"favoriteColors\":{\"primary\":\"GREEN\"}}",
    ) {
    JsonDecodeOk(_) => fail("unknown map enum JSON name should be rejected")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected map enum JSON error")
  }
}

///|
test "map fields support nested message values" {
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
  let book_desc = MessageDescriptor::{
    name: "Book",
    fields: [
      FieldDescriptor::{
        name: "contacts",
        typ: MapType(StringType, NamedType("Address")),
        number: 1,
        label: Repeated,
      },
    ],
  }
  let address = message_value([
    message_field("street", StringValue("Main")),
    message_field("zip", UInt64Value(94107UL)),
  ])
  let msg = message_value([
    repeated_message_field("contacts", [
      map_entry_value(StringValue("home"), NestedMessageValue(address)),
    ]),
  ])
  let address_bytes = concat_bytes([
    encode_string_field(1, "Main"),
    encode_uint64_field(2, 94107UL),
  ])
  let entry_bytes = concat_bytes([
    encode_string_field(1, "home"),
    concat_bytes([
      encode_key(2, LengthDelimited),
      encode_length_delimited(address_bytes),
    ]),
  ])
  let expected_bytes = concat_bytes([
    encode_key(1, LengthDelimited),
    encode_length_delimited(entry_bytes),
  ])
  let descriptors = [address_desc]
  match encode_message_with_descriptors(book_desc, descriptors, msg) {
    EncodeMessageErr(_) => fail("nested map encode failed")
    EncodeMessageOk(bytes) => {
      assert_eq(bytes, expected_bytes)
      match decode_message_with_descriptors(book_desc, descriptors, bytes) {
        DecodeMessageErr(_) => fail("nested map decode failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == msg)
        }
      }
    }
  }
  let json = "{\"contacts\":{\"home\":{\"street\":\"Main\",\"zip\":\"94107\"}}}"
  match message_to_json_with_descriptors(book_desc, descriptors, msg) {
    JsonErr(_) => fail("nested map JSON encode failed")
    JsonOk(encoded) => assert_eq(encoded, json)
  }
  match json_to_message_with_descriptors(book_desc, descriptors, json) {
    JsonDecodeErr(_) => fail("nested map JSON decode failed")
    JsonDecodeOk(decoded) => assert_true(decoded == msg)
  }
}

///|
test "map schema validation rejects unsupported key and nested map value" {
  let msg = MessageDescriptor::{
    name: "BadMaps",
    fields: [
      FieldDescriptor::{
        name: "bad_key",
        typ: MapType(BytesType, UInt64Type),
        number: 1,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "bad_value",
        typ: MapType(StringType, MapType(StringType, UInt64Type)),
        number: 2,
        label: Repeated,
      },
    ],
  }
  match validate_message_descriptor(msg) {
    SchemaValid => fail("invalid map schema should fail validation")
    SchemaInvalid(issues) => {
      assert_eq(issues.length(), 2)
      assert_eq(issues[0].message, "invalid map key type")
      assert_eq(issues[1].message, "map value must not be a map")
    }
  }
}

///|
test "parse and codegen oneof fields" {
  let src =
    #|syntax = "proto3";
    #|package demo;
    #|message Contact {
    #|  uint64 id = 1;
    #|  oneof reach {
    #|    string email = 2;
    #|    string phone = 3;
    #|  }
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("oneof parser failed")
    ProtoOk(file) => {
      assert_eq(file.messages.length(), 1)
      assert_eq(file.messages[0].fields.length(), 3)
      assert_true(file.messages[0].fields[1].label == Oneof("reach"))
      assert_true(file.messages[0].fields[2].label == Oneof("reach"))
      let generated = generate_moonbit_source(file)
      let expected =
        #|pub(all) struct Contact {
        #|  id : UInt64
        #|  email : String?
        #|  phone : String?
        #|} derive(Debug, Eq)
        #|
        #|pub fn descriptor_Contact() -> MessageDescriptor {
        #|  MessageDescriptor::{
        #|    name : "Contact",
        #|    fields : [
        #|      FieldDescriptor::{ name : "id", typ : UInt64Type, number : 1, label : Singular },
        #|      FieldDescriptor::{ name : "email", typ : StringType, number : 2, label : Oneof("reach") },
        #|      FieldDescriptor::{ name : "phone", typ : StringType, number : 3, label : Oneof("reach") },
        #|    ],
        #|  }
        #|}
        #|
        #|pub fn message_descriptors() -> Array[MessageDescriptor] {
        #|  [
        #|    descriptor_Contact(),
        #|  ]
        #|}
        #|
        #|pub fn enum_descriptors() -> Array[EnumDescriptor] {
        #|  [
        #|  ]
        #|}
        #|
        #|pub fn encode_Contact(value : MessageValue) -> EncodeMessageResult {
        #|  encode_message_with_descriptors(descriptor_Contact(), message_descriptors(), value)
        #|}
        #|
        #|pub fn decode_Contact(input : Bytes) -> DecodeMessageResult {
        #|  decode_message_with_descriptors(descriptor_Contact(), message_descriptors(), input)
        #|}
        #|
        #|pub fn to_json_Contact(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_with_schema(descriptor_Contact(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn to_json_lower_camel_Contact(value : MessageValue) -> JsonEncodeResult {
        #|  message_to_json_lower_camel_with_schema(descriptor_Contact(), message_descriptors(), enum_descriptors(), value)
        #|}
        #|
        #|pub fn from_json_Contact(input : String) -> JsonDecodeResult {
        #|  json_to_message_with_schema(descriptor_Contact(), message_descriptors(), enum_descriptors(), input)
        #|}
      assert_eq(generated, expected)
    }
  }
}

///|
test "parser tolerates oneof option statements" {
  let src =
    #|syntax = "proto3";
    #|package demo.oneof_options;
    #|message RoutedContact {
    #|  oneof route {
    #|    option (demo.route) = { priority: "primary; still option" };
    #|    string email = 1;
    #|    string phone = 2;
    #|  }
    #|}
  match parse_proto(src) {
    ProtoErr(_) => fail("oneof option schema should parse")
    ProtoOk(file) => {
      assert_eq(file.messages.length(), 1)
      assert_eq(file.messages[0].name, "RoutedContact")
      assert_eq(file.messages[0].fields.length(), 2)
      assert_true(file.messages[0].fields[0].label == Oneof("route"))
      assert_true(file.messages[0].fields[1].label == Oneof("route"))
      assert_true(schema_is_valid(file))
      let generated = generate_moonbit_source(file)
      assert_true(generated.contains("email : String?"))
      assert_true(generated.contains("phone : String?"))
      assert_true(generated.contains("Oneof(\"route\")"))
    }
  }
}

///|
test "oneof binary and json semantics" {
  let desc = MessageDescriptor::{
    name: "Contact",
    fields: [
      FieldDescriptor::{
        name: "id",
        typ: UInt64Type,
        number: 1,
        label: Singular,
      },
      FieldDescriptor::{
        name: "email",
        typ: StringType,
        number: 2,
        label: Oneof("reach"),
      },
      FieldDescriptor::{
        name: "phone",
        typ: StringType,
        number: 3,
        label: Oneof("reach"),
      },
    ],
  }
  let by_email = message_value([
    message_field("id", UInt64Value(1UL)),
    message_field("email", StringValue("a@example.com")),
  ])
  match encode_message(desc, by_email) {
    EncodeMessageErr(_) => fail("oneof encode failed")
    EncodeMessageOk(bytes) => {
      assert_eq(
        bytes,
        concat_bytes([
          encode_uint64_field(1, 1UL),
          encode_string_field(2, "a@example.com"),
        ]),
      )
      match decode_message(desc, bytes) {
        DecodeMessageErr(_) => fail("oneof decode failed")
        DecodeMessageOk(decoded, next) => {
          assert_eq(next, bytes.length())
          assert_true(decoded == by_email)
        }
      }
    }
  }
  let conflicting = message_value([
    message_field("email", StringValue("a@example.com")),
    message_field("phone", StringValue("123")),
  ])
  match encode_message(desc, conflicting) {
    EncodeMessageOk(_) => fail("oneof encoder should reject conflicts")
    EncodeMessageErr(Unsupported(_)) => ()
    EncodeMessageErr(_) => fail("unexpected oneof encode error")
  }
  let last_one_wins = concat_bytes([
    encode_string_field(2, "a@example.com"),
    encode_string_field(3, "123"),
  ])
  match decode_message(desc, last_one_wins) {
    DecodeMessageErr(_) => fail("oneof last-one-wins decode failed")
    DecodeMessageOk(decoded, next) => {
      assert_eq(next, last_one_wins.length())
      assert_true(
        decoded == message_value([message_field("phone", StringValue("123"))]),
      )
    }
  }
  match message_to_json(desc, by_email) {
    JsonErr(_) => fail("oneof JSON encode failed")
    JsonOk(json) =>
      assert_eq(json, "{\"id\":\"1\",\"email\":\"a@example.com\"}")
  }
  let by_phone = message_value([
    message_field("id", UInt64Value(1UL)),
    message_field("phone", StringValue("123")),
  ])
  match encode_message(desc, by_phone) {
    EncodeMessageErr(_) => fail("oneof phone encode failed")
    EncodeMessageOk(bytes) => assert_eq(bytes, b"\x08\x01\x1a\x03123")
  }
  match message_to_json(desc, by_phone) {
    JsonErr(_) => fail("oneof phone JSON encode failed")
    JsonOk(json) => assert_eq(json, "{\"id\":\"1\",\"phone\":\"123\"}")
  }
  match json_to_message(desc, "{\"phone\":\"123\",\"id\":\"1\"}") {
    JsonDecodeErr(_) => fail("oneof JSON decode failed")
    JsonDecodeOk(decoded) =>
      assert_true(
        decoded ==
        message_value([
          message_field("id", UInt64Value(1UL)),
          message_field("phone", StringValue("123")),
        ]),
      )
  }
  match
    json_to_message(desc, "{\"email\":\"a@example.com\",\"phone\":\"123\"}") {
    JsonDecodeOk(_) => fail("oneof JSON parser should reject conflicts")
    JsonDecodeErr(Unsupported(_)) => ()
    JsonDecodeErr(_) => fail("unexpected oneof JSON error")
  }
}

///|
fn deterministic_u64(seed : Int) -> UInt64 {
  let x = seed.to_uint64()
  (x * 9973UL) ^ (x << 9) ^ (x >> 3)
}

///|
fn deterministic_i64(seed : Int) -> Int64 {
  if seed % 2 == 0 {
    (seed * 7919).to_int64()
  } else {
    (-(seed * 7919)).to_int64()
  }
}

///|
test "property varint roundtrip deterministic corpus" {
  for i = 0; i < 256; i = i + 1 {
    let value = deterministic_u64(i)
    let encoded = encode_varint_u64(value)
    match decode_varint_u64(encoded) {
      U64Err(_) => fail("varint deterministic corpus decode failed")
      U64Ok(decoded, next) => {
        assert_eq(decoded, value)
        assert_eq(next, encoded.length())
      }
    }
  }
  let edge_cases = [
    0UL, 1UL, 127UL, 128UL, 16383UL, 16384UL, 0xffffffffUL, 0xffffffffffffffffUL,
  ]
  for value in edge_cases {
    let encoded = encode_varint_u64(value)
    match decode_varint_u64(encoded) {
      U64Err(_) => fail("varint edge decode failed")
      U64Ok(decoded, next) => {
        assert_eq(decoded, value)
        assert_eq(next, encoded.length())
      }
    }
  }
}

///|
test "property zigzag roundtrip deterministic corpus" {
  for i = -128; i <= 128; i = i + 1 {
    assert_eq(decode_zigzag_int(encode_zigzag_int(i)), i)
  }
  for i = 0; i < 256; i = i + 1 {
    let value = deterministic_i64(i)
    assert_eq(decode_zigzag_i64(encode_zigzag_i64(value)), value)
  }
}

///|
test "property dynamic message binary and json roundtrip corpus" {
  let desc = MessageDescriptor::{
    name: "Sample",
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
        name: "score",
        typ: SInt64Type,
        number: 4,
        label: Singular,
      },
      FieldDescriptor::{
        name: "tags",
        typ: StringType,
        number: 5,
        label: Repeated,
      },
      FieldDescriptor::{
        name: "samples",
        typ: UInt64Type,
        number: 6,
        label: Repeated,
      },
    ],
  }
  for i = 0; i < 64; i = i + 1 {
    let id = deterministic_u64(i)
    let score = deterministic_i64(i)
    let msg = message_value([
      message_field("id", UInt64Value(id)),
      message_field("name", StringValue("user" + i.to_string())),
      message_field("active", BoolValue(i % 2 == 0)),
      message_field("score", Int64Value(score)),
      repeated_message_field("tags", [
        StringValue("tag" + i.to_string()),
        StringValue("group" + (i % 7).to_string()),
      ]),
      repeated_message_field("samples", [
        UInt64Value(deterministic_u64(i + 1)),
        UInt64Value(deterministic_u64(i + 2)),
      ]),
    ])
    match encode_message(desc, msg) {
      EncodeMessageErr(_) => fail("property message encode failed")
      EncodeMessageOk(bytes) =>
        match decode_message(desc, bytes) {
          DecodeMessageErr(_) => fail("property message decode failed")
          DecodeMessageOk(decoded, next) => {
            assert_eq(next, bytes.length())
            assert_true(decoded == msg)
          }
        }
    }
    match message_to_json(desc, msg) {
      JsonErr(_) => fail("property message json encode failed")
      JsonOk(json) =>
        match json_to_message(desc, json) {
          JsonDecodeErr(_) => fail("property message json decode failed")
          JsonDecodeOk(decoded) => assert_true(decoded == msg)
        }
    }
  }
}
