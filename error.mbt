///| Error values returned by the small, allocation-light protobuf readers.
pub(all) enum DecodeError {
  UnexpectedEof
  VarintOverflow
  InvalidWireType(Int)
  InvalidFieldNumber(Int)
  NegativeLength
  Unsupported(String)
} derive(Debug, Eq)

///| Result of reading an unsigned protobuf varint.
pub(all) enum DecodeU64Result {
  U64Ok(UInt64, Int)
  U64Err(DecodeError)
} derive(Debug, Eq)

///| Result of reading a 32-bit little-endian fixed value.
pub(all) enum DecodeU32Result {
  U32Ok(UInt, Int)
  U32Err(DecodeError)
} derive(Debug, Eq)

///| Result of reading a 64-bit little-endian fixed value.
pub(all) enum DecodeU64FixedResult {
  U64FixedOk(UInt64, Int)
  U64FixedErr(DecodeError)
} derive(Debug, Eq)

///| Result of reading a length-delimited payload.
pub(all) enum DecodeBytesResult {
  BytesOk(Bytes, Int)
  BytesErr(DecodeError)
} derive(Debug, Eq)
