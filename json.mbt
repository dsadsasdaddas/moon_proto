///|
/// Result of converting a dynamic message to protobuf-style JSON.
pub(all) enum JsonEncodeResult {
  JsonOk(String)
  JsonErr(DecodeError)
} derive(Debug, Eq)

///|
/// Result of parsing protobuf-style JSON into a dynamic message.
pub(all) enum JsonDecodeResult {
  JsonDecodeOk(MessageValue)
  JsonDecodeErr(DecodeError)
} derive(Debug, Eq)

///|
priv enum JsonStringResult {
  JsonStringOk(String)
  JsonStringErr(DecodeError)
}

///|
priv enum JsonScalarDecodeResult {
  JsonScalarOk(ProtoValue)
  JsonScalarErr(DecodeError)
}

///|
priv struct JsonParser {
  src : String
  chars : Array[Char]
  mut i : Int
}

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
fn base64_value(c : Char) -> Int {
  if c >= 'A' && c <= 'Z' {
    c.to_int() - 'A'.to_int()
  } else if c >= 'a' && c <= 'z' {
    c.to_int() - 'a'.to_int() + 26
  } else if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int() + 52
  } else if c == '+' {
    62
  } else if c == '/' {
    63
  } else {
    -1
  }
}

///|
/// Decode standard base64 used by protobuf JSON bytes fields.
pub fn base64_decode(input : String) -> DecodeBytesResult {
  let chars = input.to_array()
  if chars.length() == 0 {
    return BytesOk(b"", 0)
  }
  if chars.length() % 4 != 0 {
    return BytesErr(Unsupported("invalid base64 length"))
  }
  let out : Array[Byte] = []
  let mut i = 0
  while i < chars.length() {
    let c0 = chars[i]
    let c1 = chars[i + 1]
    let c2 = chars[i + 2]
    let c3 = chars[i + 3]
    let v0 = base64_value(c0)
    let v1 = base64_value(c1)
    let pad2 = c2 == '='
    let pad3 = c3 == '='
    if v0 < 0 || v1 < 0 {
      return BytesErr(Unsupported("invalid base64 alphabet"))
    }
    if pad2 && !pad3 {
      return BytesErr(Unsupported("invalid base64 padding"))
    }
    let v2 = if pad2 { 0 } else { base64_value(c2) }
    let v3 = if pad3 { 0 } else { base64_value(c3) }
    if v2 < 0 || v3 < 0 {
      return BytesErr(Unsupported("invalid base64 alphabet"))
    }
    let triple = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
    out.push(((triple >> 16) & 255).reinterpret_as_uint().to_byte())
    if !pad2 {
      out.push(((triple >> 8) & 255).reinterpret_as_uint().to_byte())
    }
    if !pad3 {
      out.push((triple & 255).reinterpret_as_uint().to_byte())
    }
    if (pad2 || pad3) && i + 4 < chars.length() {
      return BytesErr(Unsupported("base64 padding must be final"))
    }
    i = i + 4
  }
  BytesOk(Bytes::from_array(out), chars.length())
}

///|
fn is_i64_json_string_type(typ : ScalarType) -> Bool {
  match typ {
    Int64Type | UInt64Type | SInt64Type | Fixed64Type | SFixed64Type => true
    _ => false
  }
}

///|
fn json_upper_ascii(c : Char) -> Char {
  match c {
    'a' => 'A'
    'b' => 'B'
    'c' => 'C'
    'd' => 'D'
    'e' => 'E'
    'f' => 'F'
    'g' => 'G'
    'h' => 'H'
    'i' => 'I'
    'j' => 'J'
    'k' => 'K'
    'l' => 'L'
    'm' => 'M'
    'n' => 'N'
    'o' => 'O'
    'p' => 'P'
    'q' => 'Q'
    'r' => 'R'
    's' => 'S'
    't' => 'T'
    'u' => 'U'
    'v' => 'V'
    'w' => 'W'
    'x' => 'X'
    'y' => 'Y'
    'z' => 'Z'
    other => other
  }
}

///|
fn json_lower_camel_field_name(name : String) -> String {
  let chars = name.to_array()
  let out : Array[Char] = []
  let mut capitalize_next = false
  for c in chars {
    if c == '_' {
      capitalize_next = true
    } else if capitalize_next {
      out.push(json_upper_ascii(c))
      capitalize_next = false
    } else {
      out.push(c)
    }
  }
  String::from_iter(out.iter())
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
  for field in desc.fields {
    if json_lower_camel_field_name(field.name) == name {
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
fn json_find_message_descriptor(
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
fn json_oneof_group(label : FieldLabel) -> String? {
  match label {
    Oneof(group) => Some(group)
    Singular | Optional | Repeated => None
  }
}

///|
fn validate_json_message(
  desc : MessageDescriptor,
  value : MessageValue,
) -> DecodeError? {
  let seen_oneofs : Array[String] = []
  for field in value.fields {
    match json_find_descriptor(desc, field.name) {
      None =>
        return Some(Unsupported("unknown field in JSON mapping: " + field.name))
      Some(fd) => {
        if fd.label != Repeated && field.values.length() > 1 {
          return Some(
            Unsupported(
              "singular field has multiple JSON values: " + field.name,
            ),
          )
        }
        match json_oneof_group(fd.label) {
          None => ()
          Some(group) =>
            if field.values.length() > 0 {
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
    }
  }
  None
}

///|
fn json_find_entry_field(entry : MessageValue, name : String) -> ProtoValue? {
  for field in entry.fields {
    if field.name == name && field.values.length() > 0 {
      return Some(field.values[0])
    }
  }
  None
}

///|
fn map_key_to_json_property(
  typ : ScalarType,
  value : ProtoValue,
) -> JsonEncodeResult {
  match (typ, value) {
    (StringType, StringValue(v)) => JsonOk(v)
    (BoolType, BoolValue(v)) => JsonOk(if v { "true" } else { "false" })
    (UInt32Type | Fixed32Type, UInt64Value(v)) =>
      if v <= 0xffffffffUL {
        JsonOk(v.to_string())
      } else {
        JsonErr(Unsupported("uint32 map key out of range"))
      }
    (UInt64Type | Fixed64Type, UInt64Value(v)) =>
      JsonOk(v.to_string())
    (
      Int32Type
      | SInt32Type
      | SFixed32Type,
      Int64Value(v),
    ) =>
      if v >= (-2147483647L - 1L) && v <= 2147483647L {
        JsonOk(v.to_string())
      } else {
        JsonErr(Unsupported("int32 map key out of range"))
      }
    (Int64Type | SInt64Type | SFixed64Type, Int64Value(v)) =>
      JsonOk(v.to_string())
    _ => JsonErr(Unsupported("value does not match map key type"))
  }
}

///|
fn map_field_to_json(
  desc : FieldDescriptor,
  field : MessageField,
  descriptors : Array[MessageDescriptor],
  lower_camel : Bool,
) -> JsonEncodeResult {
  match desc.typ {
    MapType(key_typ, value_typ) => {
      let props : Array[String] = []
      for item in field.values {
        match item {
          MapEntryValue(entry) => {
            let key = match json_find_entry_field(entry, "key") {
              None => return JsonErr(Unsupported("map entry missing key"))
              Some(k) => k
            }
            let value = match json_find_entry_field(entry, "value") {
              None => return JsonErr(Unsupported("map entry missing value"))
              Some(v) => v
            }
            let key_text = match map_key_to_json_property(key_typ, key) {
              JsonErr(e) => return JsonErr(e)
              JsonOk(text) => text
            }
            let value_text = match
              scalar_to_json_with_options(
                value_typ, value, descriptors, lower_camel,
              ) {
              JsonErr(e) => return JsonErr(e)
              JsonOk(text) => text
            }
            props.push(json_escape_string(key_text) + ":" + value_text)
          }
          _ =>
            return JsonErr(Unsupported("value does not match map entry type"))
        }
      }
      JsonOk("{" + json_join(props, ",") + "}")
    }
    _ => JsonErr(Unsupported("field is not a map"))
  }
}

///|
fn scalar_to_json(typ : ScalarType, value : ProtoValue) -> JsonEncodeResult {
  match (typ, value) {
    (StringType, StringValue(v)) => JsonOk(json_escape_string(v))
    (BytesType, BytesValue(v)) => JsonOk(json_escape_string(base64_encode(v)))
    (BoolType, BoolValue(v)) => JsonOk(if v { "true" } else { "false" })
    (EnumType(_), Int64Value(v)) => JsonOk(v.to_string())
    (UInt32Type | Fixed32Type, UInt64Value(v)) =>
      if v > 0xffffffffUL {
        JsonErr(Unsupported("uint32 value out of range"))
      } else {
        JsonOk(v.to_string())
      }
    (UInt64Type | Fixed64Type, UInt64Value(v)) =>
      if is_i64_json_string_type(typ) {
        JsonOk(json_escape_string(v.to_string()))
      } else {
        JsonOk(v.to_string())
      }
    (
      Int32Type
      | SInt32Type
      | SFixed32Type,
      Int64Value(v),
    ) =>
      if v < (-2147483647L - 1L) || v > 2147483647L {
        JsonErr(Unsupported("int32 value out of range"))
      } else {
        JsonOk(v.to_string())
      }
    (
      Int64Type
      | SInt64Type
      | SFixed64Type,
      Int64Value(v),
    ) =>
      if is_i64_json_string_type(typ) {
        JsonOk(json_escape_string(v.to_string()))
      } else {
        JsonOk(v.to_string())
      }
    (FloatType, FloatValue(v)) => JsonOk(float_double_to_json(v.to_double()))
    (DoubleType, DoubleValue(v)) => JsonOk(float_double_to_json(v))
    (NamedType(name), NestedMessageValue(_)) =>
      JsonErr(Unsupported("missing descriptor for nested message: " + name))
    (NamedType(name), _) =>
      JsonErr(Unsupported("value does not match nested message: " + name))
    (MapType(_, _), _) =>
      JsonErr(Unsupported("map value must be encoded as a JSON object"))
    (FloatType, _) => JsonErr(Unsupported("value does not match float type"))
    (DoubleType, _) => JsonErr(Unsupported("value does not match double type"))
    _ => JsonErr(Unsupported("value does not match JSON scalar type"))
  }
}

///|
fn float_double_to_json(v : Double) -> String {
  if v.is_nan() {
    json_escape_string("NaN")
  } else if v.is_pos_inf() {
    json_escape_string("Infinity")
  } else if v.is_neg_inf() {
    json_escape_string("-Infinity")
  } else {
    v.to_string()
  }
}

///|
fn field_to_json(
  desc : FieldDescriptor,
  field : MessageField,
  descriptors : Array[MessageDescriptor],
  lower_camel : Bool,
) -> JsonEncodeResult {
  match desc.typ {
    MapType(_, _) =>
      return map_field_to_json(desc, field, descriptors, lower_camel)
    _ => ()
  }
  if desc.label == Repeated {
    let items : Array[String] = []
    for value in field.values {
      match scalar_to_json_with_options(
        desc.typ, value, descriptors, lower_camel,
      ) {
        JsonErr(e) => return JsonErr(e)
        JsonOk(item) => items.push(item)
      }
    }
    JsonOk("[" + json_join(items, ",") + "]")
  } else if field.values.length() == 0 {
    JsonErr(Unsupported("singular field has no JSON value: " + field.name))
  } else {
    scalar_to_json_with_options(
      desc.typ, field.values[0], descriptors, lower_camel,
    )
  }
}

///|
fn scalar_to_json_with_options(
  typ : ScalarType,
  value : ProtoValue,
  descriptors : Array[MessageDescriptor],
  lower_camel : Bool,
) -> JsonEncodeResult {
  match (typ, value) {
    (NamedType(name), NestedMessageValue(v)) =>
      match json_find_message_descriptor(descriptors, name) {
        None =>
          JsonErr(Unsupported("missing descriptor for nested message: " + name))
        Some(desc) =>
          message_to_json_with_options(desc, descriptors, v, lower_camel)
      }
    _ => scalar_to_json(typ, value)
  }
}

///|
fn json_output_field_name(field : FieldDescriptor, lower_camel : Bool) -> String {
  if lower_camel {
    json_lower_camel_field_name(field.name)
  } else {
    field.name
  }
}

///|
/// Convert a dynamic message to deterministic protobuf-style JSON. Known
/// fields are emitted in descriptor order; absent fields are omitted.
pub fn message_to_json(
  desc : MessageDescriptor,
  value : MessageValue,
) -> JsonEncodeResult {
  message_to_json_with_descriptors(desc, [], value)
}

///|
/// Convert a dynamic message to deterministic protobuf-style JSON using
/// lowerCamelCase JSON field names, matching the protobuf JSON default.
pub fn message_to_json_lower_camel(
  desc : MessageDescriptor,
  value : MessageValue,
) -> JsonEncodeResult {
  message_to_json_lower_camel_with_descriptors(desc, [], value)
}

///|
/// Convert a dynamic message to deterministic protobuf-style JSON, resolving
/// `NamedType` fields through `descriptors` for nested message values.
pub fn message_to_json_with_descriptors(
  desc : MessageDescriptor,
  descriptors : Array[MessageDescriptor],
  value : MessageValue,
) -> JsonEncodeResult {
  message_to_json_with_options(desc, descriptors, value, false)
}

///|
/// Convert protobuf-style JSON with lowerCamelCase field names while resolving
/// `NamedType` fields through `descriptors`.
pub fn message_to_json_lower_camel_with_descriptors(
  desc : MessageDescriptor,
  descriptors : Array[MessageDescriptor],
  value : MessageValue,
) -> JsonEncodeResult {
  message_to_json_with_options(desc, descriptors, value, true)
}

///|
fn message_to_json_with_options(
  desc : MessageDescriptor,
  descriptors : Array[MessageDescriptor],
  value : MessageValue,
  lower_camel : Bool,
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
        match field_to_json(fd, field, descriptors, lower_camel) {
          JsonErr(e) => return JsonErr(e)
          JsonOk(encoded) =>
            props.push(
              json_escape_string(json_output_field_name(fd, lower_camel)) +
              ":" +
              encoded,
            )
        }
    }
  }
  JsonOk("{" + json_join(props, ",") + "}")
}

///|
fn JsonParser::skip_ws(self : JsonParser) -> Unit {
  while self.i < self.chars.length() {
    let c = self.chars[self.i]
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      self.i = self.i + 1
    } else {
      return
    }
  }
}

///|
fn JsonParser::peek(self : JsonParser) -> Char? {
  if self.i < self.chars.length() {
    Some(self.chars[self.i])
  } else {
    None
  }
}

///|
fn JsonParser::consume(self : JsonParser, wanted : Char) -> Bool {
  self.skip_ws()
  match self.peek() {
    Some(c) =>
      if c == wanted {
        self.i = self.i + 1
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn JsonParser::consume_literal(self : JsonParser, wanted : String) -> Bool {
  self.skip_ws()
  let chars = wanted.to_array()
  if self.i + chars.length() > self.chars.length() {
    return false
  }
  for j = 0; j < chars.length(); j = j + 1 {
    if self.chars[self.i + j] != chars[j] {
      return false
    }
  }
  self.i = self.i + chars.length()
  true
}

///|
fn JsonParser::parse_string(self : JsonParser) -> JsonStringResult {
  self.skip_ws()
  if self.i >= self.chars.length() || self.chars[self.i] != '"' {
    return JsonStringErr(Unsupported("expected JSON string"))
  }
  self.i = self.i + 1
  let out : Array[Char] = []
  while self.i < self.chars.length() {
    let c = self.chars[self.i]
    self.i = self.i + 1
    if c == '"' {
      return JsonStringOk(String::from_iter(out.iter()))
    } else if c == '\\' {
      if self.i >= self.chars.length() {
        return JsonStringErr(UnexpectedEof)
      }
      let e = self.chars[self.i]
      self.i = self.i + 1
      if e == '"' {
        out.push('"')
      } else if e == '\\' {
        out.push('\\')
      } else if e == '/' {
        out.push('/')
      } else if e == 'n' {
        out.push('\n')
      } else if e == 'r' {
        out.push('\r')
      } else if e == 't' {
        out.push('\t')
      } else {
        return JsonStringErr(Unsupported("unsupported JSON escape"))
      }
    } else {
      out.push(c)
    }
  }
  JsonStringErr(UnexpectedEof)
}

///|
fn is_json_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_json_number_char(c : Char) -> Bool {
  is_json_digit(c) || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E'
}

///|
fn JsonParser::parse_number_token(self : JsonParser) -> JsonStringResult {
  self.skip_ws()
  let start = self.i
  let mut saw_digit = false
  while self.i < self.chars.length() &&
    is_json_number_char(self.chars[self.i]) {
    if is_json_digit(self.chars[self.i]) {
      saw_digit = true
    }
    self.i = self.i + 1
  }
  if !saw_digit || self.i == start {
    return JsonStringErr(Unsupported("expected JSON number"))
  }
  JsonStringOk(self.src[start:self.i].to_owned())
}

///|
fn JsonParser::parse_number_or_string_token(
  self : JsonParser,
) -> JsonStringResult {
  self.skip_ws()
  match self.peek() {
    Some('"') => self.parse_string()
    _ => self.parse_number_token()
  }
}

///|
fn parse_u64_digits(text : String) -> UInt64? {
  let chars = text.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut value = 0UL
  for c in chars {
    if !is_json_digit(c) {
      return None
    }
    value = value * 10UL + (c.to_int() - '0'.to_int()).to_uint64()
  }
  Some(value)
}

///|
fn parse_i64_digits(text : String) -> Int64? {
  let chars = text.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    i = 1
  }
  if i >= chars.length() {
    return None
  }
  let mut value = 0L
  while i < chars.length() {
    let c = chars[i]
    if !is_json_digit(c) {
      return None
    }
    value = value * 10L + (c.to_int() - '0'.to_int()).to_int64()
    i = i + 1
  }
  if negative {
    Some(-value)
  } else {
    Some(value)
  }
}

///|
fn parse_json_double_value(text : String) -> Double? {
  match text {
    "NaN" => Some(0x7FF8000000000001UL.reinterpret_as_double())
    "Infinity" => Some(0x7FF0000000000000UL.reinterpret_as_double())
    "-Infinity" => Some(0xFFF0000000000000UL.reinterpret_as_double())
    _ =>
      try @string.parse_double(text) catch {
        _ => None
      } noraise {
        v => Some(v)
      }
  }
}

///|
fn parse_scalar_from_json(
  parser : JsonParser,
  typ : ScalarType,
  descriptors : Array[MessageDescriptor],
) -> JsonScalarDecodeResult {
  match typ {
    StringType =>
      match parser.parse_string() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(v) => JsonScalarOk(StringValue(v))
      }
    BytesType =>
      match parser.parse_string() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match base64_decode(text) {
            BytesErr(e) => JsonScalarErr(e)
            BytesOk(bytes, _) => JsonScalarOk(BytesValue(bytes))
          }
      }
    BoolType =>
      if parser.consume_literal("true") {
        JsonScalarOk(BoolValue(true))
      } else if parser.consume_literal("false") {
        JsonScalarOk(BoolValue(false))
      } else {
        JsonScalarErr(Unsupported("expected JSON bool"))
      }
    UInt32Type | Fixed32Type =>
      match parser.parse_number_or_string_token() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match parse_u64_digits(text) {
            Some(v) =>
              if v <= 0xffffffffUL {
                JsonScalarOk(UInt64Value(v))
              } else {
                JsonScalarErr(Unsupported("uint32 JSON out of range"))
              }
            None => JsonScalarErr(Unsupported("invalid unsigned integer JSON"))
          }
      }
    UInt64Type | Fixed64Type =>
      match parser.parse_number_or_string_token() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match parse_u64_digits(text) {
            Some(v) => JsonScalarOk(UInt64Value(v))
            None => JsonScalarErr(Unsupported("invalid unsigned integer JSON"))
          }
      }
    Int32Type | SInt32Type | SFixed32Type =>
      match parser.parse_number_or_string_token() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match parse_i64_digits(text) {
            Some(v) =>
              if v >= (-2147483647L - 1L) && v <= 2147483647L {
                JsonScalarOk(Int64Value(v))
              } else {
                JsonScalarErr(Unsupported("int32 JSON out of range"))
              }
            None => JsonScalarErr(Unsupported("invalid signed integer JSON"))
          }
      }
    Int64Type | SInt64Type | SFixed64Type =>
      match parser.parse_number_or_string_token() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match parse_i64_digits(text) {
            Some(v) => JsonScalarOk(Int64Value(v))
            None => JsonScalarErr(Unsupported("invalid signed integer JSON"))
          }
      }
    EnumType(_) =>
      match parser.parse_number_or_string_token() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match parse_i64_digits(text) {
            Some(v) => JsonScalarOk(Int64Value(v))
            None => JsonScalarErr(Unsupported("invalid enum integer JSON"))
          }
      }
    FloatType =>
      match parser.parse_number_or_string_token() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match parse_json_double_value(text) {
            Some(v) => JsonScalarOk(FloatValue(Float::from_double(v)))
            None => JsonScalarErr(Unsupported("invalid float JSON"))
          }
      }
    DoubleType =>
      match parser.parse_number_or_string_token() {
        JsonStringErr(e) => JsonScalarErr(e)
        JsonStringOk(text) =>
          match parse_json_double_value(text) {
            Some(v) => JsonScalarOk(DoubleValue(v))
            None => JsonScalarErr(Unsupported("invalid double JSON"))
          }
      }
    NamedType(name) =>
      match json_find_message_descriptor(descriptors, name) {
        None =>
          JsonScalarErr(
            Unsupported("missing descriptor for nested message: " + name),
          )
        Some(desc) =>
          match parse_json_message_object(parser, desc, descriptors) {
            JsonDecodeErr(e) => JsonScalarErr(e)
            JsonDecodeOk(message) => JsonScalarOk(NestedMessageValue(message))
          }
      }
    MapType(_, _) =>
      JsonScalarErr(Unsupported("map JSON value must be parsed as object"))
  }
}

///|
fn json_string_array_contains(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn parse_map_key_from_json_property(
  key_typ : ScalarType,
  key : String,
) -> JsonScalarDecodeResult {
  match key_typ {
    StringType => JsonScalarOk(StringValue(key))
    BoolType =>
      if key == "true" {
        JsonScalarOk(BoolValue(true))
      } else if key == "false" {
        JsonScalarOk(BoolValue(false))
      } else {
        JsonScalarErr(Unsupported("invalid bool map key JSON"))
      }
    UInt32Type | Fixed32Type =>
      match parse_u64_digits(key) {
        Some(v) =>
          if v <= 0xffffffffUL {
            JsonScalarOk(UInt64Value(v))
          } else {
            JsonScalarErr(Unsupported("uint32 map key JSON out of range"))
          }
        None => JsonScalarErr(Unsupported("invalid unsigned map key JSON"))
      }
    UInt64Type | Fixed64Type =>
      match parse_u64_digits(key) {
        Some(v) => JsonScalarOk(UInt64Value(v))
        None => JsonScalarErr(Unsupported("invalid unsigned map key JSON"))
      }
    Int32Type | SInt32Type | SFixed32Type =>
      match parse_i64_digits(key) {
        Some(v) =>
          if v >= (-2147483647L - 1L) && v <= 2147483647L {
            JsonScalarOk(Int64Value(v))
          } else {
            JsonScalarErr(Unsupported("int32 map key JSON out of range"))
          }
        None => JsonScalarErr(Unsupported("invalid signed map key JSON"))
      }
    Int64Type | SInt64Type | SFixed64Type =>
      match parse_i64_digits(key) {
        Some(v) => JsonScalarOk(Int64Value(v))
        None => JsonScalarErr(Unsupported("invalid signed map key JSON"))
      }
    _ => JsonScalarErr(Unsupported("unsupported map key JSON type"))
  }
}

///|
fn parse_json_map_field(
  parser : JsonParser,
  fd : FieldDescriptor,
  descriptors : Array[MessageDescriptor],
) -> JsonDecodeResult {
  match fd.typ {
    MapType(key_typ, value_typ) => {
      if !parser.consume('{') {
        return JsonDecodeErr(Unsupported("expected map JSON object"))
      }
      let values : Array[ProtoValue] = []
      let seen : Array[String] = []
      parser.skip_ws()
      if parser.consume('}') {
        return JsonDecodeOk(
          message_value([repeated_message_field(fd.name, values)]),
        )
      }
      let mut done = false
      while !done {
        let key_text = match parser.parse_string() {
          JsonStringErr(e) => return JsonDecodeErr(e)
          JsonStringOk(k) => k
        }
        if json_string_array_contains(seen, key_text) {
          return JsonDecodeErr(
            Unsupported("duplicate map JSON key: " + key_text),
          )
        }
        seen.push(key_text)
        if !parser.consume(':') {
          return JsonDecodeErr(Unsupported("expected map JSON colon"))
        }
        let key = match parse_map_key_from_json_property(key_typ, key_text) {
          JsonScalarErr(e) => return JsonDecodeErr(e)
          JsonScalarOk(v) => v
        }
        let value = match
          parse_scalar_from_json(parser, value_typ, descriptors) {
          JsonScalarErr(e) => return JsonDecodeErr(e)
          JsonScalarOk(v) => v
        }
        values.push(map_entry_value(key, value))
        parser.skip_ws()
        if parser.consume(',') {
          ()
        } else if parser.consume('}') {
          done = true
        } else {
          return JsonDecodeErr(Unsupported("expected comma or map object end"))
        }
      }
      JsonDecodeOk(message_value([repeated_message_field(fd.name, values)]))
    }
    _ => JsonDecodeErr(Unsupported("field is not a map"))
  }
}

///|
fn parse_json_field(
  parser : JsonParser,
  fd : FieldDescriptor,
  descriptors : Array[MessageDescriptor],
) -> JsonDecodeResult {
  if parser.consume_literal("null") {
    return JsonDecodeOk(message_value([]))
  }
  match fd.typ {
    MapType(_, _) => return parse_json_map_field(parser, fd, descriptors)
    _ => ()
  }
  if fd.label == Repeated {
    if !parser.consume('[') {
      return JsonDecodeErr(Unsupported("expected repeated JSON array"))
    }
    let values : Array[ProtoValue] = []
    parser.skip_ws()
    if parser.consume(']') {
      return JsonDecodeOk(
        message_value([repeated_message_field(fd.name, values)]),
      )
    }
    let mut done = false
    while !done {
      match parse_scalar_from_json(parser, fd.typ, descriptors) {
        JsonScalarErr(e) => return JsonDecodeErr(e)
        JsonScalarOk(value) => values.push(value)
      }
      parser.skip_ws()
      if parser.consume(',') {
        ()
      } else if parser.consume(']') {
        done = true
      } else {
        return JsonDecodeErr(Unsupported("expected comma or array end"))
      }
    }
    JsonDecodeOk(message_value([repeated_message_field(fd.name, values)]))
  } else {
    match parse_scalar_from_json(parser, fd.typ, descriptors) {
      JsonScalarErr(e) => JsonDecodeErr(e)
      JsonScalarOk(value) =>
        JsonDecodeOk(message_value([message_field(fd.name, value)]))
    }
  }
}

///|
fn append_json_field(
  fields : Array[MessageField],
  field : MessageField,
) -> Unit {
  fields.push(field)
}

///|
fn order_json_fields(
  desc : MessageDescriptor,
  parsed : Array[MessageField],
) -> Array[MessageField] {
  let ordered : Array[MessageField] = []
  for fd in desc.fields {
    for f in parsed {
      if f.name == fd.name {
        ordered.push(f)
      }
    }
  }
  ordered
}

///|
fn parse_json_message_object(
  parser : JsonParser,
  desc : MessageDescriptor,
  descriptors : Array[MessageDescriptor],
) -> JsonDecodeResult {
  if !parser.consume('{') {
    return JsonDecodeErr(Unsupported("expected JSON object"))
  }
  let parsed : Array[MessageField] = []
  let seen_field_names : Array[String] = []
  let seen_oneofs : Array[String] = []
  parser.skip_ws()
  if parser.consume('}') {
    return JsonDecodeOk(message_value([]))
  }
  let mut done = false
  while !done {
    let key = match parser.parse_string() {
      JsonStringErr(e) => return JsonDecodeErr(e)
      JsonStringOk(k) => k
    }
    if !parser.consume(':') {
      return JsonDecodeErr(Unsupported("expected JSON object colon"))
    }
    let fd = match json_find_descriptor(desc, key) {
      None => return JsonDecodeErr(Unsupported("unknown JSON field: " + key))
      Some(found) => found
    }
    if json_string_array_contains(seen_field_names, fd.name) {
      return JsonDecodeErr(Unsupported("duplicate JSON field: " + key))
    }
    seen_field_names.push(fd.name)
    match parse_json_field(parser, fd, descriptors) {
      JsonDecodeErr(e) => return JsonDecodeErr(e)
      JsonDecodeOk(one) =>
        if one.fields.length() > 0 {
          match json_oneof_group(fd.label) {
            None => ()
            Some(group) => {
              for seen in seen_oneofs {
                if seen == group {
                  return JsonDecodeErr(
                    Unsupported(
                      "multiple JSON fields for oneof group: " + group,
                    ),
                  )
                }
              }
              seen_oneofs.push(group)
            }
          }
          append_json_field(parsed, one.fields[0])
        }
    }
    parser.skip_ws()
    if parser.consume(',') {
      ()
    } else if parser.consume('}') {
      done = true
    } else {
      return JsonDecodeErr(Unsupported("expected comma or object end"))
    }
  }
  JsonDecodeOk(message_value(order_json_fields(desc, parsed)))
}

///|
/// Parse a protobuf-style JSON object into a dynamic message. Known fields are
/// accepted in any JSON order and returned in descriptor order.
pub fn json_to_message(
  desc : MessageDescriptor,
  input : String,
) -> JsonDecodeResult {
  json_to_message_with_descriptors(desc, [], input)
}

///|
/// Parse protobuf-style JSON, resolving `NamedType` fields through
/// `descriptors` for nested message values.
pub fn json_to_message_with_descriptors(
  desc : MessageDescriptor,
  descriptors : Array[MessageDescriptor],
  input : String,
) -> JsonDecodeResult {
  let parser = JsonParser::{ src: input, chars: input.to_array(), i: 0 }
  match parse_json_message_object(parser, desc, descriptors) {
    JsonDecodeErr(e) => JsonDecodeErr(e)
    JsonDecodeOk(message) => {
      parser.skip_ws()
      if parser.i != parser.chars.length() {
        JsonDecodeErr(Unsupported("trailing JSON input"))
      } else {
        JsonDecodeOk(message)
      }
    }
  }
}
