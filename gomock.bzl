load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_context")
load("@io_bazel_rules_go//go/private:providers.bzl", "GoLibrary")
load("@bazel_skylib//lib:paths.bzl", "paths")

_MOCKGEN_TOOL = "@com_github_golang_mock//mockgen"
_MOCKGEN_MODEL_LIB = "@com_github_golang_mock//mockgen/model:go_default_library"

def _gomock_source_impl(ctx):
    go_ctx = go_context(ctx)

    # create GOPATH and copy source into GOPATH
    source_relative_path = paths.join("src", ctx.attr.library[GoLibrary].importmap, ctx.file.source.basename)
    source = ctx.actions.declare_file(paths.join("gopath", source_relative_path))
    # trim the relative path of source to get GOPATH
    gopath = source.path[:-len(source_relative_path)]
    ctx.actions.run_shell(
        outputs=[source],
        inputs=[ctx.file.source],
        command = "mkdir -p {0} && cp -L {1} {0}".format(source.dirname, ctx.file.source.path),
    )
    # passed in source needs to be in gopath to not trigger module mode
    args = ["-source", source.path]

    args, needed_files = _handle_shared_args(ctx, args)

    if len(ctx.attr.aux_files) > 0:
        aux_files = []
        for target, pkg in ctx.attr.aux_files.items():
            f = target.files.to_list()[0]
            aux = ctx.actions.declare_file(paths.join(gopath, "src", pkg, f.basename))
            ctx.actions.run_shell(
                outputs=[aux],
                inputs=[f],
                command = "mkdir -p {0} && cp -L {1} {0}".format(aux.dirname, f.path)
            )
            aux_files.append("{0}={1}".format(pkg, aux.path))
            needed_files.append(f)
        args += ["-aux_files", ",".join(aux_files)]

    inputs = (
        needed_files +
        go_ctx.sdk.headers + go_ctx.sdk.srcs + go_ctx.sdk.tools
    ) + [source]

    # We can use the go binary from the stdlib for most of the environment
    # variables, but our GOPATH is specific to the library target we were given.
    ctx.actions.run_shell(
        outputs = [ctx.outputs.out],
        inputs = inputs,
        tools = [
            ctx.file.mockgen_tool,
            go_ctx.go,
        ],
        command = """
            export GOPATH=$(pwd)/{gopath} &&
            {cmd} {args} > {out}
        """.format(
            gopath = gopath,
            cmd = "$(pwd)/" + ctx.file.mockgen_tool.path,
            args = " ".join(args),
            out = ctx.outputs.out.path,
            mnemonic = "GoMockSourceGen",
        ),
        env = {
            # GOCACHE is required starting in Go 1.12
            "GOCACHE": "./.gocache",
        },
    )

_gomock_source = rule(
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
            doc = "Ignored. If `source` is not set, this would be the list of Go interfaces to generate mocks for.",
            mandatory = True,
        ),
        "aux_files": attr.label_keyed_string_dict(
            default = {},
            doc = "A map from auxilliary Go source files to their packages.",
            allow_files = True,
        ),
        "package": attr.string(
            doc = "The name of the package the generated mocks should be in. If not specified, uses mockgen's default.",
        ),
        "self_package": attr.string(
            doc = "The full package import path for the generated code. The purpose of this flag is to prevent import cycles in the generated code by trying to include its own package. This can happen if the mock's package is set to one of its inputs (usually the main one) and the output is stdio so mockgen cannot detect the final output package. Setting this flag will then tell mockgen which import to exclude.",
        ),
        "imports": attr.string_dict(
            doc = "Dictionary of name-path pairs of explicit imports to use.",
        ),
        "mock_names": attr.string_dict(
            doc = "Dictionary of interface name to mock name pairs to change the output names of the mock objects. Mock names default to 'Mock' prepended to the name of the interface.",
            default = {},
        ),
        "copyright_file": attr.label(
            doc = "Optional file containing copyright to prepend to the generated contents.",
            allow_single_file = True,
            mandatory = False,
        ),
        "mockgen_tool": attr.label(
            doc = "The mockgen tool to run",
            default = Label(_MOCKGEN_TOOL),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            mandatory = False,
        ),
        "_go_context_data": attr.label(
            default = "@io_bazel_rules_go//:go_context_data",
        ),
    },
    toolchains = ["@io_bazel_rules_go//go:toolchain"],
)

def gomock(name, library, out, **kwargs):
    mockgen_tool = _MOCKGEN_TOOL
    if kwargs.get("mockgen_tool", None):
        mockgen_tool = kwargs["mockgen_tool"]

    if kwargs.get("source", None):
        _gomock_source(
            name = name,
            library = library,
            out = out,
            **kwargs)
    else:
        _gomock_reflect(
            name = name,
            library = library,
            out = out,
            mockgen_tool = mockgen_tool,
            **kwargs)

def _gomock_reflect(name, library, out, mockgen_tool, **kwargs):
    interfaces = kwargs.pop("interfaces", None)

    mockgen_model_lib = _MOCKGEN_MODEL_LIB
    if kwargs.get("mockgen_model_library", None):
        mockgen_model_lib = kwargs["mockgen_model_library"]

    prog_src = name + "_gomock_prog"
    prog_src_out = prog_src + ".go"
    _gomock_prog_gen(
        name = prog_src,
        interfaces = interfaces,
        library = library,
        out = prog_src_out,
        mockgen_tool = mockgen_tool,
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
        out = out,
        prog_bin = prog_bin,
        mockgen_tool = mockgen_tool,
        **kwargs)

def _gomock_prog_gen_impl(ctx):
    args = ["-prog_only"]
    args += [ctx.attr.library[GoLibrary].importpath]
    args += [",".join(ctx.attr.interfaces)]

    cmd = ctx.file.mockgen_tool
    out = ctx.outputs.out
    ctx.actions.run_shell(
        outputs = [out],
        tools = [cmd],
        command = """
           {cmd} {args} > {out}
        """.format(
            cmd = "$(pwd)/" + cmd.path,
            args = " ".join(args),
            out = out.path,
        ),
        mnemonic = "GoMockReflectProgOnlyGen"
    )

_gomock_prog_gen = rule(
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
        "mockgen_tool": attr.label(
            doc = "The mockgen tool to run",
            default = Label(_MOCKGEN_TOOL),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            mandatory = False,
        ),
        "_go_context_data": attr.label(
            default = "@io_bazel_rules_go//:go_context_data",
        ),
    },
    toolchains = ["@io_bazel_rules_go//go:toolchain"],
)

def _gomock_prog_exec_impl(ctx):
    args = ["-exec_only", ctx.file.prog_bin.path]
    args, needed_files = _handle_shared_args(ctx, args)

    # annoyingly, the interfaces join has to go after the importpath so we can't
    # share those.
    args += [ctx.attr.library[GoLibrary].importpath]
    args += [",".join(ctx.attr.interfaces)]

    ctx.actions.run_shell(
        outputs = [ctx.outputs.out],
        inputs = [ctx.file.prog_bin] + needed_files,
        tools = [ctx.file.mockgen_tool],
        command = """{cmd} {args} > {out}""".format(
            cmd = "$(pwd)/" + ctx.file.mockgen_tool.path,
            args = " ".join(args),
            out = ctx.outputs.out.path,
        ),
        env = {
            # GOCACHE is required starting in Go 1.12
            "GOCACHE": "./.gocache",
        },
        mnemonic = "GoMockReflectExecOnlyGen",
    )

_gomock_prog_exec = rule(
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
        "self_package": attr.string(
            doc = "The full package import path for the generated code. The purpose of this flag is to prevent import cycles in the generated code by trying to include its own package. This can happen if the mock's package is set to one of its inputs (usually the main one) and the output is stdio so mockgen cannot detect the final output package. Setting this flag will then tell mockgen which import to exclude.",
        ),
        "imports": attr.string_dict(
            doc = "Dictionary of name-path pairs of explicit imports to use.",
        ),
        "mock_names": attr.string_dict(
            doc = "Dictionary of interfaceName-mockName pairs of explicit mock names to use. Mock names default to 'Mock'+ interfaceName suffix.",
            default = {},
        ),
        "copyright_file": attr.label(
            doc = "Optional file containing copyright to prepend to the generated contents.",
            allow_single_file = True,
            mandatory = False,
        ),
        "prog_bin": attr.label(
            doc = "The program binary generated by mockgen's -prog_only and compiled by bazel.",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "mockgen_tool": attr.label(
            doc = "The mockgen tool to run",
            default = Label(_MOCKGEN_TOOL),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            mandatory = False,
	),
        "_go_context_data": attr.label(
            default = "@io_bazel_rules_go//:go_context_data",
        ),
    },
    toolchains = ["@io_bazel_rules_go//go:toolchain"],
)

def _handle_shared_args(ctx, args):
    needed_files = []

    if ctx.attr.package != "":
        args += ["-package", ctx.attr.package]
    if ctx.attr.self_package != "":
        args += ["-self_package", ctx.attr.self_package]
    if len(ctx.attr.imports) > 0:
        imports = ",".join(["{0}={1}".format(name, pkg) for name, pkg in ctx.attr.imports.items()])
        args += ["-imports", imports]
    if ctx.file.copyright_file != None:
        args += ["-copyright_file", ctx.file.copyright_file.path]
        needed_files.append(ctx.file.copyright_file)
    if len(ctx.attr.mock_names) > 0:
        mock_names = ",".join(["{0}={1}".format(name, pkg) for name, pkg in ctx.attr.mock_names.items()])
        args += ["-mock_names", mock_names]

    return args, needed_files
