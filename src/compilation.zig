//! Checks if code snippets compile and compiles them into dynamic libraries.
//! Used by the REPL to validate and build user input.
const std = @import("std");
const log = std.log.scoped(.zepl_comp);

var tmpfile_num: u32 = 0;

/// Check if a snippet compiles. TODO fix the pipes to report back errors.
pub fn snippetChecksOut(allocator: std.mem.Allocator, file_content: []const u8) !bool {
    const file_name = try std.fmt.allocPrint(allocator, "tmpfile_{d}.zig", .{tmpfile_num});
    const temp_file = try std.fs.cwd().createFile(file_name, .{});
    temp_file.writeAll(file_content) catch unreachable;

    log.debug("  wrote {s}, checking if it compiles\n", .{file_name});

    var child = std.process.Child.init(&[_][]const u8{
        "zig", "build", "check_snippet", "--", file_name,
    }, allocator);

    //const pipes = try std.posix.pipe();

    //const hej: File =

    // TODO copy piping logic from prev project... (or not, it's unix-only)
    //child.stderr = std.fs.File{ .handle = pipes[1] };
    child.stderr_behavior = .Ignore;

    const status = try child.spawnAndWait();
    tmpfile_num += 1;
    log.debug("  {s} compilation exit code: {d}\n", .{ file_name, status.Exited });

    // TODO read from the pipe; we can't use spawnAndWait
    // const otherPart = std.fs.File{ .handle = pipes[0] };
    // var buf: [10000]u8 = undefined;
    // const sz = try otherPart.readAll(&buf);
    // std.debug.print("{s}\n", .{buf[0..sz]});

    return status.Exited == 0;
}

pub const CompileError = error{
    CompileFailed,
};

/// Compile a snippet into a dylib. Returns dylib path.
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
    const res = std.fmt.allocPrintZ(allocator, "./libsnippet_{d}{s}", .{ snippet_num, builtin.os.tag.dynamicLibSuffix() }) catch unreachable;
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
    try std.testing.expect(result);
}

test "snippetChecksOut returns false for an invalid snippet" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // An invalid snippet (missing closing brace)
    const invalid_snippet = "pub fn main() void {";
    const result = try Compilation.snippetChecksOut(allocator, invalid_snippet);
    try std.testing.expect(!result);
}
