///|
/// Result of converting a dynamic message to protobuf-style JSON.
pub(all) enum JsonEncodeResult {
  JsonOk(String)
  JsonErr(DecodeError)
} derive(Debug, Eq)

///|
fn json_join(parts : Array[String], sep : String) -> String {
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + sep
    }
    out = out + parts[i]
  }
  out
}

///|
fn json_hex_digit(n : Int) -> String {
  match n {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    _ => "f"
  }
}

///|
fn json_unicode_escape(code : Int) -> String {
  "\\u" +
  json_hex_digit((code >> 12) & 15) +
  json_hex_digit((code >> 8) & 15) +
  json_hex_digit((code >> 4) & 15) +
  json_hex_digit(code & 15)
}

///|
/// Escape a MoonBit string as a JSON string literal.
pub fn json_escape_string(value : String) -> String {
  let mut out = "\""
  for c in value.to_array() {
    if c == '"' {
      out = out + "\\\""
    } else if c == '\\' {
      out = out + "\\\\"
    } else if c == '\n' {
      out = out + "\\n"
    } else if c == '\r' {
      out = out + "\\r"
    } else if c == '\t' {
      out = out + "\\t"
    } else if c.to_int() < 32 {
      out = out + json_unicode_escape(c.to_int())
    } else {
      out = out + c.to_string()
    }
  }
  out + "\""
}

///|
fn base64_char(index : Int) -> String {
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[index:index +
  1].to_owned()
}

///|
/// Encode bytes with the standard base64 alphabet used by protobuf JSON.
pub fn base64_encode(input : Bytes) -> String {
  let bytes = input.to_array()
  let mut out = ""
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i].to_uint().reinterpret_as_int()
    let b1 = if i + 1 < bytes.length() {
      bytes[i + 1].to_uint().reinterpret_as_int()
    } else {
      0
    }
    let b2 = if i + 2 < bytes.length() {
      bytes[i + 2].to_uint().reinterpret_as_int()
    } else {
      0
    }
    let triple = (b0 << 16) | (b1 << 8) | b2
    out = out + base64_char((triple >> 18) & 63)
    out = out + base64_char((triple >> 12) & 63)
    if i + 1 < bytes.length() {
      out = out + base64_char((triple >> 6) & 63)
    } else {
      out = out + "="
    }
    if i + 2 < bytes.length() {
      out = out + base64_char(triple & 63)
    } else {
      out = out + "="
    }
    i = i + 3
  }
  out
}

///|
fn is_i64_json_string_type(typ : ScalarType) -> Bool {
  match typ {
    Int64Type | UInt64Type | SInt64Type | Fixed64Type | SFixed64Type => true
    _ => false
  }
}

///|
fn json_find_descriptor(
  desc : MessageDescriptor,
  name : String,
) -> FieldDescriptor? {
  for field in desc.fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}

///|
fn json_find_message_field(
  value : MessageValue,
  name : String,
) -> MessageField? {
  for field in value.fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}

///|
fn validate_json_message(
  desc : MessageDescriptor,
  value : MessageValue,
) -> DecodeError? {
  for field in value.fields {
    match json_find_descriptor(desc, field.name) {
      None =>
        return Some(Unsupported("unknown field in JSON mapping: " + field.name))
      Some(fd) =>
        if fd.label != Repeated && field.values.length() > 1 {
          return Some(
            Unsupported(
              "singular field has multiple JSON values: " + field.name,
            ),
          )
        }
    }
  }
  None
}

///|
fn scalar_to_json(typ : ScalarType, value : ProtoValue) -> JsonEncodeResult {
  match (typ, value) {
    (StringType, StringValue(v)) => JsonOk(json_escape_string(v))
    (BytesType, BytesValue(v)) => JsonOk(json_escape_string(base64_encode(v)))
    (BoolType, BoolValue(v)) => JsonOk(if v { "true" } else { "false" })
    (UInt32Type | UInt64Type | Fixed32Type | Fixed64Type, UInt64Value(v)) =>
      if is_i64_json_string_type(typ) {
        JsonOk(json_escape_string(v.to_string()))
      } else {
        JsonOk(v.to_string())
      }
    (
      Int32Type
      | Int64Type
      | SInt32Type
      | SInt64Type
      | SFixed32Type
      | SFixed64Type,
      Int64Value(v),
    ) =>
      if is_i64_json_string_type(typ) {
        JsonOk(json_escape_string(v.to_string()))
      } else {
        JsonOk(v.to_string())
      }
    (NamedType(name), _) =>
      JsonErr(Unsupported("nested message JSON is not implemented: " + name))
    (FloatType | DoubleType, _) =>
      JsonErr(Unsupported("float/double JSON is not implemented"))
    _ => JsonErr(Unsupported("value does not match JSON scalar type"))
  }
}

///|
fn field_to_json(
  desc : FieldDescriptor,
  field : MessageField,
) -> JsonEncodeResult {
  if desc.label == Repeated {
    let items : Array[String] = []
    for value in field.values {
      match scalar_to_json(desc.typ, value) {
        JsonErr(e) => return JsonErr(e)
        JsonOk(item) => items.push(item)
      }
    }
    JsonOk("[" + json_join(items, ",") + "]")
  } else if field.values.length() == 0 {
    JsonErr(Unsupported("singular field has no JSON value: " + field.name))
  } else {
    scalar_to_json(desc.typ, field.values[0])
  }
}

///|
/// Convert a dynamic message to deterministic protobuf-style JSON. Known
/// fields are emitted in descriptor order; absent fields are omitted.
pub fn message_to_json(
  desc : MessageDescriptor,
  value : MessageValue,
) -> JsonEncodeResult {
  match validate_json_message(desc, value) {
    Some(e) => return JsonErr(e)
    None => ()
  }
  let props : Array[String] = []
  for fd in desc.fields {
    match json_find_message_field(value, fd.name) {
      None => ()
      Some(field) =>
        match field_to_json(fd, field) {
          JsonErr(e) => return JsonErr(e)
          JsonOk(encoded) =>
            props.push(json_escape_string(fd.name) + ":" + encoded)
        }
    }
  }
  JsonOk("{" + json_join(props, ",") + "}")
}
