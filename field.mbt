///| Small dynamic value type used by field helpers and the schema-driven

///| runtime. Integer scalar values are carried in 64-bit containers so the

///| dynamic API can represent uint32/uint64, int32/int64, sint32/sint64 and

///|
/// fixed32/fixed64 without a large amount of boxing.
pub(all) enum ProtoValue {
  UInt64Value(UInt64)
  Int64Value(Int64)
  BoolValue(Bool)
  StringValue(String)
  BytesValue(Bytes)
  NestedMessageValue(MessageValue)
} derive(Debug, Eq)

///|
/// Encode `uint32`/`uint64` field payload with its key.
pub fn encode_uint64_field(field_number : Int, value : UInt64) -> Bytes {
  concat_bytes([encode_key(field_number, Varint), encode_varint_u64(value)])
}

///|
/// Encode a bool field payload with its key.
pub fn encode_bool_field(field_number : Int, value : Bool) -> Bytes {
  encode_uint64_field(field_number, if value { 1UL } else { 0UL })
}

///|
/// Encode a sint64 field payload with protobuf zig-zag mapping and key.
pub fn encode_sint64_field(field_number : Int, value : Int64) -> Bytes {
  concat_bytes([
    encode_key(field_number, Varint),
    encode_varint_u64(encode_zigzag_i64(value)),
  ])
}

///|
/// Encode a string field payload with its key.
pub fn encode_string_field(field_number : Int, value : String) -> Bytes {
  concat_bytes([encode_key(field_number, LengthDelimited), encode_string(value)])
}

///|
/// Encode a bytes field payload with its key.
pub fn encode_bytes_field(field_number : Int, value : Bytes) -> Bytes {
  concat_bytes([
    encode_key(field_number, LengthDelimited),
    encode_length_delimited(value),
  ])
}
