///|
/// One schema validation issue with a stable path for diagnostics.
pub(all) struct SchemaIssue {
  path : String
  message : String
} derive(Debug, Eq)

///|
/// Result of validating a proto schema model.
pub(all) enum SchemaValidationResult {
  SchemaValid
  SchemaInvalid(Array[SchemaIssue])
} derive(Debug, Eq)

///|
fn schema_issue(path : String, message : String) -> SchemaIssue {
  SchemaIssue::{ path, message }
}

///|
fn push_issue(
  issues : Array[SchemaIssue],
  path : String,
  message : String,
) -> Unit {
  issues.push(schema_issue(path, message))
}

///|
fn validate_nonempty_name(
  issues : Array[SchemaIssue],
  path : String,
  name : String,
) -> Unit {
  if name.length() == 0 {
    push_issue(issues, path, "name must not be empty")
  }
}

///|
/// Protobuf field numbers must be positive, at most 2^29 - 1, and must not
/// fall inside the implementation-reserved 19000..19999 range.
pub fn is_valid_field_number(number : Int) -> Bool {
  number > 0 && number <= 536870911 && (number < 19000 || number > 19999)
}

///|
fn validate_field_descriptor(
  issues : Array[SchemaIssue],
  message_name : String,
  field : FieldDescriptor,
) -> Unit {
  let path = "message." + message_name + ".field." + field.name
  validate_nonempty_name(issues, path + ".name", field.name)
  if !is_valid_field_number(field.number) {
    push_issue(issues, path + ".number", "invalid protobuf field number")
  }
  match field.label {
    Singular | Optional | Repeated => ()
    Oneof(group) => validate_nonempty_name(issues, path + ".oneof", group)
  }
  match field.typ {
    MapType(key_typ, value_typ) => {
      if field.label != Repeated {
        push_issue(issues, path + ".label", "map field must be repeated")
      }
      if !is_valid_map_key_type(key_typ) {
        push_issue(issues, path + ".key", "invalid map key type")
      }
      match value_typ {
        MapType(_, _) =>
          push_issue(issues, path + ".value", "map value must not be a map")
        _ => ()
      }
    }
    _ => ()
  }
}

///|
/// Protobuf map keys may be integral, bool or string scalar types.
pub fn is_valid_map_key_type(typ : ScalarType) -> Bool {
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
    | BoolType
    | StringType => true
    DoubleType
    | FloatType
    | BytesType
    | EnumType(_)
    | NamedType(_)
    | MapType(_, _) => false
  }
}

///|
fn has_duplicate_field_name(
  fields : Array[FieldDescriptor],
  index : Int,
) -> Bool {
  for i = 0; i < index; i = i + 1 {
    if fields[i].name == fields[index].name {
      return true
    }
  }
  false
}

///|
fn has_duplicate_field_number(
  fields : Array[FieldDescriptor],
  index : Int,
) -> Bool {
  for i = 0; i < index; i = i + 1 {
    if fields[i].number == fields[index].number {
      return true
    }
  }
  false
}

///|
fn reserved_range_contains(range : ReservedNumberRange, number : Int) -> Bool {
  number >= range.start && number <= range.end
}

///|
fn reserved_ranges_contain(
  ranges : Array[ReservedNumberRange],
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
fn reservation_for_owner(
  reservations : Array[ReservedDescriptor],
  owner : String,
) -> ReservedDescriptor {
  let numbers : Array[ReservedNumberRange] = []
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
  ReservedDescriptor::{ owner, numbers, names }
}

///|
fn has_duplicate_reserved_name(names : Array[String], index : Int) -> Bool {
  for i = 0; i < index; i = i + 1 {
    if names[i] == names[index] {
      return true
    }
  }
  false
}

///|
fn reserved_range_overlaps(
  ranges : Array[ReservedNumberRange],
  index : Int,
) -> Bool {
  let current = ranges[index]
  for i = 0; i < index; i = i + 1 {
    let other = ranges[i]
    if current.start <= other.end && other.start <= current.end {
      return true
    }
  }
  false
}

///|
fn validate_reserved_descriptor(
  issues : Array[SchemaIssue],
  path : String,
  reservation : ReservedDescriptor,
  is_enum : Bool,
) -> Unit {
  for i = 0; i < reservation.numbers.length(); i = i + 1 {
    let range = reservation.numbers[i]
    let range_path = path + ".reserved." + range.start.to_string()
    if range.start > range.end {
      push_issue(issues, range_path, "reserved range start must be <= end")
    }
    let start_valid = if is_enum {
      is_valid_enum_reserved_number(range.start)
    } else {
      is_valid_field_number(range.start)
    }
    let end_valid = if is_enum {
      is_valid_enum_reserved_number(range.end)
    } else {
      is_valid_field_number(range.end)
    }
    if !start_valid || !end_valid {
      push_issue(issues, range_path, "invalid reserved number range")
    }
    if reserved_range_overlaps(reservation.numbers, i) {
      push_issue(issues, range_path, "overlapping reserved number range")
    }
  }
  for i = 0; i < reservation.names.length(); i = i + 1 {
    let name = reservation.names[i]
    let name_path = path + ".reserved." + name
    validate_nonempty_name(issues, name_path, name)
    if has_duplicate_reserved_name(reservation.names, i) {
      push_issue(issues, name_path, "duplicate reserved name")
    }
  }
}

///|
fn validate_message_reservations(
  issues : Array[SchemaIssue],
  message : MessageDescriptor,
  reservation : ReservedDescriptor,
) -> Unit {
  let path = "message." + message.name
  validate_reserved_descriptor(issues, path, reservation, false)
  for field in message.fields {
    if reserved_ranges_contain(reservation.numbers, field.number) {
      push_issue(
        issues,
        path + ".field." + field.name + ".number",
        "field uses reserved number",
      )
    }
    if reserved_names_contain(reservation.names, field.name) {
      push_issue(
        issues,
        path + ".field." + field.name + ".name",
        "field uses reserved name",
      )
    }
  }
}

///|
pub fn validate_message_descriptor(
  message : MessageDescriptor,
) -> SchemaValidationResult {
  let issues : Array[SchemaIssue] = []
  validate_nonempty_name(issues, "message.name", message.name)
  for i = 0; i < message.fields.length(); i = i + 1 {
    let field = message.fields[i]
    validate_field_descriptor(issues, message.name, field)
    if has_duplicate_field_name(message.fields, i) {
      push_issue(
        issues,
        "message." + message.name + ".field." + field.name,
        "duplicate field name",
      )
    }
    if has_duplicate_field_number(message.fields, i) {
      push_issue(
        issues,
        "message." + message.name + ".field." + field.number.to_string(),
        "duplicate field number",
      )
    }
  }
  if issues.length() == 0 {
    SchemaValid
  } else {
    SchemaInvalid(issues)
  }
}

///|
fn has_duplicate_enum_value_name(
  values : Array[EnumValueDescriptor],
  index : Int,
) -> Bool {
  for i = 0; i < index; i = i + 1 {
    if values[i].name == values[index].name {
      return true
    }
  }
  false
}

///|
fn has_duplicate_enum_value_number(
  values : Array[EnumValueDescriptor],
  index : Int,
) -> Bool {
  for i = 0; i < index; i = i + 1 {
    if values[i].number == values[index].number {
      return true
    }
  }
  false
}

///|
fn is_valid_enum_reserved_number(number : Int) -> Bool {
  number >= (-2147483647 - 1) && number <= 2147483647
}

///|
fn validate_enum_reservations(
  issues : Array[SchemaIssue],
  enum_desc : EnumDescriptor,
  reservation : ReservedDescriptor,
) -> Unit {
  let path = "enum." + enum_desc.name
  validate_reserved_descriptor(
    issues,
    path,
    reservation,
    true,
  )
  for value in enum_desc.values {
    if reserved_ranges_contain(reservation.numbers, value.number) {
      push_issue(
        issues,
        path + ".value." + value.name + ".number",
        "enum value uses reserved number",
      )
    }
    if reserved_names_contain(reservation.names, value.name) {
      push_issue(
        issues,
        path + ".value." + value.name + ".name",
        "enum value uses reserved name",
      )
    }
  }
}

///|
pub fn validate_enum_descriptor(
  enum_desc : EnumDescriptor,
) -> SchemaValidationResult {
  let issues : Array[SchemaIssue] = []
  validate_nonempty_name(issues, "enum.name", enum_desc.name)
  if enum_desc.values.length() == 0 {
    push_issue(
      issues,
      "enum." + enum_desc.name + ".values",
      "proto3 enum must have at least one value",
    )
  } else if enum_desc.values[0].number != 0 {
    push_issue(
      issues,
      "enum." + enum_desc.name + ".values[0]",
      "proto3 enum first value must be zero",
    )
  }
  for i = 0; i < enum_desc.values.length(); i = i + 1 {
    let value = enum_desc.values[i]
    validate_nonempty_name(
      issues,
      "enum." + enum_desc.name + ".value." + value.name,
      value.name,
    )
    if has_duplicate_enum_value_name(enum_desc.values, i) {
      push_issue(
        issues,
        "enum." + enum_desc.name + ".value." + value.name,
        "duplicate enum value name",
      )
    }
    if !enum_desc.allow_alias &&
      has_duplicate_enum_value_number(enum_desc.values, i) {
      push_issue(
        issues,
        "enum." + enum_desc.name + ".value." + value.number.to_string(),
        "duplicate enum value number",
      )
    }
  }
  if issues.length() == 0 {
    SchemaValid
  } else {
    SchemaInvalid(issues)
  }
}

///|
fn append_validation_result(
  issues : Array[SchemaIssue],
  result : SchemaValidationResult,
) -> Unit {
  match result {
    SchemaValid => ()
    SchemaInvalid(more) =>
      for issue in more {
        issues.push(issue)
      }
  }
}

///|
fn has_duplicate_top_level_message(
  messages : Array[MessageDescriptor],
  index : Int,
) -> Bool {
  for i = 0; i < index; i = i + 1 {
    if messages[i].name == messages[index].name {
      return true
    }
  }
  false
}

///|
fn has_duplicate_top_level_enum(
  enums : Array[EnumDescriptor],
  index : Int,
) -> Bool {
  for i = 0; i < index; i = i + 1 {
    if enums[i].name == enums[index].name {
      return true
    }
  }
  false
}

///|
fn enum_conflicts_with_message(
  messages : Array[MessageDescriptor],
  enum_name : String,
) -> Bool {
  for message in messages {
    if message.name == enum_name {
      return true
    }
  }
  false
}

///|
pub fn validate_proto_file(file : ProtoFile) -> SchemaValidationResult {
  let issues : Array[SchemaIssue] = []
  if file.syntax != "proto3" {
    push_issue(issues, "syntax", "only proto3 syntax is supported")
  }
  for i = 0; i < file.messages.length(); i = i + 1 {
    let message = file.messages[i]
    append_validation_result(issues, validate_message_descriptor(message))
    validate_message_reservations(
      issues,
      message,
      reservation_for_owner(file.message_reservations, message.name),
    )
    if has_duplicate_top_level_message(file.messages, i) {
      push_issue(
        issues,
        "message." + message.name,
        "duplicate top-level message name",
      )
    }
  }
  for i = 0; i < file.enums.length(); i = i + 1 {
    let enum_desc = file.enums[i]
    append_validation_result(issues, validate_enum_descriptor(enum_desc))
    validate_enum_reservations(
      issues,
      enum_desc,
      reservation_for_owner(file.enum_reservations, enum_desc.name),
    )
    if has_duplicate_top_level_enum(file.enums, i) {
      push_issue(
        issues,
        "enum." + enum_desc.name,
        "duplicate top-level enum name",
      )
    }
    if enum_conflicts_with_message(file.messages, enum_desc.name) {
      push_issue(
        issues,
        "enum." + enum_desc.name,
        "top-level enum name conflicts with message name",
      )
    }
  }
  if issues.length() == 0 {
    SchemaValid
  } else {
    SchemaInvalid(issues)
  }
}

///|
pub fn schema_is_valid(file : ProtoFile) -> Bool {
  match validate_proto_file(file) {
    SchemaValid => true
    SchemaInvalid(_) => false
  }
}
