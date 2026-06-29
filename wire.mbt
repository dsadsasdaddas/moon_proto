///| Protobuf wire type numbers as defined by the encoding specification.
pub(all) enum WireType {
  Varint
  Fixed64
  LengthDelimited
  StartGroup
  EndGroup
  Fixed32
} derive(Debug, Eq)

///| Numeric tag used in the low three bits of a protobuf key.
pub fn WireType::number(self : WireType) -> Int {
  match self {
    Varint => 0
    Fixed64 => 1
    LengthDelimited => 2
    StartGroup => 3
    EndGroup => 4
    Fixed32 => 5
  }
}

///| Convert a raw wire type number to a typed value.
pub fn wire_type_from_number(n : Int) -> WireType? {
  match n {
    0 => Some(Varint)
    1 => Some(Fixed64)
    2 => Some(LengthDelimited)
    3 => Some(StartGroup)
    4 => Some(EndGroup)
    5 => Some(Fixed32)
    _ => None
  }
}

///| Build a protobuf key: `(field_number << 3) | wire_type`.
pub fn make_key(field_number : Int, wire : WireType) -> UInt64 {
  (field_number.to_uint64() << 3) | wire.number().to_uint64()
}

///| Result of splitting a protobuf key into field number and wire type.
pub(all) enum ParseKeyResult {
  KeyOk(Int, WireType)
  KeyErr(DecodeError)
} derive(Debug, Eq)

///| Parse a raw protobuf key varint value.
pub fn parse_key(raw : UInt64) -> ParseKeyResult {
  let field_number = (raw >> 3).to_int()
  let wire_num = (raw & 7UL).to_int()
  if field_number <= 0 {
    KeyErr(InvalidFieldNumber(field_number))
  } else {
    match wire_type_from_number(wire_num) {
      Some(w) => KeyOk(field_number, w)
      None => KeyErr(InvalidWireType(wire_num))
    }
  }
}

///| Encode a key as a protobuf varint.
pub fn encode_key(field_number : Int, wire : WireType) -> Bytes {
  encode_varint_u64(make_key(field_number, wire))
}
