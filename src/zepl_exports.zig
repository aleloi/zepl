///! Export symbols for use in generated code. This is compiled with the main zepl process. It has
/// the 'export' declarations.
/// In the generated code, we import a similar file with 'extern' declarations.
const std = @import("std");

pub var exportable_log_level: std.log.Level = .info;

var log_level_ptr: *std.log.Level = &exportable_log_level;
comptime {
    @export(log_level_ptr, .{ .name = "log_level" });
}

pub const Highlight = @import("highlight.zig");

pub export var do_highlight = true;

pub var hl: Highlight = undefined;
const log = std.log.scoped(.zepl);

// Breakpoint experiment.
pub extern fn setup_breakpoint() c_int;
pub extern fn breakpoint() void;

const stdout = std.io.getStdOut().writer();
var hl_writer = std.io.bufferedWriter(stdout);

pub var is_tty: bool = undefined;

/// export so it can be called from generated code.
pub export fn highlight(inputZ: [*:0]const u8) callconv(.C) void {
    const len = std.mem.indexOfSentinel(u8, 0, inputZ);
    const inputS: [:0]const u8 = inputZ[0..len :0];

    if (is_tty and do_highlight) {
        hl.highlight(inputS, hl_writer.writer()) catch |err| {
            log.err("  highlight error: {}\n", .{err});
            std.debug.print("{s}", .{inputS});
        };
        _ = hl_writer.write("\n") catch unreachable;
        hl_writer.flush() catch unreachable;
    } else {
        std.debug.print("{s}\n", .{inputS});
    }
}
