//! Keeps track of history and code that's
//! put at the top of each snippet. Grows with new declarations.
const std = @import("std");

/// history
pub const ReplContext = struct {

    // Do we keep them seperate?
    comptimes: std.ArrayList(u8),
    externs: std.ArrayList(u8),

    /// All the context to compile a snippet; both comptimes and externs.
    current_context: std.ArrayList(u8),

    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) @This() {
        const au8 = std.ArrayList(u8);
        return .{
            .allocator = allocator,
            .comptimes = au8.init(allocator),
            .externs = au8.init(allocator),
            .current_context = au8.init(allocator),
        };
    }

    // todo deinit
};
