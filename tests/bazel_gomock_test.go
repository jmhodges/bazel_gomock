package main

import (
	"flag"
	"fmt"
	"log"
	"path/filepath"
	"testing"

	"github.com/bazelbuild/rules_go/go/tools/bazel_testing"
)

var gomockBzlPath = flag.String("gomockPath", "", "")

func TestMain(m *testing.M) {
	flag.Parse()
	if *gomockBzlPath == "" {
		log.Fatalf("-gomockPath was blank")
	}
	abs, err := filepath.Abs(*gomockBzlPath)
	if err != nil {
		log.Fatalf("unable to get absolute path of %#v: %s", *gomockBzlPath, err)
	}
	dir := filepath.Dir(abs)
	log.Println("FIXME arg", dir)
	bazel_testing.TestMain(m, bazel_testing.Args{
		WorkspaceSuffix: fmt.Sprintf(`
new_local_repository(
    name = "com_github_jmhodges_bazel_gomock",
    path = %#v,
    workspace_file_content = """
workspace(name = "com_github_jmhodges_bazel_gomock")
""",
    build_file_content = """
exports_files(["gomock.bzl"], visibility = ["//visibility:public"])
""",
)
`, dir),
		Main: `
-- BUILD.bazel --
load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")
load("@io_bazel_rules_go//proto:def.bzl", "go_proto_library")
load("@com_github_jmhodges_bazel_gomock//:gomock.bzl", "gomock")

proto_library(
    name = "foo_proto",
    srcs = ["foo.proto"],
)

go_proto_library(
    name = "foo_go_proto",
    importpath = "example.com/foo",
    proto = ":foo_proto",
)

go_library(
    name = "foo_lib",
    embed = [":foo_go_proto"],
    importpath = "example.com/foo",
)

gomock(
    name = "proto_mock",
    out = "foo_proto_mock.go",
    interfaces = [
        "FooerService",
    ],
    library = ":foo_lib",
    package = "hello",
)

go_library(
    name = "hello",
	srcs = ["hello.go", "proto_mock.go"],
	importpath = "fakeimportpath/hello",
	visibility = ["//visibility:public"],
)

gomock(
    name = "source_mock",
    out = "source_mock_test.go",
    interfaces = [
        "simpleOne",
        "simpleTwo",
    ],
    library = ":go_default_library",
    package = "hello",
    source = "hello.go",
)

go_test(
    name = "go_default_test",
    srcs = [
        "main_test.go",
        "source_mock_test.go"
    ],
)
-- foo.proto --
syntax = "proto3";

package fooproto

service Fooer {
  rpc DoIt(Thing thing) returns (FooResponse) {}
}

message Thing {
  string bar = 1;
}

message FooResponse {
  bool okay = 1;
}
-- hello.go --
package hello

import "fmt"

func A() string { return fmt.Sprintf("hello is %d", 12) }
-- main_test.go --
packcage main

import "testing"

func TestOkay(t *testing.T) {
	t.Logf("hello")
}
`,
	})
}

func TestGoldenPath(t *testing.T) {
	if err := bazel_testing.RunBazel("build", "test", "//:go_default_test"); err != nil {
		t.Fatalf("unable to run go_default_test tests:\n%s", err)
	}
}
