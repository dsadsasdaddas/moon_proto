///|
/// Encode a UInt64 using protobuf's unsigned base-128 varint format.
pub fn encode_varint_u64(value : UInt64) -> Bytes {
  let out : Array[Byte] = []
  for v = value {
    if v < 128UL {
      out.push(v.to_byte())
      break
    } else {
      out.push(((v & 0x7fUL) | 0x80UL).to_byte())
      continue v >> 7
    }
  }
  Bytes::from_array(out)
}

///|
/// Encode a UInt32/UInt as a protobuf varint.
pub fn encode_varint_uint(value : UInt) -> Bytes {
  encode_varint_u64(value.to_uint64())
}

///|
/// Decode a UInt64 varint from `input` starting at `offset`.
pub fn decode_varint_u64(input : Bytes, offset? : Int = 0) -> DecodeU64Result {
  let bytes = input.to_array()
  if offset < 0 || offset > bytes.length() {
    return U64Err(UnexpectedEof)
  }
  let mut result : UInt64 = 0UL
  let mut shift = 0
  let mut index = offset
  while index < bytes.length() {
    let b = bytes[index].to_uint64()
    let payload = b & 0x7fUL
    if shift >= 64 || (shift == 63 && payload > 1UL) {
      return U64Err(VarintOverflow)
    }
    result = result | (payload << shift)
    index = index + 1
    if (b & 0x80UL) == 0UL {
      return U64Ok(result, index)
    }
    shift = shift + 7
    if index - offset >= 10 {
      return U64Err(VarintOverflow)
    }
  }
  U64Err(UnexpectedEof)
}
