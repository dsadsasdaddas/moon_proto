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
  assert_eq(encode_fixed64(0x0102030405060708UL), b"\x08\x07\x06\x05\x04\x03\x02\x01")
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
  let src = #|syntax = "proto3";
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
    }
    ProtoErr(_) => fail("expected parser to accept simple proto")
  }
}
