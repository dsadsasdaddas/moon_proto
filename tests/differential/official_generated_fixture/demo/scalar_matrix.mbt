// Fixture representing salient snippets from moonbitlang/protoc-gen-mbt output.
pub struct ScalarMatrix {
  d : Double
  f : Float
  i32 : Int
  i64 : Int64
  u32 : UInt
  u64 : UInt64
  s32 : Int
  s64 : Int64
  fixed32_value : UInt
  fixed64_value : UInt64
  sfixed32_value : Int
  sfixed64_value : Int64
  active : Bool
  name : String
  payload : Bytes
  note : Option[String]
  samples : Array[UInt]
}
