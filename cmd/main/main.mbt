///|
fn usage() -> String {
  let text =
    #|moon_proto CLI
    #|
    #|Usage:
    #|  moon run cmd/main -- gen --example
    #|  moon run cmd/main -- gen --schema '<proto3 source>'
    #|  moon run cmd/main -- doctor --schema '<proto3 source>'
    #|  moon run cmd/main -- inspect --schema '<proto3 source>'
    #|
    #|Commands:
    #|  gen --example          Generate MoonBit source for a built-in demo schema.
    #|  gen --schema <text>    Parse, validate, and generate MoonBit source from inline proto3 text.
    #|  doctor --schema <text> Parse and validate inline proto3 text, printing stable diagnostics.
    #|  inspect --schema <text> Print a compact schema summary for reports and debugging.
  text
}

///|
fn example_schema() -> String {
  let schema =
    #|syntax = "proto3";
    #|package demo;
    #|enum Color {
    #|  COLOR_UNSPECIFIED = 0;
    #|  RED = 1;
    #|}
    #|message Address {
    #|  string street = 1;
    #|  uint64 zip = 2;
    #|}
    #|message User {
    #|  uint64 id = 1;
    #|  string name = 2;
    #|  repeated string tags = 3;
    #|  Color favorite = 4;
    #|  Address address = 5;
    #|  map<string, uint64> counters = 6;
    #|  oneof contact {
    #|    string email = 7;
    #|    string phone = 8;
    #|  }
    #|}
  schema
}

///|
fn join_lines(lines : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < lines.length(); i = i + 1 {
    if i > 0 {
      out = out + "\n"
    }
    out = out + lines[i]
  }
  out
}

///|
fn first_issue_message(result : @proto.SchemaValidationResult) -> String {
  match result {
    @proto.SchemaValid => ""
    @proto.SchemaInvalid(issues) =>
      if issues.length() == 0 {
        "unknown schema validation error"
      } else {
        issues[0].path + ": " + issues[0].message
      }
  }
}

///|
fn scalar_type_name(typ : @proto.ScalarType) -> String {
  match typ {
    @proto.DoubleType => "double"
    @proto.FloatType => "float"
    @proto.Int32Type => "int32"
    @proto.Int64Type => "int64"
    @proto.UInt32Type => "uint32"
    @proto.UInt64Type => "uint64"
    @proto.SInt32Type => "sint32"
    @proto.SInt64Type => "sint64"
    @proto.Fixed32Type => "fixed32"
    @proto.Fixed64Type => "fixed64"
    @proto.SFixed32Type => "sfixed32"
    @proto.SFixed64Type => "sfixed64"
    @proto.BoolType => "bool"
    @proto.StringType => "string"
    @proto.BytesType => "bytes"
    @proto.EnumType(name) => "enum " + name
    @proto.NamedType(name) => name
    @proto.MapType(key_typ, value_typ) =>
      "map<" + scalar_type_name(key_typ) + ", " + scalar_type_name(value_typ) + ">"
  }
}

///|
fn field_label_name(label : @proto.FieldLabel) -> String {
  match label {
    @proto.Singular => "singular"
    @proto.Optional => "optional"
    @proto.Repeated => "repeated"
    @proto.Oneof(group) => "oneof " + group
  }
}

///|
fn validation_report(file : @proto.ProtoFile) -> String {
  let result = @proto.validate_proto_file(file)
  let lines : Array[String] = []
  match result {
    @proto.SchemaValid => {
      lines.push("schema valid")
      lines.push("syntax: " + file.syntax)
      lines.push("package: " + file.package_name)
      lines.push("messages: " + file.messages.length().to_string())
      lines.push("enums: " + file.enums.length().to_string())
    }
    @proto.SchemaInvalid(issues) => {
      lines.push("schema invalid")
      lines.push("issues: " + issues.length().to_string())
      for issue in issues {
        lines.push(issue.path + ": " + issue.message)
      }
    }
  }
  join_lines(lines)
}

///|
fn inspect_report(file : @proto.ProtoFile) -> String {
  let lines : Array[String] = []
  lines.push("syntax: " + file.syntax)
  lines.push("package: " + file.package_name)
  lines.push("messages: " + file.messages.length().to_string())
  for msg in file.messages {
    lines.push("message " + msg.name + " fields=" + msg.fields.length().to_string())
    for field in msg.fields {
      lines.push(
        "  " +
        field.number.to_string() +
        " " +
        field.name +
        " : " +
        field_label_name(field.label) +
        " " +
        scalar_type_name(field.typ),
      )
    }
  }
  lines.push("enums: " + file.enums.length().to_string())
  for enum_desc in file.enums {
    lines.push("enum " + enum_desc.name + " values=" + enum_desc.values.length().to_string())
    for value in enum_desc.values {
      lines.push("  " + value.number.to_string() + " " + value.name)
    }
  }
  join_lines(lines)
}

///|
fn parse_or_print_error(schema : String) -> @proto.ProtoFile? {
  match @proto.parse_proto(schema) {
    @proto.ProtoErr(_) => {
      println("error: failed to parse proto3 schema")
      None
    }
    @proto.ProtoOk(file) => Some(file)
  }
}

///|
fn generate(schema : String) -> Unit {
  match parse_or_print_error(schema) {
    None => ()
    Some(file) =>
      match @proto.validate_proto_file(file) {
        @proto.SchemaInvalid(_) =>
          println(
            "error: " + first_issue_message(@proto.validate_proto_file(file)),
          )
        @proto.SchemaValid => println(@proto.generate_moonbit_source(file))
      }
  }
}

///|
fn doctor(schema : String) -> Unit {
  match parse_or_print_error(schema) {
    None => ()
    Some(file) => println(validation_report(file))
  }
}

///|
fn inspect(schema : String) -> Unit {
  match parse_or_print_error(schema) {
    None => ()
    Some(file) => println(inspect_report(file))
  }
}

///|
fn arg_at(args : Array[String], index : Int) -> String? {
  if index < args.length() {
    Some(args[index])
  } else {
    None
  }
}

///|
fn main {
  let args = @env.args()
  match (arg_at(args, 1), arg_at(args, 2), arg_at(args, 3)) {
    (Some("gen"), Some("--example"), _) => generate(example_schema())
    (Some("gen"), Some("--schema"), Some(schema)) => generate(schema)
    (Some("doctor"), Some("--schema"), Some(schema)) => doctor(schema)
    (Some("inspect"), Some("--schema"), Some(schema)) => inspect(schema)
    (Some("--help"), _, _) | (Some("help"), _, _) | (None, _, _) =>
      println(usage())
    _ => println(usage())
  }
}
