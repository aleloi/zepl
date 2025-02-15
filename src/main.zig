//! The entry point of the Read Evaluate Print Loop. Better name would be
//! Read Compile LoadDynamically Execute loop.
//! Reads user input, processes code snippets, compiles them, and executes the compiled code.
const std = @import("std");
pub const compilation = @import("compilation.zig");
pub const Linenoise = @import("linenoise").Linenoise;
pub const preprocess = @import("preprocess.zig");

const log = std.log.scoped(.zepl);

pub const std_options = .{
    .log_level = .info,
    .logFn = logFn,
};

/// See `std.log`.
pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const scope_prefix = "(" ++ @tagName(scope) ++ ") ";
    const prefix = "  [" ++ comptime level.asText() ++ "] " ++ scope_prefix;
    std.debug.print(prefix ++ format, args);
}

/// Write snippet content to a file.
fn makeSnippet(file_name: []const u8, snippet_content: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    try file.writeAll(snippet_content);
}

/// Load a dynamic library into current process.
fn loadDylib(dylib_name: [:0]const u8) !*anyopaque {
    log.debug("  loading dylib: {s}\n", .{dylib_name});
    return std.c.dlopen(dylib_name, @bitCast(@import("dlopen_rtld_backport.zig").RTLD{
        .NOW = true,
        .GLOBAL = true,
    })) orelse {
        log.err("  Couldn't load dylib, can't continue. This is probably a bug. Error is: {?s}\n", .{std.c.dlerror()});
        std.process.exit(1);
    };
}

/// Run the side effects function from a dylib.
fn runSideEffects(handle: *anyopaque, sideEffectsName: [:0]const u8) !void {
    const sym: *anyopaque = std.c.dlsym(handle, sideEffectsName) orelse {
        log.err("  Couldn't load side effects function from dylib, can't continue. This is probably a bug. Error is: {?s}\n", .{std.c.dlerror()});
        std.process.exit(1);
    };
    const myFun: *const fn () void = @ptrCast(@alignCast(sym));
    myFun();
}

/// Read-Eval-Print Loop.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const ReplContext = @import("repl_context.zig").ReplContext;
    var zepl_context = ReplContext.init(std.heap.page_allocator);

    var ln = Linenoise.init(std.heap.page_allocator);
    ln.history.load("history.txt") catch {};

    defer {
        ln.history.save("history.txt") catch log.debug("Failed to save history\n", .{});
        ln.deinit();
    }

    var snippet_num: u32 = 0;

    const allocator = arena.allocator();

    while (try ln.linenoise("zepl> ")) |input| {
        defer _ = arena.reset(.retain_capacity);
        try ln.history.add(input);
        snippet_num += 1;

        const parsed_ast = @import("parse.zig").parse(allocator, input, zepl_context) catch |err| {
            log.info("  Parsing error: {}\n", .{err});
            continue;
        };

        const pa = preprocess.PreprocArgs{
            .snippet_num = snippet_num,
            .source = input,
            .parsed = parsed_ast,
            .rc = zepl_context,
            .allocator = allocator,
        };

        log.debug("  Parsed AST: {}\n", .{parsed_ast.tag});

        const pres = preprocess.preprocess(pa) catch |err| {
            log.info("  couldn't preprocess: {}. TODO show compilation logs.\n", .{err});
            continue;
        };
        //log.debug("  export: {?s}\n", .{pres.export_symbol});
        //defer allocator.free(input);

        var current_snippet_buf: [100000]u8 = undefined;
        var fbs_output: std.io.FixedBufferStream([]u8) = std.io.fixedBufferStream(&current_snippet_buf);
        fbs_output.writer().print(
            \\{s}  // context
            \\{s}  // export
            \\{s}  // comptime
            \\{s}  // side effects
            \\
        , .{
            zepl_context.current_context.items,
            pres.export_symbol orelse "",
            pres.comptime_stmt orelse "",
            pres.side_effects,
        }) catch unreachable;

        if (!try compilation.snippetChecksOut(allocator, fbs_output.getWritten())) {
            log.info("Couldn't compile TODO plumb compilation errors here.\n", .{});
            log.info("Run `build check_snippet -- tmpfile_<NUM>.zig`\n", .{});
            continue;
        }

        const file_name = try std.fmt.allocPrint(allocator, "snippet_{d}.zig", .{snippet_num});
        try makeSnippet(file_name, fbs_output.getWritten());

        const dylib_name = compilation.compileSnippet(allocator, file_name, snippet_num) catch |err| {
            switch (err) {
                compilation.CompileError.CompileFailed => continue,
                else => unreachable,
            }
        };

        try zepl_context.current_context.appendSlice("// snippet\n");
        try zepl_context.comptimes.appendSlice("// snippet\n");
        try zepl_context.externs.appendSlice("// snippet\n");
        try zepl_context.comptimes.appendSlice(pres.comptime_stmt orelse "");
        try zepl_context.externs.appendSlice(pres.extern_def orelse "");
        try zepl_context.current_context.appendSlice(pres.comptime_stmt orelse "");
        try zepl_context.current_context.appendSlice(pres.extern_def orelse "");

        const sideEffectsName = try @TypeOf(pres).sideEffectsName(allocator, snippet_num);
        const handle = try loadDylib(dylib_name);
        try runSideEffects(handle, sideEffectsName);
    }
}

// To make sure tests run with "zig build test"
test {
    std.testing.refAllDecls(@This());
    // or refAllDeclsRecursive
}
