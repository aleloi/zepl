//! Checks if code snippets compile and compiles them into dynamic libraries.
//! Used by the REPL to validate and build user input.
const std = @import("std");
const log = std.log.scoped(.zepl_comp);

var tmpfile_num: u32 = 0;

/// For displaying comp errors.
pub const CompilationResult = struct {
    stderr: []const u8,
    term: std.process.Child.Term,
    pub fn isSuccess(self: CompilationResult) bool {
        return switch (self.term) {
            .Exited => |code| code == 0,
            else => false,
        };
    }
};

var compilation_stderr_buf: [10000]u8 = undefined;

/// Check if a snippet compiles. TODO fix the pipes to report back errors.
pub fn snippetChecksOut(allocator: std.mem.Allocator, file_content: []const u8) !CompilationResult {
    defer tmpfile_num += 1;

    const file_name = try std.fmt.allocPrint(allocator, "generated/tmpfile_{d}.zig", .{tmpfile_num});
    const temp_file = try std.fs.cwd().createFile(file_name, .{});
    temp_file.writeAll(file_content) catch unreachable;

    log.debug("  wrote {s}, checking if it compiles\n", .{file_name});

    var child = std.process.Child.init(&[_][]const u8{
        "zig", "build", "check_snippet", "--summary", "none", "--color", "on", "--prominent-compile-errors", "--", file_name,
    }, allocator);

    child.stderr_behavior = .Pipe;

    try child.spawn();
    const sz = try child.stderr.?.readAll(&compilation_stderr_buf);
    const res = compilation_stderr_buf[0..sz];

    const term = try child.wait();

    log.debug("  {s} compilation exit status: {any}\n", .{ file_name, term });

    return CompilationResult{ .term = term, .stderr = res };
}

pub const CompileError = error{
    CompileFailed,
};

/// Compile a snippet into a dylib. Returns dylib path.
/// Don't capture the output because we already did that in snippetChecksOut.
/// Which is maybe not OKAY? The comp flags are different!
pub fn compileSnippet(allocator: std.mem.Allocator, file_name: []const u8, snippet_num: u32) ![:0]const u8 {
    // create subprocess call to zig build-lib ${file_name} ...
    var child = std.process.Child.init(&[_][]const u8{
        "zig", "build-lib", "-rdynamic", "-dynamic", "-fallow-shlib-undefined", file_name,
    }, allocator);
    log.debug("  compiling {s}\n", .{file_name});
    const status = try child.spawnAndWait();
    if (status.Exited != 0) {
        return CompileError.CompileFailed;
    }

    const builtin = @import("builtin");
    const gen_file = std.fmt.allocPrintZ(allocator, "libsnippet_{d}{s}", .{ snippet_num, builtin.os.tag.dynamicLibSuffix() }) catch unreachable;
    const res = std.fmt.allocPrintZ(allocator, "./generated/libsnippet_{d}{s}", .{ snippet_num, builtin.os.tag.dynamicLibSuffix() }) catch unreachable;

    const cwd = std.fs.cwd();

    const generated = try cwd.openDir("generated", .{});
    _ = try generated.stat();
    log.debug("  generated file is: {s}\n", .{gen_file});
    log.debug("  target location is is: {s}\n", .{res});

    var buf: [1000]u8 = undefined;
    const should_be_here = try cwd.realpath(gen_file, &buf);
    log.debug("  should be here: {s}\n", .{should_be_here});

    // must work, we just created it; we can't continue if it doesn't any way.
    try std.fs.Dir.copyFile(cwd, gen_file, generated, gen_file, .{});

    // again - must work, we just copied from it
    try cwd.deleteFile(gen_file);

    // the .o files are only to clean up.
    const gen_file_o = std.fmt.allocPrintZ(allocator, "libsnippet_{d}{s}.o", .{ snippet_num, builtin.os.tag.dynamicLibSuffix() }) catch unreachable;
    cwd.deleteFile(gen_file_o) catch |err| {
        switch (err) {
            error.FileNotFound => {
                log.debug("  file not found (only tested on mac)\n", .{});
            },
            else => {
                return err;
            },
        }
    };

    log.debug("  compiled {s} into {s}\n", .{ file_name, res });
    return res;
}

const Compilation = @This();

test "snippetChecksOut returns true for a valid snippet" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const valid_snippet = "pub fn main() void {}";
    const result = try Compilation.snippetChecksOut(allocator, valid_snippet);
    try std.testing.expect(result.isSuccess());
}

test "snippetChecksOut returns false for an invalid snippet" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // An invalid snippet (missing closing brace)
    const invalid_snippet = "pub fn main() void {";
    const result = try Compilation.snippetChecksOut(allocator, invalid_snippet);
    try std.testing.expect(!result.isSuccess());
}
