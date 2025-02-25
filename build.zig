const std = @import("std");

// fn check_snippet(b: *std.Build, file_name: []const u8) *std.Build.Step.Compile {
//     return b.addExecutable(.{
//         .name = "will_not_be_used",

//         .root_source_file = b.path(file_name),
//         .target = b.standardTargetOptions(.{}),
//         .optimize = b.standardOptimizeOption(.{}),
//     });
// }

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    //builtin.zig_version
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const linenoise = b.dependency("linenoise", .{ .target = target, .optimize = optimize }).module("linenoise");
    // const treez = b.dependency("treez", .{
    //     .target = target,
    //     .optimize = optimize,
    // }).module("treez");

    const syntax = b.dependency("syntax", .{
        .target = target,
        .optimize = optimize,
    }).module("syntax");

    const ansi_term = b.dependency("ansi-term", .{
        .target = target,
        .optimize = optimize,
    }).module("ansi-term");

    var breakpoint = b.addStaticLibrary(.{
        .name = "breakpoint",
        .target = target,
        .optimize = optimize,
    });

    breakpoint.linkLibC();
    breakpoint.addCSourceFile(.{ .file = b.path("src/breakpoint.c"), .flags = &.{} });
    //breakpoint.addIncludePath(b.path("src"));

    b.installArtifact(breakpoint);

    // // const tmpfile = b.dependency("tmpfile", .{ .target = target, .optimize = optimize }).module("tmpfile");

    // // We will also create a module for our other entry point, 'main.zig'.
    // const exe_mod = b.createModule(.{
    //     // `root_source_file` is the Zig "entry point" of the module. If a module
    //     // only contains e.g. external object files, you can make this `null`.
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    //     .imports = &.{
    //         .{
    //             .name = "linenoise",
    //             .module = linenoise,
    //         },
    //         .{
    //             .name = "treez",
    //             .module = treez,
    //         },
    //         // .{
    //         //     .name = "tmpfile",
    //         //     .module = tmpfile,
    //         // },
    //     },
    // });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "zepl",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        //.root_module = exe_mod,
    });

    //exe.root_module.addImport("treez", treez); //.module("treez"));
    exe.root_module.addImport("linenoise", linenoise); //.module("linenoise"));
    exe.root_module.addImport("syntax", syntax); //.module("syntax"));
    exe.root_module.addImport("ansi-term", ansi_term); //.module("ansi_term"));
    exe.linkLibC();
    exe.linkLibrary(breakpoint);
    // exe.linkLibrary(b.dependency("tree-sitter", .{
    //     .target = target,
    //     .optimize = optimize,
    // }).artifact("tree-sitter"));

    // exe.linkLibrary(b.dependency("tree-sitter-zig", .{
    //     .target = target,
    //     .optimize = optimize,
    // }).artifact("tree-sitter-zig"));

    // exe.linkLibrary(b.dependency("syntax", .{
    //     .target = target,
    //     .optimize = optimize,
    // }).artifact("syntax"));

    const check_step = b.step("check", "for ZLS");
    check_step.dependOn(&exe.step);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    if (b.args) |args| {
        //const snippet_module = b.createModule(.{ .root_source_file = b.path(args[0]), .target = target, .optimize = optimize });
        const snippet_exe = b.addStaticLibrary(.{
            .name = "will_not_be_used",
            .root_source_file = b.path(args[0]),
            .target = target,
            .optimize = optimize,
            //.root_module = snippet_module,
        });
        const snippet_step = b.step("check_snippet", "TODO describe");
        snippet_step.dependOn(&snippet_exe.step);
    }

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // exe_unit_tests.root_module.addImport("treez", treez); //.module("treez"));
    exe_unit_tests.root_module.addImport("linenoise", linenoise); //.module("linenoise"));
    exe_unit_tests.root_module.addImport("syntax", syntax); //.module("syntax"));
    exe_unit_tests.root_module.addImport("ansi-term", ansi_term); //.module("ansi_term"));

    // // TODO this also doesn't work; 0.14 has '.pointer'
    // // TODO this also doesn't work; 0.14 has '.pointer'
    // switch (@typeInfo(@TypeOf(exe_mod))) {
    //     .Pointer => {
    //         //exe.root_module = exe_mod.*;
    //         exe_unit_tests.root_module = exe_mod.*;
    //     },
    //     else => {
    //         //exe.root_module = exe_mod;
    //         exe_unit_tests.root_module = exe_mod;
    //     },
    // }

    // if (false) {
    //     const zig_version = @import("builtin").zig_version;

    //     //@compileLog(zig_version);
    //     // TODO is comparing versions not comptime?
    //     if (zig_version.order(std.SemanticVersion{
    //         .major = 0,
    //         .minor = 14,
    //         .patch = 0, //
    //         .pre = "dev.1",
    //     }) == .lt or false) {
    //         exe.root_module = exe_mod.*;
    //         exe_unit_tests.root_module = exe_mod.*;
    //     } else {
    //         unreachable; // zig version too new
    //         //@compileError("zig version is too new");
    //         // exe.root_module = exe_mod;
    //         // exe_unit_tests.root_module = exe_mod;
    //     }
    // }

    exe.linkLibC();

    const docsget = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    b.default_step.dependOn(&docsget.step);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    //    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    //run_cmd.step.dependOn(b.getInstallStep());
}
