load("@io_bazel_rules_go//go:def.bzl", "go_context", "go_path", "go_rule")
load("@io_bazel_rules_go//go/private:providers.bzl", "GoLibrary", "GoPath")

_MOCKGEN_TOOL = "@com_github_golang_mock//mockgen"

def _gomock_sh_impl(ctx):
    go_ctx = go_context(ctx)
    gopath = "$(pwd)/" + ctx.var["BINDIR"] + "/" + ctx.attr.gopath_dep[GoPath].gopath

    inputs = [ctx.file.mockgen_tool, go_ctx.go] + (
        ctx.attr.gopath_dep.files.to_list() +
        go_ctx.sdk.headers + go_ctx.sdk.srcs + go_ctx.sdk.tools
    )
    args = []
    if ctx.attr.package != "":
        args += ["-package", ctx.attr.package]

    args += ["-destination", "$(pwd)/" + ctx.outputs.out.path]

    if ctx.attr.source == None:
        args += [ctx.attr.library[GoLibrary].importpath]
    else:
        args += ["-source", ctx.file.source.path]
        inputs += [ctx.file.source]

    args += [",".join(ctx.attr.interfaces)]

    # We can use the go binary from the stdlib for most of the environment
    # variables, but our GOPATH is specific to the library target we were given.
    ctx.actions.run_shell(
        outputs = [ctx.outputs.out],
        inputs = inputs,
        command = """
           source <($PWD/{godir}/go env) &&
           export PATH=$GOROOT/bin:$PWD/{godir}:$PATH &&
           export GOPATH={gopath} &&
           {mockgen} {args}
        """.format(
            godir = go_ctx.go.path[:-1 - len(go_ctx.go.basename)],
            gopath = gopath,
            mockgen = "$(pwd)/" + ctx.file.mockgen_tool.path,
            args = " ".join(args),
        ),
    )

_gomock_sh = go_rule(
    _gomock_sh_impl,
    attrs = {
        "library": attr.label(
            doc = "The target the Go library is at to look for the interfaces in. When this is set and source is not set, mockgen will use its reflect code to generate the mocks. If source is set, its dependencies will be included in the GOPATH that mockgen will be run in.",
            providers = [GoLibrary],
            mandatory = True,
        ),
        "source": attr.label(
            doc = "A Go source file to find all the interfaces to generate mocks for. See also the docs for library.",
            mandatory = False,
            allow_single_file = True,
        ),
        "out": attr.output(
            doc = "The new Go file to emit the generated mocks into",
            mandatory = True,
        ),
        "interfaces": attr.string_list(
            allow_empty = False,
            doc = "The names of the Go interfaces to generate mocks for. If not set, all of the interfaces in the library or source file will have mocks generated for them.",
            mandatory = True,
        ),
        "package": attr.string(
            doc = "The name of the package the generated mocks should be in. If not specified, uses mockgen's default.",
        ),
        "gopath_dep": attr.label(
            doc = "The go_path label to use to create the GOPATH for the given library. Will be set correctly by the gomock macro, so you don't need to set it.",
            providers = [GoPath],
            mandatory = False,
        ),
        "mockgen_tool": attr.label(
            doc = "The mockgen tool to run",
            default = Label(_MOCKGEN_TOOL),
            allow_single_file = True,
            executable = True,
            cfg = "host",
            mandatory = False,
        ),
    },
)

def gomock(name, library, out, **kwargs):
    gopath_name = name + "_gomock_gopath"
    mockgen_tool = _MOCKGEN_TOOL
    if kwargs.get("mockgen_tool", None):
        mockgen_tool = kwargs["mockgen_tool"]
    go_path(
        name = gopath_name,
        deps = [library, mockgen_tool],
    )

    _gomock_sh(
        name = name,
        library = library,
        gopath_dep = gopath_name,
        out = out,
        **kwargs
    )
