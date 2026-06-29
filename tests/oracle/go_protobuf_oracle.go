package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
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

func messageField(
	name string,
	number int32,
	typeName string,
	fieldLabel descriptorpb.FieldDescriptorProto_Label,
) *descriptorpb.FieldDescriptorProto {
	field := field(name, number, descriptorpb.FieldDescriptorProto_TYPE_MESSAGE, fieldLabel)
	field.TypeName = str(typeName)
	return field
}

func oneofField(
	name string,
	number int32,
	fieldType descriptorpb.FieldDescriptorProto_Type,
	fieldLabel descriptorpb.FieldDescriptorProto_Label,
	oneofIndex int32,
) *descriptorpb.FieldDescriptorProto {
	field := field(name, number, fieldType, fieldLabel)
	field.OneofIndex = i32(oneofIndex)
	return field
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

func makeBagDescriptor() protoreflect.MessageDescriptor {
	optional := descriptorpb.FieldDescriptorProto_LABEL_OPTIONAL
	repeated := descriptorpb.FieldDescriptorProto_LABEL_REPEATED
	file := &descriptorpb.FileDescriptorProto{
		Name:    str("moon_proto_map_oracle.proto"),
		Package: str("demo"),
		Syntax:  str("proto3"),
		MessageType: []*descriptorpb.DescriptorProto{
			{
				Name: str("Bag"),
				Field: []*descriptorpb.FieldDescriptorProto{
					messageField("scores", 1, ".demo.Bag.ScoresEntry", repeated),
					messageField("labels", 2, ".demo.Bag.LabelsEntry", repeated),
				},
				NestedType: []*descriptorpb.DescriptorProto{
					{
						Name: str("ScoresEntry"),
						Field: []*descriptorpb.FieldDescriptorProto{
							field("key", 1, descriptorpb.FieldDescriptorProto_TYPE_STRING, optional),
							field("value", 2, descriptorpb.FieldDescriptorProto_TYPE_UINT64, optional),
						},
						Options: &descriptorpb.MessageOptions{MapEntry: proto.Bool(true)},
					},
					{
						Name: str("LabelsEntry"),
						Field: []*descriptorpb.FieldDescriptorProto{
							field("key", 1, descriptorpb.FieldDescriptorProto_TYPE_INT64, optional),
							field("value", 2, descriptorpb.FieldDescriptorProto_TYPE_STRING, optional),
						},
						Options: &descriptorpb.MessageOptions{MapEntry: proto.Bool(true)},
					},
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
	desc, err := files.FindDescriptorByName("demo.Bag")
	if err != nil {
		panic(err)
	}
	return desc.(protoreflect.MessageDescriptor)
}

func makeBagMessage() proto.Message {
	desc := makeBagDescriptor()
	message := dynamicpb.NewMessageType(desc).New()
	fields := desc.Fields()

	scores := message.Mutable(fields.ByName("scores")).Map()
	scores.Set(protoreflect.ValueOfString("alice").MapKey(), protoreflect.ValueOfUint64(150))
	scores.Set(protoreflect.ValueOfString("bob").MapKey(), protoreflect.ValueOfUint64(7))

	labels := message.Mutable(fields.ByName("labels")).Map()
	labels.Set(protoreflect.ValueOfInt64(2).MapKey(), protoreflect.ValueOfString("two"))
	labels.Set(protoreflect.ValueOfInt64(7).MapKey(), protoreflect.ValueOfString("seven"))
	return message.Interface()
}

func makeContactDescriptor() protoreflect.MessageDescriptor {
	optional := descriptorpb.FieldDescriptorProto_LABEL_OPTIONAL
	file := &descriptorpb.FileDescriptorProto{
		Name:    str("moon_proto_oneof_oracle.proto"),
		Package: str("demo"),
		Syntax:  str("proto3"),
		MessageType: []*descriptorpb.DescriptorProto{
			{
				Name: str("Contact"),
				Field: []*descriptorpb.FieldDescriptorProto{
					field("id", 1, descriptorpb.FieldDescriptorProto_TYPE_UINT64, optional),
					oneofField("email", 2, descriptorpb.FieldDescriptorProto_TYPE_STRING, optional, 0),
					oneofField("phone", 3, descriptorpb.FieldDescriptorProto_TYPE_STRING, optional, 0),
				},
				OneofDecl: []*descriptorpb.OneofDescriptorProto{
					{Name: str("reach")},
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
	desc, err := files.FindDescriptorByName("demo.Contact")
	if err != nil {
		panic(err)
	}
	return desc.(protoreflect.MessageDescriptor)
}

func makeContactMessage() proto.Message {
	desc := makeContactDescriptor()
	message := dynamicpb.NewMessageType(desc).New()
	fields := desc.Fields()
	message.Set(fields.ByName("id"), protoreflect.ValueOfUint64(1))
	message.Set(fields.ByName("phone"), protoreflect.ValueOfString("123"))
	return message.Interface()
}

func makeNumbers32Descriptor() protoreflect.MessageDescriptor {
	optional := descriptorpb.FieldDescriptorProto_LABEL_OPTIONAL
	file := &descriptorpb.FileDescriptorProto{
		Name:    str("moon_proto_numbers32_oracle.proto"),
		Package: str("demo"),
		Syntax:  str("proto3"),
		MessageType: []*descriptorpb.DescriptorProto{
			{
				Name: str("Numbers32"),
				Field: []*descriptorpb.FieldDescriptorProto{
					field("u", 1, descriptorpb.FieldDescriptorProto_TYPE_UINT32, optional),
					field("i", 2, descriptorpb.FieldDescriptorProto_TYPE_INT32, optional),
					field("s", 3, descriptorpb.FieldDescriptorProto_TYPE_SINT32, optional),
					field("f", 4, descriptorpb.FieldDescriptorProto_TYPE_FIXED32, optional),
					field("sf", 5, descriptorpb.FieldDescriptorProto_TYPE_SFIXED32, optional),
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
	desc, err := files.FindDescriptorByName("demo.Numbers32")
	if err != nil {
		panic(err)
	}
	return desc.(protoreflect.MessageDescriptor)
}

func makeNumbers32Message() proto.Message {
	desc := makeNumbers32Descriptor()
	message := dynamicpb.NewMessageType(desc).New()
	fields := desc.Fields()
	message.Set(fields.ByName("u"), protoreflect.ValueOfUint32(4294967295))
	message.Set(fields.ByName("i"), protoreflect.ValueOfInt32(-1))
	message.Set(fields.ByName("s"), protoreflect.ValueOfInt32(-2))
	message.Set(fields.ByName("f"), protoreflect.ValueOfUint32(4294967295))
	message.Set(fields.ByName("sf"), protoreflect.ValueOfInt32(-3))
	return message.Interface()
}

func makeFloatsDescriptor() protoreflect.MessageDescriptor {
	optional := descriptorpb.FieldDescriptorProto_LABEL_OPTIONAL
	file := &descriptorpb.FileDescriptorProto{
		Name:    str("moon_proto_floats_oracle.proto"),
		Package: str("demo"),
		Syntax:  str("proto3"),
		MessageType: []*descriptorpb.DescriptorProto{
			{
				Name: str("Floats"),
				Field: []*descriptorpb.FieldDescriptorProto{
					field("f", 1, descriptorpb.FieldDescriptorProto_TYPE_FLOAT, optional),
					field("d", 2, descriptorpb.FieldDescriptorProto_TYPE_DOUBLE, optional),
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
	desc, err := files.FindDescriptorByName("demo.Floats")
	if err != nil {
		panic(err)
	}
	return desc.(protoreflect.MessageDescriptor)
}

func makeFloatsMessage() proto.Message {
	desc := makeFloatsDescriptor()
	message := dynamicpb.NewMessageType(desc).New()
	fields := desc.Fields()
	message.Set(fields.ByName("f"), protoreflect.ValueOfFloat32(1.5))
	message.Set(fields.ByName("d"), protoreflect.ValueOfFloat64(-2.25))
	return message.Interface()
}

func makeFloatSpecialsDescriptor() protoreflect.MessageDescriptor {
	optional := descriptorpb.FieldDescriptorProto_LABEL_OPTIONAL
	file := &descriptorpb.FileDescriptorProto{
		Name:    str("moon_proto_float_specials_oracle.proto"),
		Package: str("demo"),
		Syntax:  str("proto3"),
		MessageType: []*descriptorpb.DescriptorProto{
			{
				Name: str("FloatSpecials"),
				Field: []*descriptorpb.FieldDescriptorProto{
					field("f_nan", 1, descriptorpb.FieldDescriptorProto_TYPE_FLOAT, optional),
					field("f_inf", 2, descriptorpb.FieldDescriptorProto_TYPE_FLOAT, optional),
					field("d_neg_inf", 3, descriptorpb.FieldDescriptorProto_TYPE_DOUBLE, optional),
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
	desc, err := files.FindDescriptorByName("demo.FloatSpecials")
	if err != nil {
		panic(err)
	}
	return desc.(protoreflect.MessageDescriptor)
}

func makeFloatSpecialsMessage() proto.Message {
	desc := makeFloatSpecialsDescriptor()
	message := dynamicpb.NewMessageType(desc).New()
	fields := desc.Fields()
	message.Set(fields.ByName("f_nan"), protoreflect.ValueOfFloat32(math.Float32frombits(0x7fc00000)))
	message.Set(fields.ByName("f_inf"), protoreflect.ValueOfFloat32(float32(math.Inf(1))))
	message.Set(fields.ByName("d_neg_inf"), protoreflect.ValueOfFloat64(math.Inf(-1)))
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

func bagOracleValues() ([]byte, string, string) {
	message := makeBagMessage()
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

func contactOracleValues() ([]byte, string, string) {
	message := makeContactMessage()
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

func numbers32OracleValues() ([]byte, string, string) {
	message := makeNumbers32Message()
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

func floatsOracleValues() ([]byte, string, string) {
	message := makeFloatsMessage()
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

func floatSpecialsOracleValues() ([]byte, string, string) {
	message := makeFloatSpecialsMessage()
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
	bagBinary, bagHexText, bagJSONText := bagOracleValues()
	contactBinary, contactHexText, contactJSONText := contactOracleValues()
	numbers32Binary, numbers32HexText, numbers32JSONText := numbers32OracleValues()
	floatsBinary, floatsHexText, floatsJSONText := floatsOracleValues()
	specialsBinary, specialsHexText, specialsJSONText := floatSpecialsOracleValues()
	checks := map[string][]byte{
		filepath.Join(root, "tests", "fixtures", "user_full.bin"):      binary,
		filepath.Join(root, "tests", "fixtures", "user_full.hex"):      []byte(hexText),
		filepath.Join(root, "tests", "fixtures", "bag_maps.bin"):       bagBinary,
		filepath.Join(root, "tests", "fixtures", "bag_maps.hex"):       []byte(bagHexText),
		filepath.Join(root, "tests", "fixtures", "contact_oneof.bin"):  contactBinary,
		filepath.Join(root, "tests", "fixtures", "contact_oneof.hex"):  []byte(contactHexText),
		filepath.Join(root, "tests", "fixtures", "numbers32.bin"):      numbers32Binary,
		filepath.Join(root, "tests", "fixtures", "numbers32.hex"):      []byte(numbers32HexText),
		filepath.Join(root, "tests", "fixtures", "floats.bin"):         floatsBinary,
		filepath.Join(root, "tests", "fixtures", "floats.hex"):         []byte(floatsHexText),
		filepath.Join(root, "tests", "fixtures", "float_specials.bin"): specialsBinary,
		filepath.Join(root, "tests", "fixtures", "float_specials.hex"): []byte(specialsHexText),
	}
	for path, expected := range checks {
		if err := verifyFile(path, expected); err != nil {
			panic(err)
		}
	}
	if err := verifyJSONFile(filepath.Join(root, "tests", "fixtures", "user_full.json"), []byte(jsonText)); err != nil {
		panic(err)
	}
	if err := verifyJSONFile(filepath.Join(root, "tests", "fixtures", "bag_maps.json"), []byte(bagJSONText)); err != nil {
		panic(err)
	}
	if err := verifyJSONFile(filepath.Join(root, "tests", "fixtures", "contact_oneof.json"), []byte(contactJSONText)); err != nil {
		panic(err)
	}
	if err := verifyJSONFile(filepath.Join(root, "tests", "fixtures", "numbers32.json"), []byte(numbers32JSONText)); err != nil {
		panic(err)
	}
	if err := verifyJSONFile(filepath.Join(root, "tests", "fixtures", "floats.json"), []byte(floatsJSONText)); err != nil {
		panic(err)
	}
	if err := verifyJSONFile(filepath.Join(root, "tests", "fixtures", "float_specials.json"), []byte(specialsJSONText)); err != nil {
		panic(err)
	}
	fmt.Println("Go protobuf oracle fixtures verified")
	fmt.Println("user_full.hex", hexText[:len(hexText)-1])
	fmt.Println("user_full.json", jsonText[:len(jsonText)-1])
	fmt.Println("bag_maps.hex", bagHexText[:len(bagHexText)-1])
	fmt.Println("bag_maps.json", bagJSONText[:len(bagJSONText)-1])
	fmt.Println("contact_oneof.hex", contactHexText[:len(contactHexText)-1])
	fmt.Println("contact_oneof.json", contactJSONText[:len(contactJSONText)-1])
	fmt.Println("numbers32.hex", numbers32HexText[:len(numbers32HexText)-1])
	fmt.Println("numbers32.json", numbers32JSONText[:len(numbers32JSONText)-1])
	fmt.Println("floats.hex", floatsHexText[:len(floatsHexText)-1])
	fmt.Println("floats.json", floatsJSONText[:len(floatsJSONText)-1])
	fmt.Println("float_specials.hex", specialsHexText[:len(specialsHexText)-1])
	fmt.Println("float_specials.json", specialsJSONText[:len(specialsJSONText)-1])
}
