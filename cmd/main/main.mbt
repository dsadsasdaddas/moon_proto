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
    #|  moon run cmd/main -- compat --old-schema '<old proto3>' --new-schema '<new proto3>'
    #|
    #|Commands:
    #|  gen --example          Generate MoonBit source for a built-in demo schema.
    #|  gen --schema <text>    Parse, validate, and generate MoonBit source from inline proto3 text.
    #|  doctor --schema <text> Parse and validate inline proto3 text, printing stable diagnostics.
    #|  inspect --schema <text> Print a compact schema summary for reports and debugging.
    #|  compat --old-schema <old> --new-schema <new>
    #|                         Check whether a new schema preserves old field and enum contracts.
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
fn reserved_range_text(range : @proto.ReservedNumberRange) -> String {
  if range.start == range.end {
    range.start.to_string()
  } else {
    range.start.to_string() + " to " + range.end.to_string()
  }
}

///|
fn reserved_ranges_text(ranges : Array[@proto.ReservedNumberRange]) -> String {
  let parts : Array[String] = []
  for range in ranges {
    parts.push(reserved_range_text(range))
  }
  join_lines_with(parts, ", ")
}

///|
fn join_lines_with(parts : Array[String], sep : String) -> String {
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
    let reservation = reservation_for_owner(file.message_reservations, msg.name)
    if reservation.numbers.length() > 0 {
      lines.push("  reserved numbers: " + reserved_ranges_text(reservation.numbers))
    }
    if reservation.names.length() > 0 {
      lines.push("  reserved names: " + join_lines_with(reservation.names, ", "))
    }
  }
  lines.push("enums: " + file.enums.length().to_string())
  for enum_desc in file.enums {
    lines.push(
      "enum " +
      enum_desc.name +
      " values=" +
      enum_desc.values.length().to_string() +
      " allow_alias=" +
      enum_desc.allow_alias.to_string(),
    )
    for value in enum_desc.values {
      lines.push("  " + value.number.to_string() + " " + value.name)
    }
    let reservation = reservation_for_owner(file.enum_reservations, enum_desc.name)
    if reservation.numbers.length() > 0 {
      lines.push("  reserved numbers: " + reserved_ranges_text(reservation.numbers))
    }
    if reservation.names.length() > 0 {
      lines.push("  reserved names: " + join_lines_with(reservation.names, ", "))
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
fn parse_or_print_named_error(
  label : String,
  schema : String,
) -> @proto.ProtoFile? {
  match @proto.parse_proto(schema) {
    @proto.ProtoErr(_) => {
      println("error: failed to parse " + label + " proto3 schema")
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
fn find_message(
  messages : Array[@proto.MessageDescriptor],
  name : String,
) -> @proto.MessageDescriptor? {
  for msg in messages {
    if msg.name == name {
      return Some(msg)
    }
  }
  None
}

///|
fn find_field_by_number(
  fields : Array[@proto.FieldDescriptor],
  number : Int,
) -> @proto.FieldDescriptor? {
  for field in fields {
    if field.number == number {
      return Some(field)
    }
  }
  None
}

///|
fn find_field_by_name(
  fields : Array[@proto.FieldDescriptor],
  name : String,
) -> @proto.FieldDescriptor? {
  for field in fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}

///|
fn find_enum(
  enums : Array[@proto.EnumDescriptor],
  name : String,
) -> @proto.EnumDescriptor? {
  for enum_desc in enums {
    if enum_desc.name == name {
      return Some(enum_desc)
    }
  }
  None
}

///|
fn reservation_for_owner(
  reservations : Array[@proto.ReservedDescriptor],
  owner : String,
) -> @proto.ReservedDescriptor {
  let numbers : Array[@proto.ReservedNumberRange] = []
  let names : Array[String] = []
  for reservation in reservations {
    if reservation.owner == owner {
      for range in reservation.numbers {
        numbers.push(range)
      }
      for name in reservation.names {
        names.push(name)
      }
    }
  }
  @proto.ReservedDescriptor::{ owner, numbers, names }
}

///|
fn reserved_range_contains(
  range : @proto.ReservedNumberRange,
  number : Int,
) -> Bool {
  number >= range.start && number <= range.end
}

///|
fn reserved_ranges_contain(
  ranges : Array[@proto.ReservedNumberRange],
  number : Int,
) -> Bool {
  for range in ranges {
    if reserved_range_contains(range, number) {
      return true
    }
  }
  false
}

///|
fn reserved_names_contain(names : Array[String], name : String) -> Bool {
  for reserved_name in names {
    if reserved_name == name {
      return true
    }
  }
  false
}

///|
fn reserved_range_covered(
  ranges : Array[@proto.ReservedNumberRange],
  wanted : @proto.ReservedNumberRange,
) -> Bool {
  for range in ranges {
    if range.start <= wanted.start && range.end >= wanted.end {
      return true
    }
  }
  false
}

///|
fn find_enum_value_by_number(
  values : Array[@proto.EnumValueDescriptor],
  number : Int,
) -> @proto.EnumValueDescriptor? {
  for value in values {
    if value.number == number {
      return Some(value)
    }
  }
  None
}

///|
fn find_enum_value_by_name(
  values : Array[@proto.EnumValueDescriptor],
  name : String,
) -> @proto.EnumValueDescriptor? {
  for value in values {
    if value.name == name {
      return Some(value)
    }
  }
  None
}

///|
fn push_compat_issue(
  issues : Array[String],
  path : String,
  message : String,
) -> Unit {
  issues.push(path + ": " + message)
}

///|
fn append_validation_issues(
  issues : Array[String],
  prefix : String,
  result : @proto.SchemaValidationResult,
) -> Unit {
  match result {
    @proto.SchemaValid => ()
    @proto.SchemaInvalid(schema_issues) =>
      for issue in schema_issues {
        push_compat_issue(
          issues,
          prefix + "." + issue.path,
          issue.message,
        )
      }
  }
}

///|
fn compare_field_compat(
  issues : Array[String],
  message_name : String,
  old_field : @proto.FieldDescriptor,
  new_fields : Array[@proto.FieldDescriptor],
  new_reservation : @proto.ReservedDescriptor,
) -> Unit {
  let path = "message." + message_name + ".field." + old_field.number.to_string()
  match find_field_by_number(new_fields, old_field.number) {
    Some(new_field) => {
      if new_field.name != old_field.name {
        push_compat_issue(
          issues,
          path,
          "field name changed from " + old_field.name + " to " + new_field.name,
        )
      }
      if new_field.typ != old_field.typ {
        push_compat_issue(
          issues,
          path,
          "field type changed from " +
          scalar_type_name(old_field.typ) +
          " to " +
          scalar_type_name(new_field.typ),
        )
      }
      if new_field.label != old_field.label {
        push_compat_issue(
          issues,
          path,
          "field label changed from " +
          field_label_name(old_field.label) +
          " to " +
          field_label_name(new_field.label),
        )
      }
    }
    None =>
      match find_field_by_name(new_fields, old_field.name) {
        Some(new_field) =>
          push_compat_issue(
            issues,
            "message." + message_name + ".field." + old_field.name,
            "field number changed from " +
            old_field.number.to_string() +
            " to " +
            new_field.number.to_string(),
          )
        None => {
          let reserved_number = reserved_ranges_contain(
            new_reservation.numbers,
            old_field.number,
          )
          let reserved_name = reserved_names_contain(
            new_reservation.names,
            old_field.name,
          )
          if !(reserved_number && reserved_name) {
            push_compat_issue(
              issues,
              path,
              "field removed without reserving number and name: " +
              old_field.name,
            )
          }
        }
      }
  }
}

///|
fn compare_message_reservation_compat(
  issues : Array[String],
  owner : String,
  old_reservation : @proto.ReservedDescriptor,
  new_reservation : @proto.ReservedDescriptor,
) -> Unit {
  for range in old_reservation.numbers {
    if !reserved_range_covered(new_reservation.numbers, range) {
      push_compat_issue(
        issues,
        "message." + owner + ".reserved." + range.start.to_string(),
        "reserved number range not preserved: " + reserved_range_text(range),
      )
    }
  }
  for name in old_reservation.names {
    if !reserved_names_contain(new_reservation.names, name) {
      push_compat_issue(
        issues,
        "message." + owner + ".reserved." + name,
        "reserved name not preserved",
      )
    }
  }
}

///|
fn compare_message_compat(
  issues : Array[String],
  old_msg : @proto.MessageDescriptor,
  new_msg : @proto.MessageDescriptor,
  old_reservation : @proto.ReservedDescriptor,
  new_reservation : @proto.ReservedDescriptor,
) -> Unit {
  for old_field in old_msg.fields {
    compare_field_compat(
      issues,
      old_msg.name,
      old_field,
      new_msg.fields,
      new_reservation,
    )
  }
  compare_message_reservation_compat(
    issues,
    old_msg.name,
    old_reservation,
    new_reservation,
  )
  for new_field in new_msg.fields {
    if reserved_ranges_contain(old_reservation.numbers, new_field.number) {
      push_compat_issue(
        issues,
        "message." + old_msg.name + ".field." + new_field.number.to_string(),
        "field uses previously reserved number",
      )
    }
    if reserved_names_contain(old_reservation.names, new_field.name) {
      push_compat_issue(
        issues,
        "message." + old_msg.name + ".field." + new_field.name,
        "field uses previously reserved name",
      )
    }
  }
}

///|
fn compare_enum_compat(
  issues : Array[String],
  old_enum : @proto.EnumDescriptor,
  new_enum : @proto.EnumDescriptor,
  old_reservation : @proto.ReservedDescriptor,
  new_reservation : @proto.ReservedDescriptor,
) -> Unit {
  for old_value in old_enum.values {
    let path =
      "enum." + old_enum.name + ".value." + old_value.number.to_string()
    match find_enum_value_by_number(new_enum.values, old_value.number) {
      Some(new_value) =>
        if new_value.name != old_value.name {
          push_compat_issue(
            issues,
            path,
            "enum value name changed from " +
            old_value.name +
            " to " +
            new_value.name,
          )
        }
      None =>
        match find_enum_value_by_name(new_enum.values, old_value.name) {
          Some(new_value) =>
            push_compat_issue(
              issues,
              "enum." + old_enum.name + ".value." + old_value.name,
              "enum value number changed from " +
              old_value.number.to_string() +
              " to " +
              new_value.number.to_string(),
            )
          None => {
            let reserved_number = reserved_ranges_contain(
              new_reservation.numbers,
              old_value.number,
            )
            let reserved_name = reserved_names_contain(
              new_reservation.names,
              old_value.name,
            )
            if !(reserved_number && reserved_name) {
              push_compat_issue(
                issues,
                path,
                "enum value removed without reserving number and name: " +
                old_value.name,
              )
            }
          }
        }
    }
  }
  for range in old_reservation.numbers {
    if !reserved_range_covered(new_reservation.numbers, range) {
      push_compat_issue(
        issues,
        "enum." + old_enum.name + ".reserved." + range.start.to_string(),
        "reserved number range not preserved: " + reserved_range_text(range),
      )
    }
  }
  for name in old_reservation.names {
    if !reserved_names_contain(new_reservation.names, name) {
      push_compat_issue(
        issues,
        "enum." + old_enum.name + ".reserved." + name,
        "reserved name not preserved",
      )
    }
  }
  for new_value in new_enum.values {
    if reserved_ranges_contain(old_reservation.numbers, new_value.number) {
      push_compat_issue(
        issues,
        "enum." + old_enum.name + ".value." + new_value.number.to_string(),
        "enum value uses previously reserved number",
      )
    }
    if reserved_names_contain(old_reservation.names, new_value.name) {
      push_compat_issue(
        issues,
        "enum." + old_enum.name + ".value." + new_value.name,
        "enum value uses previously reserved name",
      )
    }
  }
}

///|
fn compatibility_issues(
  old_file : @proto.ProtoFile,
  new_file : @proto.ProtoFile,
) -> Array[String] {
  let issues : Array[String] = []
  append_validation_issues(
    issues,
    "old",
    @proto.validate_proto_file(old_file),
  )
  append_validation_issues(
    issues,
    "new",
    @proto.validate_proto_file(new_file),
  )
  if issues.length() > 0 {
    return issues
  }
  if old_file.syntax != new_file.syntax {
    push_compat_issue(
      issues,
      "syntax",
      "changed from " + old_file.syntax + " to " + new_file.syntax,
    )
  }
  if old_file.package_name != new_file.package_name {
    push_compat_issue(
      issues,
      "package",
      "changed from " + old_file.package_name + " to " + new_file.package_name,
    )
  }
  for old_msg in old_file.messages {
    match find_message(new_file.messages, old_msg.name) {
      None =>
        push_compat_issue(
          issues,
          "message." + old_msg.name,
          "message removed",
        )
      Some(new_msg) =>
        compare_message_compat(
          issues,
          old_msg,
          new_msg,
          reservation_for_owner(old_file.message_reservations, old_msg.name),
          reservation_for_owner(new_file.message_reservations, old_msg.name),
        )
    }
  }
  for old_enum in old_file.enums {
    match find_enum(new_file.enums, old_enum.name) {
      None =>
        push_compat_issue(
          issues,
          "enum." + old_enum.name,
          "enum removed",
        )
      Some(new_enum) =>
        compare_enum_compat(
          issues,
          old_enum,
          new_enum,
          reservation_for_owner(old_file.enum_reservations, old_enum.name),
          reservation_for_owner(new_file.enum_reservations, old_enum.name),
        )
    }
  }
  issues
}

///|
fn compat_report(old_file : @proto.ProtoFile, new_file : @proto.ProtoFile) -> String {
  let issues = compatibility_issues(old_file, new_file)
  let lines : Array[String] = []
  if issues.length() == 0 {
    lines.push("schema compatible")
    lines.push("old messages: " + old_file.messages.length().to_string())
    lines.push("new messages: " + new_file.messages.length().to_string())
    lines.push("old enums: " + old_file.enums.length().to_string())
    lines.push("new enums: " + new_file.enums.length().to_string())
  } else {
    lines.push("schema incompatible")
    lines.push("issues: " + issues.length().to_string())
    for issue in issues {
      lines.push(issue)
    }
  }
  join_lines(lines)
}

///|
fn compat(old_schema : String, new_schema : String) -> Unit {
  match (
    parse_or_print_named_error("old", old_schema),
    parse_or_print_named_error("new", new_schema),
  ) {
    (Some(old_file), Some(new_file)) => println(compat_report(old_file, new_file))
    _ => ()
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
  match arg_at(args, 1) {
    Some("gen") =>
      match (arg_at(args, 2), arg_at(args, 3)) {
        (Some("--example"), _) => generate(example_schema())
        (Some("--schema"), Some(schema)) => generate(schema)
        _ => println(usage())
      }
    Some("doctor") =>
      match (arg_at(args, 2), arg_at(args, 3)) {
        (Some("--schema"), Some(schema)) => doctor(schema)
        _ => println(usage())
      }
    Some("inspect") =>
      match (arg_at(args, 2), arg_at(args, 3)) {
        (Some("--schema"), Some(schema)) => inspect(schema)
        _ => println(usage())
      }
    Some("compat") =>
      match (arg_at(args, 2), arg_at(args, 3), arg_at(args, 4), arg_at(args, 5)) {
        (Some("--old-schema"), Some(old_schema), Some("--new-schema"), Some(new_schema)) =>
          compat(old_schema, new_schema)
        _ => println(usage())
      }
    Some("--help") | Some("help") | None => println(usage())
    _ => println(usage())
  }
}
