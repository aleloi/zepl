pub const zepl_externs = struct {
    // Breakpoint experiment.
    pub extern fn setup_breakpoint() c_int;
    pub extern fn breakpoint() void;

    // syntax highlighting for zepl
    pub extern fn highlight(inputZ: [*:0]const u8) void;
    pub extern var do_highlight: bool;

    // change log level from within zepl
    pub extern const log_level: *@import("std").log.Level;
};
