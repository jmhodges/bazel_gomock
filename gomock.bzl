load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_context", "go_path", "go_rule")
load("@io_bazel_rules_go//go/private:providers.bzl", "GoLibrary", "GoPath")

_MOCKGEN_TOOL = "@com_github_golang_mock//mockgen"
_MOCKGEN_MODEL_LIB = "@com_github_golang_mock//mockgen/model:go_default_library"

def _gomock_source_impl(ctx):
    args = ["-source", ctx.file.source.path]
    if ctx.attr.package != "":
        args += ["-package", ctx.attr.package]
    args += [",".join(ctx.attr.interfaces)]

    _go_tool_run_shell_stdout(
        ctx = ctx,
        cmd = ctx.file.mockgen_tool,
        args = args,
        extra_inputs = [ctx.file.source],
        out = ctx.outputs.out,
    )

_gomock_source = go_rule(
    _gomock_source_impl,
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

    if kwargs.get("source", None):
        _gomock_source(
            name = name,
            library = library,
            gopath_dep = gopath_name,
            out = out,
            **kwargs
        )
    else:
        _gomock_reflect(
            name = name,
            library = library,
            out = out,
            mockgen_tool = mockgen_tool,
            gopath_dep = gopath_name,
            **kwargs
        )

def _gomock_reflect(name, library, out, mockgen_tool, gopath_dep, **kwargs):
    interfaces = kwargs.get("interfaces", None)
    mockgen_model_lib = _MOCKGEN_MODEL_LIB
    if kwargs.get("mockgen_model_library", None):
        mockgen_model_lib = kwargs["mockgen_model_library"]

    prog_src = name + "_gomock_prog"
    prog_src_out = prog_src + ".go"
    _gomock_prog_gen(
        name = prog_src,
        interfaces = interfaces,
        library = library,
        package = kwargs.get("package", None),
        out = prog_src_out,
        mockgen_tool = mockgen_tool,
        gopath_dep = gopath_dep,
    )
    prog_bin = name + "_gomock_prog_bin"
    go_binary(
        name = prog_bin,
        srcs = [prog_src_out],
        deps = [library, mockgen_model_lib],
    )
    _gomock_prog_exec(
        name = name,
        interfaces = interfaces,
        library = library,
        package = kwargs.get("package", None),
        out = out,
        prog_bin = prog_bin,
        mockgen_tool = mockgen_tool,
        gopath_dep = gopath_dep,
    )

def _gomock_prog_gen_impl(ctx):
    args = ["-prog_only"]
    if ctx.attr.package != "":
        args += ["-package", ctx.attr.package]

    args += [ctx.attr.library[GoLibrary].importpath]
    args += [",".join(ctx.attr.interfaces)]
    _go_tool_run_shell_stdout(
        ctx = ctx,
        cmd = ctx.file.mockgen_tool,
        args = args,
        extra_inputs = [],
        out = ctx.outputs.out,
    )

_gomock_prog_gen = go_rule(
    _gomock_prog_gen_impl,
    attrs = {
        "library": attr.label(
            doc = "The target the Go library is at to look for the interfaces in. When this is set and source is not set, mockgen will use its reflect code to generate the mocks. If source is set, its dependencies will be included in the GOPATH that mockgen will be run in.",
            providers = [GoLibrary],
            mandatory = True,
        ),
        "out": attr.output(
            doc = "The new Go source file put the mock generator code",
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
            mandatory = True,
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

def _gomock_prog_exec_impl(ctx):
    args = ["-exec_only", ctx.file.prog_bin.path]
    if ctx.attr.package != "":
        args += ["-package", ctx.attr.package]

    args += [ctx.attr.library[GoLibrary].importpath]
    args += [",".join(ctx.attr.interfaces)]

    ctx.actions.run_shell(
        outputs = [ctx.outputs.out],
        inputs = [ctx.file.mockgen_tool, ctx.file.prog_bin],
        command = """{cmd} {args} > {out}""".format(
            cmd = "$(pwd)/" + ctx.file.mockgen_tool.path,
            args = " ".join(args),
            out = ctx.outputs.out.path,
        ),
    )

_gomock_prog_exec = go_rule(
    _gomock_prog_exec_impl,
    attrs = {
        "library": attr.label(
            doc = "The target the Go library is at to look for the interfaces in. When this is set and source is not set, mockgen will use its reflect code to generate the mocks. If source is set, its dependencies will be included in the GOPATH that mockgen will be run in.",
            providers = [GoLibrary],
            mandatory = True,
        ),
        "out": attr.output(
            doc = "The new Go source file to put the generated mock code",
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
        "prog_bin": attr.label(
            doc = "The program binary generated by mockgen's -prog_only and compiled by bazel.",
            allow_single_file = True,
            executable = True,
            cfg = "host",
            mandatory = True,
        ),
        "gopath_dep": attr.label(
            doc = "The go_path label to use to create the GOPATH for the given library. Will be set correctly by the gomock macro, so you don't need to set it.",
            providers = [GoPath],
            mandatory = True,
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

def _go_tool_run_shell_stdout(ctx, cmd, args, extra_inputs, out):
    go_ctx = go_context(ctx)
    gopath = "$(pwd)/" + ctx.var["BINDIR"] + "/" + ctx.attr.gopath_dep[GoPath].gopath

    inputs = [cmd, go_ctx.go] + (
        ctx.attr.gopath_dep.files.to_list() +
        go_ctx.sdk.headers + go_ctx.sdk.srcs + go_ctx.sdk.tools
    ) + extra_inputs

    # We can use the go binary from the stdlib for most of the environment
    # variables, but our GOPATH is specific to the library target we were given.
    ctx.actions.run_shell(
        outputs = [out],
        inputs = inputs,
        command = """
           source <($PWD/{godir}/go env) &&
           export PATH=$GOROOT/bin:$PWD/{godir}:$PATH &&
           export GOPATH={gopath} &&
           {cmd} {args} > {out}
        """.format(
            godir = go_ctx.go.path[:-1 - len(go_ctx.go.basename)],
            gopath = gopath,
            cmd = "$(pwd)/" + cmd.path,
            args = " ".join(args),
            out = out.path,
        ),
    )
