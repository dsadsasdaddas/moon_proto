///| A decoded or to-be-encoded field. Repeated protobuf fields use the same

///| field name with multiple values; singular fields should contain exactly

///|
/// one value.
pub(all) struct MessageField {
  name : String
  values : Array[ProtoValue]
} derive(Debug, Eq)

///|
/// Dynamic message value consumed and produced by the schema-driven runtime.
pub(all) struct MessageValue {
  fields : Array[MessageField]
} derive(Debug, Eq)

///|
/// Result of encoding a dynamic message.
pub(all) enum EncodeMessageResult {
  EncodeMessageOk(Bytes)
  EncodeMessageErr(DecodeError)
} derive(Debug, Eq)

///| Result of decoding a dynamic message. The second integer is the next byte

///|
/// offset after the decoded message.
pub(all) enum DecodeMessageResult {
  DecodeMessageOk(MessageValue, Int)
  DecodeMessageErr(DecodeError)
} derive(Debug, Eq)

///|
priv enum EncodeFieldResult {
  EncodedField(Bytes)
  EncodeFieldErr(DecodeError)
}

///|
priv enum DecodeScalarResult {
  DecodedScalar(ProtoValue, Int)
  DecodeScalarErr(DecodeError)
}

///|
priv enum DecodePackedResult {
  DecodedPacked(Array[ProtoValue], Int)
  DecodePackedErr(DecodeError)
}

///|
priv enum SkipResult {
  SkipOk(Int)
  SkipErr(DecodeError)
}

///|
/// Convenience constructor for a singular field.
pub fn message_field(name : String, value : ProtoValue) -> MessageField {
  MessageField::{ name, values: [value] }
}

///|
/// Convenience constructor for a repeated field.
pub fn repeated_message_field(
  name : String,
  values : Array[ProtoValue],
) -> MessageField {
  MessageField::{ name, values }
}

///|
/// Convenience constructor for a dynamic message.
pub fn message_value(fields : Array[MessageField]) -> MessageValue {
  MessageValue::{ fields, }
}

///|
/// Convenience constructor for a protobuf map entry value. Map fields are
/// represented as repeated `MapEntryValue` items in the dynamic API.
pub fn map_entry_value(key : ProtoValue, value : ProtoValue) -> ProtoValue {
  MapEntryValue(
    message_value([message_field("key", key), message_field("value", value)]),
  )
}

///|
fn find_field_by_name(
  desc : MessageDescriptor,
  name : String,
) -> FieldDescriptor? {
  for f in desc.fields {
    if f.name == name {
      return Some(f)
    }
  }
  None
}

///|
fn find_field_by_number(
  desc : MessageDescriptor,
  number : Int,
) -> FieldDescriptor? {
  for f in desc.fields {
    if f.number == number {
      return Some(f)
    }
  }
  None
}

///|
fn has_field_name(desc : MessageDescriptor, name : String) -> Bool {
  match find_field_by_name(desc, name) {
    Some(_) => true
    None => false
  }
}

///|
fn find_message_descriptor(
  descriptors : Array[MessageDescriptor],
  name : String,
) -> MessageDescriptor? {
  for desc in descriptors {
    if desc.name == name {
      return Some(desc)
    }
  }
  None
}

///|
fn bool_to_u64(value : Bool) -> UInt64 {
  if value {
    1UL
  } else {
    0UL
  }
}

///|
fn map_entry_descriptor(
  key_typ : ScalarType,
  value_typ : ScalarType,
) -> MessageDescriptor {
  MessageDescriptor::{
    name: "MapEntry",
    fields: [
      FieldDescriptor::{ name: "key", typ: key_typ, number: 1, label: Singular },
      FieldDescriptor::{
        name: "value",
        typ: value_typ,
        number: 2,
        label: Singular,
      },
    ],
  }
}

///|
fn is_packable_scalar(typ : ScalarType) -> Bool {
  match typ {
    Int32Type
    | Int64Type
    | UInt32Type
    | UInt64Type
    | SInt32Type
    | SInt64Type
    | Fixed32Type
    | Fixed64Type
    | SFixed32Type
    | SFixed64Type
    | EnumType(_)
    | BoolType => true
    _ => false
  }
}

///|
fn encode_varint_payload(
  typ : ScalarType,
  value : ProtoValue,
) -> EncodeFieldResult {
  match (typ, value) {
    (UInt32Type, UInt64Value(v)) | (UInt64Type, UInt64Value(v)) =>
      EncodedField(encode_varint_u64(v))
    (Int32Type, Int64Value(v)) | (Int64Type, Int64Value(v)) =>
      EncodedField(encode_varint_u64(v.reinterpret_as_uint64()))
    (SInt32Type, Int64Value(v)) | (SInt64Type, Int64Value(v)) =>
      EncodedField(encode_varint_u64(encode_zigzag_i64(v)))
    (BoolType, BoolValue(v)) => EncodedField(encode_varint_u64(bool_to_u64(v)))
    (EnumType(_), Int64Value(v)) =>
      EncodedField(encode_varint_u64(v.reinterpret_as_uint64()))
    _ => EncodeFieldErr(Unsupported("value does not match varint scalar type"))
  }
}

///|
fn encode_length_payload(
  typ : ScalarType,
  value : ProtoValue,
  descriptors : Array[MessageDescriptor],
) -> EncodeFieldResult {
  match (typ, value) {
    (StringType, StringValue(v)) => EncodedField(encode_string(v))
    (BytesType, BytesValue(v)) => EncodedField(encode_length_delimited(v))
    (NamedType(name), NestedMessageValue(v)) =>
      match find_message_descriptor(descriptors, name) {
        None =>
          EncodeFieldErr(
            Unsupported("missing descriptor for nested message: " + name),
          )
        Some(desc) =>
          match encode_message_with_descriptors(desc, descriptors, v) {
            EncodeMessageErr(e) => EncodeFieldErr(e)
            EncodeMessageOk(bytes) =>
              EncodedField(encode_length_delimited(bytes))
          }
      }
    (NamedType(name), _) =>
      EncodeFieldErr(
        Unsupported("value does not match nested message: " + name),
      )
    (MapType(key_typ, value_typ), MapEntryValue(entry)) => {
      let entry_desc = map_entry_descriptor(key_typ, value_typ)
      match encode_message_with_descriptors(entry_desc, descriptors, entry) {
        EncodeMessageErr(e) => EncodeFieldErr(e)
        EncodeMessageOk(bytes) => EncodedField(encode_length_delimited(bytes))
      }
    }
    (MapType(_, _), _) =>
      EncodeFieldErr(Unsupported("value does not match map entry type"))
    _ =>
      EncodeFieldErr(
        Unsupported("value does not match length-delimited scalar type"),
      )
  }
}

///|
fn encode_fixed32_payload(
  typ : ScalarType,
  value : ProtoValue,
) -> EncodeFieldResult {
  match (typ, value) {
    (Fixed32Type, UInt64Value(v)) => EncodedField(encode_fixed32(v.to_uint()))
    (SFixed32Type, Int64Value(v)) =>
      EncodedField(
        encode_fixed32((v.reinterpret_as_uint64() & 0xffffffffUL).to_uint()),
      )
    (FloatType, _) =>
      EncodeFieldErr(Unsupported("float encoding is not implemented"))
    _ => EncodeFieldErr(Unsupported("value does not match fixed32 scalar type"))
  }
}

///|
fn encode_fixed64_payload(
  typ : ScalarType,
  value : ProtoValue,
) -> EncodeFieldResult {
  match (typ, value) {
    (Fixed64Type, UInt64Value(v)) => EncodedField(encode_fixed64(v))
    (SFixed64Type, Int64Value(v)) =>
      EncodedField(encode_fixed64(v.reinterpret_as_uint64()))
    (DoubleType, _) =>
      EncodeFieldErr(Unsupported("double encoding is not implemented"))
    _ => EncodeFieldErr(Unsupported("value does not match fixed64 scalar type"))
  }
}

///|
fn encode_scalar_payload(
  typ : ScalarType,
  value : ProtoValue,
  descriptors : Array[MessageDescriptor],
) -> EncodeFieldResult {
  match typ.wire_type() {
    Varint => encode_varint_payload(typ, value)
    LengthDelimited => encode_length_payload(typ, value, descriptors)
    Fixed32 => encode_fixed32_payload(typ, value)
    Fixed64 => encode_fixed64_payload(typ, value)
    StartGroup | EndGroup =>
      EncodeFieldErr(Unsupported("groups are not supported"))
  }
}

///|
fn encode_scalar_field(
  desc : FieldDescriptor,
  value : ProtoValue,
  descriptors : Array[MessageDescriptor],
) -> EncodeFieldResult {
  let payload = encode_scalar_payload(desc.typ, value, descriptors)
  match payload {
    EncodedField(p) =>
      EncodedField(
        concat_bytes([encode_key(desc.number, desc.typ.wire_type()), p]),
      )
    EncodeFieldErr(e) => EncodeFieldErr(e)
  }
}

///|
fn encode_packed_repeated_field(
  desc : FieldDescriptor,
  values : Array[ProtoValue],
  descriptors : Array[MessageDescriptor],
) -> EncodeFieldResult {
  let payloads : Array[Bytes] = []
  for v in values {
    match encode_scalar_payload(desc.typ, v, descriptors) {
      EncodedField(bytes) => payloads.push(bytes)
      EncodeFieldErr(e) => return EncodeFieldErr(e)
    }
  }
  let payload = concat_bytes(payloads)
  EncodedField(
    concat_bytes([
      encode_key(desc.number, LengthDelimited),
      encode_length_delimited(payload),
    ]),
  )
}

///|
fn oneof_group(label : FieldLabel) -> String? {
  match label {
    Oneof(group) => Some(group)
    Singular | Optional | Repeated => None
  }
}

///|
fn message_field_in_oneof_group(
  desc : MessageDescriptor,
  field_name : String,
  group : String,
) -> Bool {
  match find_field_by_name(desc, field_name) {
    None => false
    Some(fd) =>
      match oneof_group(fd.label) {
        Some(g) => g == group
        None => false
      }
  }
}

///|
fn validate_message_fields(
  desc : MessageDescriptor,
  value : MessageValue,
) -> DecodeError? {
  let seen_oneofs : Array[String] = []
  for f in value.fields {
    if !has_field_name(desc, f.name) {
      return Some(Unsupported("unknown field: " + f.name))
    }
    match find_field_by_name(desc, f.name) {
      Some(fd) => {
        if fd.label != Repeated && f.values.length() > 1 {
          return Some(
            Unsupported("singular field has multiple values: " + f.name),
          )
        }
        match oneof_group(fd.label) {
          None => ()
          Some(group) =>
            if f.values.length() > 0 {
              for seen in seen_oneofs {
                if seen == group {
                  return Some(
                    Unsupported("multiple fields set for oneof group: " + group),
                  )
                }
              }
              seen_oneofs.push(group)
            }
        }
      }
      None => ()
    }
  }
  None
}

///| Encode a dynamic message according to a parsed/constructed descriptor.

///| Fields are emitted in the caller-provided order, which keeps generated

///|
/// golden-vector tests easy to read.
pub fn encode_message(
  desc : MessageDescriptor,
  value : MessageValue,
) -> EncodeMessageResult {
  encode_message_with_descriptors(desc, [], value)
}

///|
/// Encode a dynamic message, resolving `NamedType` fields through
/// `descriptors` for message-valued nested fields.
pub fn encode_message_with_descriptors(
  desc : MessageDescriptor,
  descriptors : Array[MessageDescriptor],
  value : MessageValue,
) -> EncodeMessageResult {
  match validate_message_fields(desc, value) {
    Some(e) => return EncodeMessageErr(e)
    None => ()
  }
  let parts : Array[Bytes] = []
  for f in value.fields {
    match find_field_by_name(desc, f.name) {
      Some(fd) =>
        if fd.label == Repeated &&
          is_packable_scalar(fd.typ) &&
          f.values.length() > 0 {
          match encode_packed_repeated_field(fd, f.values, descriptors) {
            EncodedField(bytes) => parts.push(bytes)
            EncodeFieldErr(e) => return EncodeMessageErr(e)
          }
        } else {
          for v in f.values {
            match encode_scalar_field(fd, v, descriptors) {
              EncodedField(bytes) => parts.push(bytes)
              EncodeFieldErr(e) => return EncodeMessageErr(e)
            }
          }
        }
      None => return EncodeMessageErr(Unsupported("unknown field: " + f.name))
    }
  }
  EncodeMessageOk(concat_bytes(parts))
}

///|
fn decode_scalar_payload(
  typ : ScalarType,
  input : Bytes,
  offset : Int,
  descriptors : Array[MessageDescriptor],
) -> DecodeScalarResult {
  match typ.wire_type() {
    Varint =>
      match decode_varint_u64(input, offset~) {
        U64Err(e) => DecodeScalarErr(e)
        U64Ok(raw, next) =>
          match typ {
            UInt32Type | UInt64Type => DecodedScalar(UInt64Value(raw), next)
            Int32Type | Int64Type =>
              DecodedScalar(Int64Value(raw.reinterpret_as_int64()), next)
            SInt32Type | SInt64Type =>
              DecodedScalar(Int64Value(decode_zigzag_i64(raw)), next)
            BoolType => DecodedScalar(BoolValue(raw != 0UL), next)
            EnumType(_) =>
              DecodedScalar(Int64Value(raw.reinterpret_as_int64()), next)
            _ => DecodeScalarErr(Unsupported("unsupported varint scalar"))
          }
      }
    LengthDelimited =>
      match typ {
        StringType =>
          match decode_string_lossy(input, offset~) {
            StringErr(e) => DecodeScalarErr(e)
            StringOk(s, next) => DecodedScalar(StringValue(s), next)
          }
        BytesType =>
          match decode_length_delimited(input, offset~) {
            BytesErr(e) => DecodeScalarErr(e)
            BytesOk(b, next) => DecodedScalar(BytesValue(b), next)
          }
        NamedType(name) =>
          match decode_length_delimited(input, offset~) {
            BytesErr(e) => DecodeScalarErr(e)
            BytesOk(payload, next) =>
              match find_message_descriptor(descriptors, name) {
                None =>
                  DecodeScalarErr(
                    Unsupported(
                      "missing descriptor for nested message: " + name,
                    ),
                  )
                Some(desc) =>
                  match
                    decode_message_with_descriptors(desc, descriptors, payload) {
                    DecodeMessageErr(e) => DecodeScalarErr(e)
                    DecodeMessageOk(message, payload_next) =>
                      if payload_next != payload.length() {
                        DecodeScalarErr(
                          Unsupported("nested decoder left trailing bytes"),
                        )
                      } else {
                        DecodedScalar(NestedMessageValue(message), next)
                      }
                  }
              }
          }
        MapType(key_typ, value_typ) =>
          match decode_length_delimited(input, offset~) {
            BytesErr(e) => DecodeScalarErr(e)
            BytesOk(payload, next) => {
              let entry_desc = map_entry_descriptor(key_typ, value_typ)
              match
                decode_message_with_descriptors(
                  entry_desc, descriptors, payload,
                ) {
                DecodeMessageErr(e) => DecodeScalarErr(e)
                DecodeMessageOk(entry, payload_next) =>
                  if payload_next != payload.length() {
                    DecodeScalarErr(
                      Unsupported("map entry decoder left trailing bytes"),
                    )
                  } else {
                    DecodedScalar(MapEntryValue(entry), next)
                  }
              }
            }
          }
        _ => DecodeScalarErr(Unsupported("unsupported length-delimited scalar"))
      }
    Fixed32 =>
      match decode_fixed32(input, offset~) {
        U32Err(e) => DecodeScalarErr(e)
        U32Ok(raw, next) =>
          match typ {
            Fixed32Type => DecodedScalar(UInt64Value(raw.to_uint64()), next)
            SFixed32Type =>
              DecodedScalar(
                Int64Value(raw.reinterpret_as_int().to_int64()),
                next,
              )
            FloatType =>
              DecodeScalarErr(Unsupported("float decoding is not implemented"))
            _ => DecodeScalarErr(Unsupported("unsupported fixed32 scalar"))
          }
      }
    Fixed64 =>
      match decode_fixed64(input, offset~) {
        U64FixedErr(e) => DecodeScalarErr(e)
        U64FixedOk(raw, next) =>
          match typ {
            Fixed64Type => DecodedScalar(UInt64Value(raw), next)
            SFixed64Type =>
              DecodedScalar(Int64Value(raw.reinterpret_as_int64()), next)
            DoubleType =>
              DecodeScalarErr(Unsupported("double decoding is not implemented"))
            _ => DecodeScalarErr(Unsupported("unsupported fixed64 scalar"))
          }
      }
    StartGroup | EndGroup =>
      DecodeScalarErr(Unsupported("groups are not supported"))
  }
}

///|
fn decode_packed_payload(
  typ : ScalarType,
  input : Bytes,
  offset : Int,
  descriptors : Array[MessageDescriptor],
) -> DecodePackedResult {
  match decode_length_delimited(input, offset~) {
    BytesErr(e) => DecodePackedErr(e)
    BytesOk(payload, next) => {
      let values : Array[ProtoValue] = []
      let mut i = 0
      while i < payload.length() {
        match decode_scalar_payload(typ, payload, i, descriptors) {
          DecodeScalarErr(e) => return DecodePackedErr(e)
          DecodedScalar(value, after_value) => {
            if after_value <= i {
              return DecodePackedErr(
                Unsupported("packed field decoder did not advance"),
              )
            }
            values.push(value)
            i = after_value
          }
        }
      }
      DecodedPacked(values, next)
    }
  }
}

///|
fn skip_unknown_field(
  input : Bytes,
  offset : Int,
  wire : WireType,
) -> SkipResult {
  match wire {
    Varint =>
      match decode_varint_u64(input, offset~) {
        U64Ok(_, next) => SkipOk(next)
        U64Err(e) => SkipErr(e)
      }
    LengthDelimited =>
      match decode_length_delimited(input, offset~) {
        BytesOk(_, next) => SkipOk(next)
        BytesErr(e) => SkipErr(e)
      }
    Fixed32 => {
      let next = offset + 4
      if offset < 0 || next > input.length() {
        SkipErr(UnexpectedEof)
      } else {
        SkipOk(next)
      }
    }
    Fixed64 => {
      let next = offset + 8
      if offset < 0 || next > input.length() {
        SkipErr(UnexpectedEof)
      } else {
        SkipOk(next)
      }
    }
    StartGroup | EndGroup => SkipErr(Unsupported("groups are not supported"))
  }
}

///|
fn add_decoded_field(
  fields : Array[MessageField],
  message_desc : MessageDescriptor,
  desc : FieldDescriptor,
  value : ProtoValue,
) -> Unit {
  match oneof_group(desc.label) {
    None => ()
    Some(group) => {
      let mut i = 0
      while i < fields.length() {
        if fields[i].name != desc.name &&
          message_field_in_oneof_group(message_desc, fields[i].name, group) {
          let _ = fields.remove(i)
        } else {
          i = i + 1
        }
      }
    }
  }
  for i = 0; i < fields.length(); i = i + 1 {
    if fields[i].name == desc.name {
      if desc.label == Repeated {
        let values = fields[i].values
        values.push(value)
      } else {
        fields[i] = MessageField::{ name: desc.name, values: [value] }
      }
      return
    }
  }
  fields.push(MessageField::{ name: desc.name, values: [value] })
}

///| Decode all fields from `input[offset:]`, skipping unknown fields as the

///| protobuf binary format requires. Repeated occurrences are accumulated in

///| a single `MessageField` when the descriptor label is `Repeated`; duplicate

///|
/// singular fields keep the last value.
pub fn decode_message(
  desc : MessageDescriptor,
  input : Bytes,
  offset? : Int = 0,
) -> DecodeMessageResult {
  decode_message_with_descriptors(desc, [], input, offset~)
}

///|
/// Decode a dynamic message, resolving `NamedType` fields through
/// `descriptors` for message-valued nested fields.
pub fn decode_message_with_descriptors(
  desc : MessageDescriptor,
  descriptors : Array[MessageDescriptor],
  input : Bytes,
  offset? : Int = 0,
) -> DecodeMessageResult {
  if offset < 0 || offset > input.length() {
    return DecodeMessageErr(UnexpectedEof)
  }
  let decoded : Array[MessageField] = []
  let mut i = offset
  while i < input.length() {
    match decode_varint_u64(input, offset=i) {
      U64Err(e) => return DecodeMessageErr(e)
      U64Ok(raw_key, after_key) =>
        match parse_key(raw_key) {
          KeyErr(e) => return DecodeMessageErr(e)
          KeyOk(number, wire) =>
            match find_field_by_number(desc, number) {
              None =>
                match skip_unknown_field(input, after_key, wire) {
                  SkipErr(e) => return DecodeMessageErr(e)
                  SkipOk(next) => i = next
                }
              Some(fd) =>
                if fd.label == Repeated &&
                  is_packable_scalar(fd.typ) &&
                  wire == LengthDelimited {
                  match
                    decode_packed_payload(fd.typ, input, after_key, descriptors) {
                    DecodePackedErr(e) => return DecodeMessageErr(e)
                    DecodedPacked(values, next) => {
                      for value in values {
                        add_decoded_field(decoded, desc, fd, value)
                      }
                      i = next
                    }
                  }
                } else if fd.typ.wire_type() != wire {
                  return DecodeMessageErr(
                    Unsupported("wire type mismatch for field: " + fd.name),
                  )
                } else {
                  match
                    decode_scalar_payload(fd.typ, input, after_key, descriptors) {
                    DecodeScalarErr(e) => return DecodeMessageErr(e)
                    DecodedScalar(value, next) => {
                      add_decoded_field(decoded, desc, fd, value)
                      i = next
                    }
                  }
                }
            }
        }
    }
  }
  DecodeMessageOk(MessageValue::{ fields: decoded }, i)
}
