package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"runtime"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protodesc"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/descriptorpb"
	"google.golang.org/protobuf/types/dynamicpb"
)

func str(value string) *string { return &value }
func i32(value int32) *int32   { return &value }
func label(value descriptorpb.FieldDescriptorProto_Label) *descriptorpb.FieldDescriptorProto_Label {
	return &value
}
func typ(value descriptorpb.FieldDescriptorProto_Type) *descriptorpb.FieldDescriptorProto_Type {
	return &value
}

func field(
	name string,
	number int32,
	fieldType descriptorpb.FieldDescriptorProto_Type,
	fieldLabel descriptorpb.FieldDescriptorProto_Label,
) *descriptorpb.FieldDescriptorProto {
	return &descriptorpb.FieldDescriptorProto{
		Name:   str(name),
		Number: i32(number),
		Label:  label(fieldLabel),
		Type:   typ(fieldType),
	}
}

func repoRoot() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		panic("cannot locate oracle source file")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
}

func makeUserDescriptor() protoreflect.MessageDescriptor {
	optional := descriptorpb.FieldDescriptorProto_LABEL_OPTIONAL
	repeated := descriptorpb.FieldDescriptorProto_LABEL_REPEATED
	file := &descriptorpb.FileDescriptorProto{
		Name:    str("moon_proto_oracle.proto"),
		Package: str("demo"),
		Syntax:  str("proto3"),
		MessageType: []*descriptorpb.DescriptorProto{
			{
				Name: str("User"),
				Field: []*descriptorpb.FieldDescriptorProto{
					field("id", 1, descriptorpb.FieldDescriptorProto_TYPE_UINT64, optional),
					field("name", 2, descriptorpb.FieldDescriptorProto_TYPE_STRING, optional),
					field("active", 3, descriptorpb.FieldDescriptorProto_TYPE_BOOL, optional),
					field("tags", 4, descriptorpb.FieldDescriptorProto_TYPE_STRING, repeated),
					field("score", 5, descriptorpb.FieldDescriptorProto_TYPE_SINT64, optional),
					field("blob", 6, descriptorpb.FieldDescriptorProto_TYPE_BYTES, optional),
					field("samples", 7, descriptorpb.FieldDescriptorProto_TYPE_UINT64, repeated),
					field("deltas", 8, descriptorpb.FieldDescriptorProto_TYPE_SINT64, repeated),
				},
			},
		},
	}
	files, err := protodesc.NewFiles(&descriptorpb.FileDescriptorSet{
		File: []*descriptorpb.FileDescriptorProto{file},
	})
	if err != nil {
		panic(err)
	}
	desc, err := files.FindDescriptorByName("demo.User")
	if err != nil {
		panic(err)
	}
	return desc.(protoreflect.MessageDescriptor)
}

func makeUserMessage() proto.Message {
	desc := makeUserDescriptor()
	message := dynamicpb.NewMessageType(desc).New()
	fields := desc.Fields()
	message.Set(fields.ByName("id"), protoreflect.ValueOfUint64(150))
	message.Set(fields.ByName("name"), protoreflect.ValueOfString("Alice \"A\""))
	message.Set(fields.ByName("active"), protoreflect.ValueOfBool(true))
	message.Set(fields.ByName("score"), protoreflect.ValueOfInt64(-2))
	message.Set(fields.ByName("blob"), protoreflect.ValueOfBytes([]byte{0xff, 0x00}))

	tags := message.Mutable(fields.ByName("tags")).List()
	tags.Append(protoreflect.ValueOfString("admin"))
	tags.Append(protoreflect.ValueOfString("tester"))

	samples := message.Mutable(fields.ByName("samples")).List()
	samples.Append(protoreflect.ValueOfUint64(1))
	samples.Append(protoreflect.ValueOfUint64(150))

	deltas := message.Mutable(fields.ByName("deltas")).List()
	deltas.Append(protoreflect.ValueOfInt64(-1))
	deltas.Append(protoreflect.ValueOfInt64(2))
	return message.Interface()
}

func oracleValues() ([]byte, string, string) {
	message := makeUserMessage()
	binary, err := proto.MarshalOptions{Deterministic: true}.Marshal(message)
	if err != nil {
		panic(err)
	}
	jsonBytes, err := protojson.MarshalOptions{UseProtoNames: true}.Marshal(message)
	if err != nil {
		panic(err)
	}
	return binary, hex.EncodeToString(binary) + "\n", string(jsonBytes) + "\n"
}

func verifyFile(path string, expected []byte) error {
	actual, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if !bytes.Equal(actual, expected) {
		return fmt.Errorf("fixture mismatch: %s", path)
	}
	return nil
}

func verifyJSONFile(path string, expected []byte) error {
	actual, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var actualValue any
	var expectedValue any
	if err := json.Unmarshal(actual, &actualValue); err != nil {
		return err
	}
	if err := json.Unmarshal(expected, &expectedValue); err != nil {
		return err
	}
	if !reflect.DeepEqual(actualValue, expectedValue) {
		return fmt.Errorf("JSON fixture mismatch: %s", path)
	}
	return nil
}

func main() {
	root := repoRoot()
	binary, hexText, jsonText := oracleValues()
	checks := map[string][]byte{
		filepath.Join(root, "tests", "fixtures", "user_full.bin"): binary,
		filepath.Join(root, "tests", "fixtures", "user_full.hex"): []byte(hexText),
	}
	for path, expected := range checks {
		if err := verifyFile(path, expected); err != nil {
			panic(err)
		}
	}
	if err := verifyJSONFile(filepath.Join(root, "tests", "fixtures", "user_full.json"), []byte(jsonText)); err != nil {
		panic(err)
	}
	fmt.Println("Go protobuf oracle fixtures verified")
	fmt.Println("user_full.hex", hexText[:len(hexText)-1])
	fmt.Println("user_full.json", jsonText[:len(jsonText)-1])
}
