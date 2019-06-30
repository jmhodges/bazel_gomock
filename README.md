gomock for Bazel
================

This skylark code allows you to generate code with `mockgen` (from
[`golang/mock`](https://github.com/golang/mock)) and use that code as a dependency in
your bazel projects. It handles all the `GOPATH` stuff for you.

`bazel_gomock` requires a `rules_go` external to be set up in your `WORKSPACE`
as well as a go_repository setup for `com_github_golang_mock` (unless you
override an argument; see below).

You call it in your BUILD files as

```python
gomock(
    name = "mock_sess",
    out = "mock_sess_test.go",
    interfaces = ["SessionsClient"],
    library = "//proto/sessions/sessproto:go_default_library",
    package = "main",
)
```

where `library` is a `go_library` target, `interfaces` is the list of names of
the Go interfaces you'd like `mockgen` to generate mocks of, `package` is the
name of the Go package at the top of the generated file (in this example,
`package "main"`), and `out` is the path of generated source file that will be
made.

There is also a `source` parameter described below.

You use this target's `out` file directly in the `srcs` parameter in `go_test`,
`go_library`, and so on. So, when the above example `gomock` call is used in the
same BUILD file, you put `mock_sess_test.go` in the `srcs` parameter like so:


```python
go_test(
    name = "go_default_test",
    srcs = [
         "cool_test.go",
         "mock_sess_test.go",
    ],
    embed = [":go_default_library"]
    ...
)
```

If you need to generate mocks from a specific Go file instead of a
import path (say, because the `go_library` you have is a `main` package and is
therefore unreflectable by Go tools and specifically unimportable by `mockgen`),
add the `source` parameter with the location of source file. E.g. `source =
"//fancy/path:foo.go"` or just `source = "foo.go"` if the file is in the same
directory). The `library` parameter must still be set to the library that source
file lives in so that any referenced dependencies can be pulled into the Go
path.

Also, `gazelle` will remove the generated source file from a `go_test` target's
`srcs` unless you end the generated file name with `_test.go`.

As a likely unused feature, you can pass in an alternative
external for where to find the `mockgen` tool target using the `mockgen_tool`
parameter. The only rule for the target is that must be a binary. The current
default is `"@com_github_golang_mock//mockgen"`.

If you try to use `gomock` on a `go_library` that is in the package `main` (and so
probably being immediately used as an `embed` target for a `go_binary`), you'll
get an annoying error like:

```
prog.go:13:2: import "your/main/package/deal" is a program, not an importable package
```

You can resolve that by setting the `source` parameter to the location of the
file with the interfaces you want in it.
