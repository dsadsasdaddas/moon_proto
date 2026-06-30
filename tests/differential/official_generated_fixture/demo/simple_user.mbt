// Fixture representing salient snippets from moonbitlang/protoc-gen-mbt output.
pub struct User {
  id : UInt32
  name : String
  tags : Array[String]
  counters : Map[String, UInt64]
  contact : UserContact?
}

pub enum UserContact {
  Email(String)
  Phone(String)
}

pub fn encode_json(_value : User) -> String {
  "{}"
}
