// Fixture representing salient snippets from moonbitlang/protoc-gen-mbt output.
pub enum Severity {
  SEVERITY_UNSPECIFIED
  INFO
  WARN
  ERROR
}

pub struct TelemetryEvent {
  id : String
  severity : Severity
  message : Option[String]
  attributes : Map[String, String]
}
