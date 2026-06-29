///|
/// Proto3 scalar types supported by the stage-1 runtime/codegen plan.
pub(all) enum ScalarType {
  DoubleType
  FloatType
  Int32Type
  Int64Type
  UInt32Type
  UInt64Type
  SInt32Type
  SInt64Type
  Fixed32Type
  Fixed64Type
  SFixed32Type
  SFixed64Type
  BoolType
  StringType
  BytesType
  EnumType(String)
  NamedType(String)
  MapType(ScalarType, ScalarType)
} derive(Debug, Eq)

///|
/// Field cardinality as written in a proto3 schema.
pub(all) enum FieldLabel {
  Singular
  Optional
  Repeated
} derive(Debug, Eq)

///|
/// A parsed field descriptor.
pub(all) struct FieldDescriptor {
  name : String
  typ : ScalarType
  number : Int
  label : FieldLabel
} derive(Debug, Eq)

///|
/// A parsed message descriptor.
pub(all) struct MessageDescriptor {
  name : String
  fields : Array[FieldDescriptor]
} derive(Debug, Eq)

///|
/// A parsed enum value descriptor.
pub(all) struct EnumValueDescriptor {
  name : String
  number : Int
} derive(Debug, Eq)

///|
/// A parsed enum descriptor.
pub(all) struct EnumDescriptor {
  name : String
  values : Array[EnumValueDescriptor]
} derive(Debug, Eq)

///|
/// Top-level proto file model used by parser and codegen.
pub(all) struct ProtoFile {
  syntax : String
  package_name : String
  messages : Array[MessageDescriptor]
  enums : Array[EnumDescriptor]
} derive(Debug, Eq)

///|
/// Convert a schema type token into a scalar or named message type.
pub fn scalar_type_from_string(name : String) -> ScalarType {
  match name {
    "double" => DoubleType
    "float" => FloatType
    "int32" => Int32Type
    "int64" => Int64Type
    "uint32" => UInt32Type
    "uint64" => UInt64Type
    "sint32" => SInt32Type
    "sint64" => SInt64Type
    "fixed32" => Fixed32Type
    "fixed64" => Fixed64Type
    "sfixed32" => SFixed32Type
    "sfixed64" => SFixed64Type
    "bool" => BoolType
    "string" => StringType
    "bytes" => BytesType
    other => NamedType(other)
  }
}

///|
/// Map a scalar type to its protobuf wire type.
pub fn ScalarType::wire_type(self : ScalarType) -> WireType {
  match self {
    DoubleType => Fixed64
    FloatType => Fixed32
    Fixed32Type => Fixed32
    SFixed32Type => Fixed32
    Fixed64Type => Fixed64
    SFixed64Type => Fixed64
    EnumType(_) => Varint
    StringType => LengthDelimited
    BytesType => LengthDelimited
    NamedType(_) => LengthDelimited
    MapType(_, _) => LengthDelimited
    _ => Varint
  }
}

///|
/// Empty proto file constructor used by tests and future codegen.
pub fn ProtoFile::empty() -> ProtoFile {
  ProtoFile::{ syntax: "proto3", package_name: "", messages: [], enums: [] }
}
