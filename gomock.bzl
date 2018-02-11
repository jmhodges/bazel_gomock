load("@io_bazel_rules_go//go:def.bzl", "go_context", "go_path", "go_rule")

load("@io_bazel_rules_go//go/private:providers.bzl", "GoLibrary", "GoPath", "GoStdLib")

_MOCKGEN_TOOL = "@com_github_golang_mock//mockgen"
        
def _gomock_sh_impl(ctx):
    go_ctx = go_context(ctx)
    gopath = "$(pwd)/" + ctx.var["BINDIR"] + "/" + ctx.attr.gopath_dep[GoPath].gopath

    stdlib = go_ctx.stdlib

    pkg_args = []
    if ctx.attr.package != '':
        pkg_args = ["-package", ctx.attr.package]
    args = pkg_args + [
        "-destination", "$(pwd)/"+ ctx.outputs.out.path,
        ctx.attr.library[GoLibrary].importpath,
        ",".join(ctx.attr.interfaces),
    ]

    # We can use the go binary from the stdlib for most of the environment
    # variables, but our GOPATH is specific to the library target we were given.
    ctx.actions.run_shell(
        outputs = [ctx.outputs.out],
        inputs = [ctx.file._mockgen, go_ctx.go] + ctx.attr.gopath_dep.files.to_list(),
        command = """
           source <($PWD/{godir}/go env) &&
           export PATH=$GOROOT/bin:$PWD/{godir}:$PATH &&
           export GOPATH={gopath} &&
           {mockgen} {args}
        """.format(
            godir=go_ctx.go.path[:-1-len(go_ctx.go.basename)],
            gopath=gopath,
            mockgen="$(pwd)/"+ctx.file._mockgen.path,
            args = " ".join(args)
        )
    )

_gomock_sh = go_rule(
    _gomock_sh_impl,
    attrs = {
        "library": attr.label(
            doc = "The target the Go library is at to look for the interfaces in. When this is set, mockgen will use its reflect code to generate the mocks. source cannot also be set when this is set.",
            providers = [GoLibrary],
            mandatory = True,
        ),

        "gopath_dep": attr.label(
            doc = "The go_path label to use to create the GOPATH for the given library",
            providers=[GoPath],
            mandatory = True
        ),

        "out": attr.output(
            doc = "The new Go file to emit the generated mocks into",
            mandatory = True
        ),
    
        "interfaces": attr.string_list(
            allow_empty = False,
            doc = "The names of the Go interfaces to generate mocks for",
            mandatory = True,
        ),
        "package": attr.string(
            doc = "The name of the package the generated mocks should be in. If not specified, uses mockgen's default.",
        ),
        "_mockgen": attr.label(
            doc = "The mockgen tool to run",
            default = Label(_MOCKGEN_TOOL),
            allow_single_file = True,
            executable = True,
            cfg = "host",
        ),
    },
)

def gomock(name, library, out, **kwargs):
    gopath_name = name + "_gomock_gopath"
    mockgen_tool = _MOCKGEN_TOOL
    if kwargs.get("_mockgen_tool", None):
        mockgen_tool = kwargs["_mockgen_tool"]
    go_path(
        name = gopath_name,
        deps = [library, mockgen_tool]
    )

    _gomock_sh(
        name = name,
        library = library,
        gopath_dep = gopath_name,
        out = out,
        **kwargs
    )
