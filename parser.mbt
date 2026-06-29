///|
/// Tokens for a deliberately small proto3 parser.
pub(all) enum ProtoToken {
  Ident(String)
  IntLit(Int)
  StrLit(String)
  Sym(String)
} derive(Debug, Eq)

///|
/// Parser error type for schema parsing.
pub(all) enum SchemaError {
  Expected(String)
  UnexpectedEofInSchema
} derive(Debug, Eq)

///|
/// Result of parsing a proto file.
pub(all) enum ParseProtoResult {
  ProtoOk(ProtoFile)
  ProtoErr(SchemaError)
} derive(Debug, Eq)

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_alpha(c) || is_digit(c) || c == '_'
}

///|
/// Lex a useful proto3 subset: identifiers, integers, strings and punctuation.
pub fn lex_proto(src : String) -> Array[ProtoToken] {
  let chars = src.to_array()
  let toks : Array[ProtoToken] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      i = i + 1
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '/' {
      i = i + 2
      while i < chars.length() && chars[i] != '\n' {
        i = i + 1
      }
    } else if is_alpha(c) || c == '_' {
      let start = i
      i = i + 1
      while i < chars.length() && is_ident_char(chars[i]) {
        i = i + 1
      }
      toks.push(Ident(src[start:i].to_owned()))
    } else if is_digit(c) {
      let mut value = 0
      while i < chars.length() && is_digit(chars[i]) {
        value = value * 10 + (chars[i].to_int() - '0'.to_int())
        i = i + 1
      }
      toks.push(IntLit(value))
    } else if c == '"' {
      i = i + 1
      let buf : Array[Char] = []
      while i < chars.length() && chars[i] != '"' {
        buf.push(chars[i])
        i = i + 1
      }
      if i < chars.length() && chars[i] == '"' {
        i = i + 1
      }
      toks.push(StrLit(String::from_iter(buf.iter())))
    } else {
      toks.push(Sym(c.to_string()))
      i = i + 1
    }
  }
  toks
}

///|
priv struct ProtoParser {
  tokens : Array[ProtoToken]
  mut i : Int
}

///|
fn ProtoParser::peek(self : ProtoParser) -> ProtoToken? {
  if self.i < self.tokens.length() {
    Some(self.tokens[self.i])
  } else {
    None
  }
}

///|
fn ProtoParser::advance(self : ProtoParser) -> ProtoToken? {
  let t = self.peek()
  self.i = self.i + 1
  t
}

///|
fn ProtoParser::consume_ident(self : ProtoParser) -> String? {
  match self.advance() {
    Some(Ident(s)) => Some(s)
    _ => None
  }
}

///|
fn ProtoParser::consume_int(self : ProtoParser) -> Int? {
  match self.advance() {
    Some(IntLit(n)) => Some(n)
    _ => None
  }
}

///|
fn ProtoParser::consume_string(self : ProtoParser) -> String? {
  match self.advance() {
    Some(StrLit(s)) => Some(s)
    _ => None
  }
}

///|
fn ProtoParser::consume_sym(self : ProtoParser, wanted : String) -> Bool {
  match self.advance() {
    Some(Sym(s)) => s == wanted
    _ => false
  }
}

///|
fn ProtoParser::match_sym(self : ProtoParser, wanted : String) -> Bool {
  match self.peek() {
    Some(Sym(s)) =>
      if s == wanted {
        let _ = self.advance()
        true
      } else {
        false
      }
    _ => false
  }
}

///|
fn ProtoParser::parse_qualified_name(self : ProtoParser) -> String? {
  let mut out = ""
  if self.match_sym(".") {
    out = "."
  }
  match self.consume_ident() {
    Some(first) => out = out + first
    None => return None
  }
  let mut done = false
  while !done {
    match self.peek() {
      Some(Sym(".")) => {
        let _ = self.advance()
        match self.consume_ident() {
          Some(part) => out = out + "." + part
          None => return None
        }
      }
      _ => done = true
    }
  }
  Some(out)
}

///|
fn ProtoParser::skip_bracketed_options(self : ProtoParser) -> Bool {
  if !self.match_sym("[") {
    return true
  }
  let mut depth = 1
  while depth > 0 {
    match self.advance() {
      Some(Sym("[")) => depth = depth + 1
      Some(Sym("]")) => depth = depth - 1
      Some(_) => ()
      None => return false
    }
  }
  true
}

///|
fn ProtoParser::skip_until_semicolon(self : ProtoParser) -> Bool {
  let mut bracket_depth = 0
  let mut brace_depth = 0
  while self.i < self.tokens.length() {
    match self.advance() {
      Some(Sym("[")) => bracket_depth = bracket_depth + 1
      Some(Sym("]")) =>
        if bracket_depth > 0 {
          bracket_depth = bracket_depth - 1
        }
      Some(Sym("{")) => brace_depth = brace_depth + 1
      Some(Sym("}")) =>
        if brace_depth == 0 && bracket_depth == 0 {
          self.i = self.i - 1
          return true
        } else if brace_depth > 0 {
          brace_depth = brace_depth - 1
        }
      Some(Sym(";")) =>
        if bracket_depth == 0 && brace_depth == 0 {
          return true
        }
      Some(_) => ()
      None => return false
    }
  }
  true
}

///|
fn ProtoParser::parse_field(self : ProtoParser) -> FieldDescriptor? {
  let mut label = Singular
  let typ_name = match self.peek() {
    Some(Ident("repeated")) => {
      let _ = self.advance()
      label = Repeated
      match self.parse_qualified_name() {
        Some(t) => t
        None => return None
      }
    }
    Some(Ident("optional")) => {
      let _ = self.advance()
      label = Optional
      match self.parse_qualified_name() {
        Some(t) => t
        None => return None
      }
    }
    _ =>
      match self.parse_qualified_name() {
        Some(t) => t
        None => return None
      }
  }
  let typ = if typ_name == "map" {
    if label != Singular {
      return None
    }
    if !self.consume_sym("<") {
      return None
    }
    let key_typ = match self.consume_ident() {
      Some(t) => scalar_type_from_string(t)
      None => return None
    }
    if !self.consume_sym(",") {
      return None
    }
    let value_typ = match self.parse_qualified_name() {
      Some(t) => scalar_type_from_string(t)
      None => return None
    }
    if !self.consume_sym(">") {
      return None
    }
    label = Repeated
    MapType(key_typ, value_typ)
  } else {
    scalar_type_from_string(typ_name)
  }
  let name = match self.consume_ident() {
    Some(n) => n
    None => return None
  }
  if !self.consume_sym("=") {
    return None
  }
  let number = match self.consume_int() {
    Some(n) => n
    None => return None
  }
  if !self.skip_bracketed_options() {
    return None
  }
  let _ = self.match_sym(";")
  Some(FieldDescriptor::{ name, typ, number, label })
}

///|
fn ProtoParser::parse_oneof_fields(
  self : ProtoParser,
) -> Array[FieldDescriptor]? {
  let group = match self.consume_ident() {
    Some(n) => n
    None => return None
  }
  if !self.consume_sym("{") {
    return None
  }
  let fields : Array[FieldDescriptor] = []
  let mut done = false
  while !done {
    match self.peek() {
      Some(Sym(s)) =>
        if s == "}" {
          let _ = self.advance()
          done = true
        } else if s == "." {
          match self.parse_field() {
            Some(f) =>
              if f.label == Singular {
                fields.push(FieldDescriptor::{ ..f, label: Oneof(group) })
              } else {
                return None
              }
            None => return None
          }
        } else {
          return None
        }
      Some(_) =>
        match self.parse_field() {
          Some(f) =>
            if f.label == Singular {
              fields.push(FieldDescriptor::{ ..f, label: Oneof(group) })
            } else {
              return None
            }
          None => return None
        }
      None => return None
    }
  }
  Some(fields)
}

///|
fn ProtoParser::parse_message(self : ProtoParser) -> MessageDescriptor? {
  let name = match self.consume_ident() {
    Some(n) => n
    None => return None
  }
  if !self.consume_sym("{") {
    return None
  }
  let fields : Array[FieldDescriptor] = []
  let mut done = false
  while !done {
    match self.peek() {
      Some(Sym(s)) =>
        if s == "}" {
          let _ = self.advance()
          done = true
        } else if s == "." {
          match self.parse_field() {
            Some(f) => fields.push(f)
            None => return None
          }
        } else {
          return None
        }
      Some(Ident(word)) =>
        if word == "oneof" {
          let _ = self.advance()
          match self.parse_oneof_fields() {
            None => return None
            Some(oneof_fields) =>
              for f in oneof_fields {
                fields.push(f)
              }
          }
        } else if word == "option" || word == "reserved" || word == "extensions" {
          let _ = self.advance()
          if !self.skip_until_semicolon() {
            return None
          }
        } else {
          match self.parse_field() {
            Some(f) => fields.push(f)
            None => return None
          }
        }
      Some(_) => return None
      None => return None
    }
  }
  Some(MessageDescriptor::{ name, fields })
}

///|
fn ProtoParser::parse_enum_value(self : ProtoParser) -> EnumValueDescriptor? {
  let name = match self.consume_ident() {
    Some(n) => n
    None => return None
  }
  if !self.consume_sym("=") {
    return None
  }
  let number = match self.consume_int() {
    Some(n) => n
    None => return None
  }
  if !self.skip_bracketed_options() {
    return None
  }
  let _ = self.match_sym(";")
  Some(EnumValueDescriptor::{ name, number })
}

///|
fn ProtoParser::parse_enum(self : ProtoParser) -> EnumDescriptor? {
  let name = match self.consume_ident() {
    Some(n) => n
    None => return None
  }
  if !self.consume_sym("{") {
    return None
  }
  let values : Array[EnumValueDescriptor] = []
  let mut done = false
  while !done {
    match self.peek() {
      Some(Sym(s)) =>
        if s == "}" {
          let _ = self.advance()
          done = true
        } else {
          return None
        }
      Some(Ident(word)) =>
        if word == "option" || word == "reserved" {
          let _ = self.advance()
          if !self.skip_until_semicolon() {
            return None
          }
        } else {
          match self.parse_enum_value() {
            Some(v) => values.push(v)
            None => return None
          }
        }
      Some(_) =>
        match self.parse_enum_value() {
          Some(v) => values.push(v)
          None => return None
        }
      None => return None
    }
  }
  Some(EnumDescriptor::{ name, values })
}

///|
fn is_top_level_enum(enums : Array[EnumDescriptor], name : String) -> Bool {
  for e in enums {
    if e.name == name {
      return true
    }
  }
  false
}

///|
fn resolve_type(typ : ScalarType, enums : Array[EnumDescriptor]) -> ScalarType {
  match typ {
    NamedType(name) =>
      if is_top_level_enum(enums, name) {
        EnumType(name)
      } else {
        NamedType(name)
      }
    MapType(key_typ, value_typ) =>
      MapType(resolve_type(key_typ, enums), resolve_type(value_typ, enums))
    other => other
  }
}

///|
fn resolve_message_types(
  messages : Array[MessageDescriptor],
  enums : Array[EnumDescriptor],
) -> Array[MessageDescriptor] {
  let out : Array[MessageDescriptor] = []
  for msg in messages {
    let fields : Array[FieldDescriptor] = []
    for field in msg.fields {
      fields.push(FieldDescriptor::{
        ..field,
        typ: resolve_type(field.typ, enums),
      })
    }
    out.push(MessageDescriptor::{ name: msg.name, fields })
  }
  out
}

///|
/// Parse a proto3 subset: syntax/package declarations, messages, fields and
/// top-level enums.
pub fn parse_proto(src : String) -> ParseProtoResult {
  let p = ProtoParser::{ tokens: lex_proto(src), i: 0 }
  let mut syntax = "proto3"
  let mut package_name = ""
  let messages : Array[MessageDescriptor] = []
  let enums : Array[EnumDescriptor] = []
  while p.i < p.tokens.length() {
    match p.consume_ident() {
      Some("syntax") => {
        if !p.consume_sym("=") {
          return ProtoErr(Expected("="))
        }
        match p.consume_string() {
          Some(s) => syntax = s
          None => return ProtoErr(Expected("syntax string"))
        }
        let _ = p.consume_sym(";")
      }
      Some("package") => {
        match p.parse_qualified_name() {
          Some(s) => package_name = s
          None => return ProtoErr(Expected("package name"))
        }
        let _ = p.consume_sym(";")
      }
      Some("import") => {
        if !p.skip_until_semicolon() {
          return ProtoErr(Expected("import statement"))
        }
      }
      Some("option") => {
        if !p.skip_until_semicolon() {
          return ProtoErr(Expected("option statement"))
        }
      }
      Some("message") =>
        match p.parse_message() {
          Some(m) => messages.push(m)
          None => return ProtoErr(Expected("message"))
        }
      Some("enum") =>
        match p.parse_enum() {
          Some(e) => enums.push(e)
          None => return ProtoErr(Expected("enum"))
        }
      Some(other) => return ProtoErr(Expected("top-level item, got " + other))
      None => return ProtoErr(UnexpectedEofInSchema)
    }
  }
  ProtoOk(ProtoFile::{
    syntax,
    package_name,
    messages: resolve_message_types(messages, enums),
    enums,
  })
}
