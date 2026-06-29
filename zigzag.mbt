///|
/// Encode a signed 32-bit-ish Int with protobuf zig-zag mapping.
pub fn encode_zigzag_int(value : Int) -> UInt {
  ((value << 1) ^ (value >> 31)).reinterpret_as_uint()
}

///|
/// Decode a zig-zag UInt into an Int.
pub fn decode_zigzag_int(value : UInt) -> Int {
  (value >> 1).reinterpret_as_int() ^ -(value & 1U).reinterpret_as_int()
}

///|
/// Encode an Int64 with protobuf zig-zag mapping.
pub fn encode_zigzag_i64(value : Int64) -> UInt64 {
  ((value << 1) ^ (value >> 63)).reinterpret_as_uint64()
}

///|
/// Decode a zig-zag UInt64 into Int64.
pub fn decode_zigzag_i64(value : UInt64) -> Int64 {
  (value >> 1).reinterpret_as_int64() ^ -(value & 1UL).reinterpret_as_int64()
}
