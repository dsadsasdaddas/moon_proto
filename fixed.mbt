///|
/// Encode a fixed32 value in protobuf little-endian order.
pub fn encode_fixed32(value : UInt) -> Bytes {
  Bytes::from_array([
    (value & 0xffU).to_byte(),
    ((value >> 8) & 0xffU).to_byte(),
    ((value >> 16) & 0xffU).to_byte(),
    ((value >> 24) & 0xffU).to_byte(),
  ])
}

///|
/// Decode a fixed32 value from protobuf little-endian order.
pub fn decode_fixed32(input : Bytes, offset? : Int = 0) -> DecodeU32Result {
  let b = input.to_array()
  if offset < 0 || offset + 4 > b.length() {
    return U32Err(UnexpectedEof)
  }
  let v = b[offset].to_uint() |
    (b[offset + 1].to_uint() << 8) |
    (b[offset + 2].to_uint() << 16) |
    (b[offset + 3].to_uint() << 24)
  U32Ok(v, offset + 4)
}

///|
/// Encode a fixed64 value in protobuf little-endian order.
pub fn encode_fixed64(value : UInt64) -> Bytes {
  Bytes::from_array([
    (value & 0xffUL).to_byte(),
    ((value >> 8) & 0xffUL).to_byte(),
    ((value >> 16) & 0xffUL).to_byte(),
    ((value >> 24) & 0xffUL).to_byte(),
    ((value >> 32) & 0xffUL).to_byte(),
    ((value >> 40) & 0xffUL).to_byte(),
    ((value >> 48) & 0xffUL).to_byte(),
    ((value >> 56) & 0xffUL).to_byte(),
  ])
}

///|
/// Decode a fixed64 value from protobuf little-endian order.
pub fn decode_fixed64(input : Bytes, offset? : Int = 0) -> DecodeU64FixedResult {
  let b = input.to_array()
  if offset < 0 || offset + 8 > b.length() {
    return U64FixedErr(UnexpectedEof)
  }
  let v = b[offset].to_uint64() |
    (b[offset + 1].to_uint64() << 8) |
    (b[offset + 2].to_uint64() << 16) |
    (b[offset + 3].to_uint64() << 24) |
    (b[offset + 4].to_uint64() << 32) |
    (b[offset + 5].to_uint64() << 40) |
    (b[offset + 6].to_uint64() << 48) |
    (b[offset + 7].to_uint64() << 56)
  U64FixedOk(v, offset + 8)
}
