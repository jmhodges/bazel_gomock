package main

import (
	"bytes"
	"flag"
	"io/ioutil"
	"testing"

	"github.com/bazelbuild/rules_go/go/tools/bazel"
	"github.com/golang/mock/gomock"
	"github.com/google/go-cmp/cmp"
)

var (
	srcWithCopyright = flag.String("srcWithCopyright", "", "generated gomock code with copyright prefix")
	copyrightFile    = flag.String("copyright", "", "file with contents of the prefix we should see in srcWithCopyright's file")
)

func TestGoldenPath(t *testing.T) {
	ctrl := gomock.NewController(t)
	m := NewMockHelloer(ctrl)
	m.EXPECT().Hello().Return("hey")
	m.Hello()

	m2 := NewMockSourceHelloer(ctrl)
	m2.EXPECT().Hello().Return("hey")
	m2.Hello()

	m3 := NewMockRenamedReflectHelloer(ctrl)
	m3.EXPECT().Hello().Return("hey")
	m3.Hello()

	defer ctrl.Finish()
}

func TestCopyright(t *testing.T) {
	cf, err := bazel.Runfile(*copyrightFile)
	if err != nil {
		t.Fatalf("copyrightFile %#v wasn't found in go_test's data arg", *copyrightFile)
	}
	copyrightPrefix, err := ioutil.ReadFile(cf)
	if err != nil {
		t.Fatalf("copyrightFile ReadFile: %s", err)
	}
	scf, err := bazel.Runfile(*srcWithCopyright)
	if err != nil {
		t.Fatalf("srcWithCopyright file %#v wasn't found in go_test's data arg", *srcWithCopyright)
	}
	srcContents, err := ioutil.ReadFile(scf)
	if err != nil {
		t.Fatalf("srcWithCopyright ReadFile: %s", err)
	}

	lines := bytes.Split(copyrightPrefix, []byte{'\n'})
	for i, line := range lines {
		if len(line) == 0 {
			continue
		}
		lines[i] = append([]byte("// "), line...)
	}
	commentedPrefix := bytes.Join(lines, []byte{'\n'})
	if !bytes.HasPrefix(srcContents, commentedPrefix) {
		expected := append(commentedPrefix, srcContents...)
		t.Fatalf("generated mock code file %#v did not start with copyright contents of %#v", *srcWithCopyright, *copyrightFile, cmp.Diff(srcContents, expected))
	}
}
