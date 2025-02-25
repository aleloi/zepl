//! The entry point of the Read Evaluate Print Loop. Better name would be
//! Read Compile LoadDynamically Execute loop.
//! Reads user input, processes code snippets, compiles them, and executes the compiled code.
const std = @import("std");
pub const compilation = @import("compilation.zig");
pub const Linenoise = @import("linenoise").Linenoise;
pub const preprocess = @import("preprocess.zig");

const zepl_exports = @import("zepl_exports.zig");

const log = std.log.scoped(.zepl);

pub var std_options = .{
    .log_level = .debug,
    .logFn = logFn,
};

// comptime {
//     @export(options_ptr, .{ .name = "log_options" });
// }

//pub var

/// See `std.log`.
pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    if (@intFromEnum(level) <= @intFromEnum(zepl_exports.exportable_log_level)) {
        const scope_prefix = "(" ++ @tagName(scope) ++ ") ";
        const prefix = "  [" ++ comptime level.asText() ++ "] " ++ scope_prefix;
        std.debug.print(prefix ++ format, args);
    }
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
    const my_fun: *const fn () void = @ptrCast(@alignCast(sym));
    call_with_breakpoint(my_fun);
    //myFun();
}
//extern fn test_breakpoint() void;

extern fn call_me_with_breakpoint() void;
extern fn call_with_breakpoint(*const anyopaque) void;

fn testBreakpoint() void {
    call_with_breakpoint(@ptrCast(@alignCast(&call_me_with_breakpoint)));
}

/// Read-Eval-Print Loop.
pub fn main() !void {
    //testBreakpoint();
    //test_breakpoint();
    //try test_syntax();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const ReplContext = @import("repl_context.zig").ReplContext;
    var zepl_context = ReplContext.init(std.heap.page_allocator);

    // try zepl_context.current_context.appendSlice(
    //     \\extern const log_level: *@import("std").log.Level;
    //     \\extern fn highlight(inputZ: [*:0]const u8) callconv(.C) void;
    // );

    var ln = Linenoise.init(std.heap.page_allocator);
    ln.history.load("history.txt") catch {};

    defer {
        ln.history.save("history.txt") catch log.debug("Failed to save history\n", .{});
        ln.deinit();
    }

    var snippet_num: u32 = 0;

    const allocator = arena.allocator();

    // TODO maybe an .init() ?
    zepl_exports.is_tty = ln.is_tty;
    zepl_exports.hl = zepl_exports.Highlight{
        .allocator = allocator,
    };

    try zepl_context.current_context.appendSlice(@embedFile("zepl_externs.zig"));

    //_ = zepl_exports.setup_breakpoint();

    const magic_string_that_removes_the_input_text_after_prompt = "\x1B[A\r\x1B[6C\x1B[K";
    // AI explains:
    // Here’s what each part does:
    // •	\x1B[A: Moves the cursor up one line.
    // •	\r: Returns the cursor to the beginning of the line.
    // •	\x1B[6C: Moves the cursor 6 columns to the right (i.e. past "zepl> ").
    // •	\x1B[K: Clears from the cursor’s current position to the end of the line.

    while (try ln.linenoise("\x1B[1mzepl> \x1B[0m")) |input| {
        if (ln.is_tty and zepl_exports.do_highlight) {
            std.debug.print(magic_string_that_removes_the_input_text_after_prompt, .{});
            const inputZ = std.fmt.allocPrintZ(allocator, "{s}", .{input}) catch unreachable;
            zepl_exports.highlight(inputZ);
        }

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

        const comp_out = try compilation.snippetChecksOut(allocator, fbs_output.getWritten());

        if (!comp_out.isSuccess()) {
            log.info("  comp output: {s}", .{comp_out.stderr});
            //log.info("Couldn't compile TODO plumb compilation errors here.\n", .{});
            //log.info("Run `build check_snippet -- tmpfile_<NUM>.zig`\n", .{});
            continue;
        }

        const file_name = try std.fmt.allocPrint(allocator, "generated/snippet_{d}.zig", .{snippet_num});
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
        {
            if (ln.is_tty and zepl_exports.do_highlight) {
                std.debug.print("\x1B[36m", .{});
            }
            defer {
                if (ln.is_tty and zepl_exports.do_highlight) std.debug.print("\x1B[0m", .{});
            }
            try runSideEffects(handle, sideEffectsName);
        }
    }
}

// To make sure tests run with "zig build test"
test {
    std.testing.refAllDecls(@This());
    // or refAllDeclsRecursive

}

fn fib(comptime n: comptime_int) comptime_int {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}
