///|
fn usage() -> String {
  let text =
    #|moon_proto CLI
    #|
    #|Usage:
    #|  moon run cmd/main -- gen --example
    #|  moon run cmd/main -- gen --schema '<proto3 source>'
    #|
    #|Commands:
    #|  gen --example         Generate MoonBit source for a built-in demo schema.
    #|  gen --schema <text>   Parse, validate, and generate MoonBit source from inline proto3 text.
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
fn generate(schema : String) -> Unit {
  match @proto.parse_proto(schema) {
    @proto.ProtoErr(_) => println("error: failed to parse proto3 schema")
    @proto.ProtoOk(file) =>
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
    (Some("--help"), _, _) | (Some("help"), _, _) | (None, _, _) =>
      println(usage())
    _ => println(usage())
  }
}
