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
fn ProtoParser::parse_field(self : ProtoParser) -> FieldDescriptor? {
  let mut label = Singular
  let first = self.consume_ident()
  match first {
    None => None
    Some(word) => {
      let typ_name = if word == "repeated" {
        label = Repeated
        match self.consume_ident() {
          Some(t) => t
          None => return None
        }
      } else if word == "optional" {
        label = Optional
        match self.consume_ident() {
          Some(t) => t
          None => return None
        }
      } else {
        word
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
      let _ = self.consume_sym(";")
      Some(FieldDescriptor::{
        name,
        typ: scalar_type_from_string(typ_name),
        number,
        label,
      })
    }
  }
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
        } else {
          return None
        }
      Some(_) =>
        match self.parse_field() {
          Some(f) => fields.push(f)
          None => return None
        }
      None => return None
    }
  }
  Some(MessageDescriptor::{ name, fields })
}

///|
/// Parse a proto3 subset: syntax/package declarations and message fields.
pub fn parse_proto(src : String) -> ParseProtoResult {
  let p = ProtoParser::{ tokens: lex_proto(src), i: 0 }
  let mut syntax = "proto3"
  let mut package_name = ""
  let messages : Array[MessageDescriptor] = []
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
        match p.consume_ident() {
          Some(s) => package_name = s
          None => return ProtoErr(Expected("package name"))
        }
        let _ = p.consume_sym(";")
      }
      Some("message") =>
        match p.parse_message() {
          Some(m) => messages.push(m)
          None => return ProtoErr(Expected("message"))
        }
      Some(other) => return ProtoErr(Expected("top-level item, got " + other))
      None => return ProtoErr(UnexpectedEofInSchema)
    }
  }
  ProtoOk(ProtoFile::{ syntax, package_name, messages })
}
