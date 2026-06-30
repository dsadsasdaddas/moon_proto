///|
/// Options for emitting MoonBit source from a parsed proto file.
pub(all) struct CodegenOptions {
  emit_descriptor_functions : Bool
  emit_runtime_helpers : Bool
} derive(Debug, Eq)

///|
/// Default generator settings used by examples and tests.
pub fn CodegenOptions::default() -> CodegenOptions {
  CodegenOptions::{
    emit_descriptor_functions: true,
    emit_runtime_helpers: true,
  }
}

///|
fn join_strings(parts : Array[String], sep : String) -> String {
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
fn moonbit_type_name(typ : ScalarType) -> String {
  match typ {
    DoubleType => "Double"
    FloatType => "Float"
    Int32Type => "Int"
    Int64Type => "Int64"
    UInt32Type => "UInt"
    UInt64Type => "UInt64"
    SInt32Type => "Int"
    SInt64Type => "Int64"
    Fixed32Type => "UInt"
    Fixed64Type => "UInt64"
    SFixed32Type => "Int"
    SFixed64Type => "Int64"
    BoolType => "Bool"
    StringType => "String"
    BytesType => "Bytes"
    EnumType(name) => name
    NamedType(name) => name
    MapType(_, _) => "MessageValue"
  }
}

///|
fn moonbit_field_type(field : FieldDescriptor) -> String {
  let base = moonbit_type_name(field.typ)
  match field.label {
    Repeated => "Array[" + base + "]"
    Optional => base + "?"
    Oneof(_) => base + "?"
    Singular => base
  }
}

///|
fn scalar_type_source(typ : ScalarType) -> String {
  match typ {
    DoubleType => "DoubleType"
    FloatType => "FloatType"
    Int32Type => "Int32Type"
    Int64Type => "Int64Type"
    UInt32Type => "UInt32Type"
    UInt64Type => "UInt64Type"
    SInt32Type => "SInt32Type"
    SInt64Type => "SInt64Type"
    Fixed32Type => "Fixed32Type"
    Fixed64Type => "Fixed64Type"
    SFixed32Type => "SFixed32Type"
    SFixed64Type => "SFixed64Type"
    BoolType => "BoolType"
    StringType => "StringType"
    BytesType => "BytesType"
    EnumType(name) => "EnumType(\"" + name + "\")"
    NamedType(name) => "NamedType(\"" + name + "\")"
    MapType(key_typ, value_typ) =>
      "MapType(" +
      scalar_type_source(key_typ) +
      ", " +
      scalar_type_source(value_typ) +
      ")"
  }
}

///|
fn field_label_source(label : FieldLabel) -> String {
  match label {
    Singular => "Singular"
    Optional => "Optional"
    Repeated => "Repeated"
    Oneof(group) => "Oneof(\"" + group + "\")"
  }
}

///|
/// Emit a MoonBit enum declaration for one enum descriptor.
pub fn generate_enum(desc : EnumDescriptor) -> String {
  let lines : Array[String] = []
  lines.push("pub(all) enum " + desc.name + " {")
  for value in desc.values {
    lines.push("  " + value.name)
  }
  lines.push("} derive(Debug, Eq)")
  join_strings(lines, "\n")
}

///|
/// Emit a descriptor function for one enum descriptor.
pub fn generate_enum_descriptor_function(desc : EnumDescriptor) -> String {
  let lines : Array[String] = []
  lines.push("pub fn descriptor_" + desc.name + "() -> EnumDescriptor {")
  lines.push("  EnumDescriptor::{")
  lines.push("    name : \"" + desc.name + "\",")
  lines.push("    allow_alias : " + desc.allow_alias.to_string() + ",")
  lines.push("    values : [")
  for value in desc.values {
    lines.push(
      "      EnumValueDescriptor::{ name : \"" +
      value.name +
      "\", number : " +
      value.number.to_string() +
      " },",
    )
  }
  lines.push("    ],")
  lines.push("  }")
  lines.push("}")
  join_strings(lines, "\n")
}

///|
/// Emit a MoonBit struct declaration for one message descriptor.
pub fn generate_message_struct(desc : MessageDescriptor) -> String {
  let lines : Array[String] = []
  lines.push("pub(all) struct " + desc.name + " {")
  for field in desc.fields {
    lines.push("  " + field.name + " : " + moonbit_field_type(field))
  }
  lines.push("} derive(Debug, Eq)")
  join_strings(lines, "\n")
}

///| Emit a descriptor function that can be compiled into generated MoonBit

///|
/// code and passed back to `encode_message` / `decode_message`.
pub fn generate_descriptor_function(desc : MessageDescriptor) -> String {
  let lines : Array[String] = []
  lines.push("pub fn descriptor_" + desc.name + "() -> MessageDescriptor {")
  lines.push("  MessageDescriptor::{")
  lines.push("    name : \"" + desc.name + "\",")
  lines.push("    fields : [")
  for field in desc.fields {
    lines.push(
      "      FieldDescriptor::{ name : \"" +
      field.name +
      "\", typ : " +
      scalar_type_source(field.typ) +
      ", number : " +
      field.number.to_string() +
      ", label : " +
      field_label_source(field.label) +
      " },",
    )
  }
  lines.push("    ],")
  lines.push("  }")
  lines.push("}")
  join_strings(lines, "\n")
}

///|
/// Emit a registry function used by generated runtime helpers to resolve
/// nested message descriptors.
pub fn generate_message_descriptor_registry(file : ProtoFile) -> String {
  let lines : Array[String] = []
  lines.push("pub fn message_descriptors() -> Array[MessageDescriptor] {")
  lines.push("  [")
  for msg in file.messages {
    lines.push("    descriptor_" + msg.name + "(),")
  }
  lines.push("  ]")
  lines.push("}")
  join_strings(lines, "\n")
}

///|
/// Emit dynamic encode/decode/JSON helper functions for one generated message.
pub fn generate_message_runtime_helpers(desc : MessageDescriptor) -> String {
  let lines : Array[String] = []
  lines.push(
    "pub fn encode_" +
    desc.name +
    "(value : MessageValue) -> EncodeMessageResult {",
  )
  lines.push(
    "  encode_message_with_descriptors(descriptor_" +
    desc.name +
    "(), message_descriptors(), value)",
  )
  lines.push("}")
  lines.push("")
  lines.push(
    "pub fn decode_" + desc.name + "(input : Bytes) -> DecodeMessageResult {",
  )
  lines.push(
    "  decode_message_with_descriptors(descriptor_" +
    desc.name +
    "(), message_descriptors(), input)",
  )
  lines.push("}")
  lines.push("")
  lines.push(
    "pub fn to_json_" +
    desc.name +
    "(value : MessageValue) -> JsonEncodeResult {",
  )
  lines.push(
    "  message_to_json_with_descriptors(descriptor_" +
    desc.name +
    "(), message_descriptors(), value)",
  )
  lines.push("}")
  lines.push("")
  lines.push(
    "pub fn to_json_lower_camel_" +
    desc.name +
    "(value : MessageValue) -> JsonEncodeResult {",
  )
  lines.push(
    "  message_to_json_lower_camel_with_descriptors(descriptor_" +
    desc.name +
    "(), message_descriptors(), value)",
  )
  lines.push("}")
  lines.push("")
  lines.push(
    "pub fn from_json_" + desc.name + "(input : String) -> JsonDecodeResult {",
  )
  lines.push(
    "  json_to_message_with_descriptors(descriptor_" +
    desc.name +
    "(), message_descriptors(), input)",
  )
  lines.push("}")
  join_strings(lines, "\n")
}

///|
/// Generate MoonBit declarations for all messages in a parsed proto file.
pub fn generate_moonbit_source(
  file : ProtoFile,
  options? : CodegenOptions = CodegenOptions::default(),
) -> String {
  let chunks : Array[String] = []
  for enum_desc in file.enums {
    chunks.push(generate_enum(enum_desc))
    if options.emit_descriptor_functions {
      chunks.push(generate_enum_descriptor_function(enum_desc))
    }
  }
  for msg in file.messages {
    chunks.push(generate_message_struct(msg))
    if options.emit_descriptor_functions {
      chunks.push(generate_descriptor_function(msg))
    }
  }
  if options.emit_descriptor_functions &&
    options.emit_runtime_helpers &&
    file.messages.length() > 0 {
    chunks.push(generate_message_descriptor_registry(file))
    for msg in file.messages {
      chunks.push(generate_message_runtime_helpers(msg))
    }
  }
  join_strings(chunks, "\n\n")
}
