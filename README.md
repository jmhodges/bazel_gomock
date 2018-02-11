gomock for Bazel
================

This skylark code allows you to generate code with `mockgen` (from
[`golang/mock`](github.com/golang/mock)) and use that code as a dependency in
your bazel projects. It handles all the `GOPATH` stuff for you.

This repo doesn't make it easy to include right now, but the api call you want
is `gomock`. It requires a `rules_go` external to be set up in your `WORKSPACE`
and a go_repository setup for `com_github_golang_mock` (unless you override an
argument; see below).

You call it in your BUILD files as

```
gomock(
    name = "mock_sess",
    out = "mock_sess_test.go",
    interfaces = ["SessionsClient"],
    library = "//proto/sessions/sessproto:go_default_library",
    package = "main",
)
```

Where `library` is a `go_library` target (that isn't a `main` package), `interfaces` is the list of interfaces
you'd like `mockgen` to use reflection to generate mocks of in that `library`,
`package` is the name of the Go package at the top of the generated file (in
this example, `package "main"`), and `out` is the path of generated source file
that will be made.

You use this target's `out` file directly in the `srcs` parameter in `go_test`,
`go_library`, and so on. So, when the above example `gomock` call is used in the
same BUILD file, you put `mock_sess_test.go` in the `srcs` parameter like so:


```
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

As a slightly hidden feature, you can pass in an alternative external for where
to find the `mockgen` tool target using the `_mockgen_tool` parameter. The only
rule for the target is that must be a binary. The current default is
`"@com_github_golang_mock//mockgen"`.

If you try to use `gomock` on a `go_library` is in package `main` (and so
probably being immediately used as an `embed` target for a `go_binary`), you'll
get an annoying error like:

```
prog.go:13:2: import "your/main/package/deal" is a program, not an importable package
```

This is because `mockgen` doesn't support reflecting into binaries (because
unused symbols you might want to reflect on could be dropped, etc.) and so you
might get directed to use `mockgen`'s `-source` parameter to point at the file
that holds the interfaces you want to create mocks for.

However, using `-source` parameter doesn't allow you to generate compilable
mocks that refer to types in other packages than the one you're generated the
code into. That's annoying and a bummer, and so `gomock` doesn't support that in
its API. You can however, rig it up

I'd recommend just breaking out another `go_library` with the
interface you need, and use gomock instead.
