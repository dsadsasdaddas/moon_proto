///| Concatenate byte buffers without exposing mutable implementation details.
pub fn concat_bytes(parts : Array[Bytes]) -> Bytes {
  let out : Array[Byte] = []
  for part in parts {
    for b in part.to_array() {
      out.push(b)
    }
  }
  Bytes::from_array(out)
}

///| Encode a length-delimited payload: varint length followed by bytes.
pub fn encode_length_delimited(payload : Bytes) -> Bytes {
  concat_bytes([encode_varint_u64(payload.length().to_uint64()), payload])
}

///| Encode a UTF-8 string as length-delimited protobuf data.
pub fn encode_string(value : String) -> Bytes {
  encode_length_delimited(@utf8.encode(value))
}

///| Decode a length-delimited payload from `input`.
pub fn decode_length_delimited(input : Bytes, offset? : Int = 0) -> DecodeBytesResult {
  match decode_varint_u64(input, offset=offset) {
    U64Err(e) => BytesErr(e)
    U64Ok(len64, next) => {
      let len = len64.to_int()
      if len < 0 {
        return BytesErr(NegativeLength)
      }
      let arr = input.to_array()
      if next + len > arr.length() {
        return BytesErr(UnexpectedEof)
      }
      let out : Array[Byte] = []
      for i = next; i < next + len; i = i + 1 {
        out.push(arr[i])
      }
      BytesOk(Bytes::from_array(out), next + len)
    }
  }
}

///| Decode a UTF-8 string lossily from length-delimited protobuf data.
pub fn decode_string_lossy(input : Bytes, offset? : Int = 0) -> DecodeStringResult {
  match decode_length_delimited(input, offset=offset) {
    BytesErr(e) => StringErr(e)
    BytesOk(payload, next) => StringOk(@utf8.decode_lossy(payload[:]), next)
  }
}

///| Result of reading a string.
pub(all) enum DecodeStringResult {
  StringOk(String, Int)
  StringErr(DecodeError)
} derive(Debug, Eq)
