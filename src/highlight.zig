//! Based on https://github.com/neurocyte/zat/blob/master/src/main.zig
const std = @import("std");
const syntax = @import("syntax");
const Theme = @import("generated/theme.zig");
const themes = @import("generated/themes.zig");
const term = @import("ansi-term");

const Self = @This();

const log = std.log.scoped(.zepl_highlight);

allocator: std.mem.Allocator,

/// Highlights the given Zig source code and writes ANSI escape codes to `writer`.
pub fn highlight(self: Self, source: [:0]const u8, writer: anytype) !void {

    // Create a tree-sitter syntax object for Zig.
    var syntax_obj = try syntax.create_file_type(self.allocator, "zig");
    try syntax_obj.refresh_from_string(source);

    // Hard-code theme to "default"
    const theme = get_theme_by_name("default") orelse unreachable;

    //std.debug.print(" theme name: {any}\n\n", .{theme});

    const Ctx = struct {
        writer: @TypeOf(writer),
        content: []const u8,
        theme: *const Theme,
        last_pos: usize,
        const CtxSelf = @This();

        /// This callback is invoked by the tree-sitter renderer for each token.
        pub fn cb(ctx: *CtxSelf, range: syntax.Range, scope: []const u8, id: u32, idx: usize, node: *const syntax.Node) error{Stop}!void {
            _ = id;
            //_ = idx;
            _ = node;
            if (idx > 0) return;

            // Write any text before the highlighted range.
            if (ctx.last_pos < range.start_byte) {
                set_ansi_style(ctx.writer, ctx.theme.editor, "editor") catch return error.Stop;
                log.debug("writeAll: {s}\n", .{ctx.content[ctx.last_pos..range.start_byte]});
                ctx.writer.writeAll(ctx.content[ctx.last_pos..range.start_byte]) catch return error.Stop;
                unset_ansi_style(ctx.writer, ctx.theme.editor) catch return error.Stop;
            }

            // If another capture has already advanced the last_pos past this token's start, skip.
            if (range.start_byte < ctx.last_pos) return;

            // Look up a token style for the scope, or fall back to the default editor style.
            const token = find_token(ctx.theme, scope);
            if (token) |t| {
                log.debug("found token, id: {d}, style fg: {?any} for scope {s}\n", .{ t.id, t.style.fg, scope });
            } else {
                log.debug("no token found for scope {s}\n", .{scope});
            }
            //log.debug("found token: {} for scope {s}\n", .{ token, scope });
            const style = if (token) |t| t.style else ctx.theme.editor;
            set_ansi_style(ctx.writer, style, scope) catch return error.Stop;
            log.debug("writeAll: {s}\n", .{ctx.content[range.start_byte..range.end_byte]});
            ctx.writer.writeAll(ctx.content[range.start_byte..range.end_byte]) catch return error.Stop;
            unset_ansi_style(ctx.writer, ctx.theme.editor) catch return error.Stop;
            ctx.last_pos = range.end_byte;
        }
    };
    // Create a minimal context that holds just what we need.
    var ctx = Ctx{
        .writer = writer,
        .content = source,
        .theme = theme,
        .last_pos = 0,
    };

    // Render tokens from the syntax tree.
    try syntax_obj.render(&ctx, Ctx.cb, null);

    // Write any remaining text.
    if (ctx.last_pos < source.len) {
        try writer.writeAll(source[ctx.last_pos..]);
    }
}

//const StyleFn = fn (writer: anytype, style: Theme.Style) !void;

/// Finds a matching token for the given scope (if any) by scanning theme tokens in reverse.
fn find_token(theme: *const Theme, scope: []const u8) ?Theme.Token {
    return if (find_scope_fallback(scope)) |tm_scope|
        find_scope_style_nofallback(theme, tm_scope) orelse find_scope_style_nofallback(theme, scope)
    else
        find_scope_style_nofallback(theme, scope);
}

fn find_scope_style_nofallback(theme: *const Theme, scope: []const u8) ?Theme.Token {
    var idx = theme.tokens.len - 1;
    var done = false;
    while (!done) : (if (idx == 0) {
        done = true;
    } else {
        idx -= 1;
    }) {
        const token = theme.tokens[idx];
        const name = themes.scopes[token.id];
        if (name.len > scope.len)
            continue;
        if (std.mem.eql(u8, name, scope[0..name.len]))
            return token;
    }
    return null;
}

fn find_scope_fallback(scope: []const u8) ?[]const u8 {
    for (fallbacks) |fallback| {
        if (fallback.ts.len > scope.len)
            continue;
        if (std.mem.eql(u8, fallback.ts, scope[0..fallback.ts.len]))
            return fallback.tm;
    }
    return null;
}

pub const FallBack = struct { ts: []const u8, tm: []const u8 };
pub const fallbacks: []const FallBack = &[_]FallBack{
    .{ .ts = "namespace", .tm = "entity.name.namespace" },
    .{ .ts = "type", .tm = "entity.name.type" },
    .{ .ts = "type.defaultLibrary", .tm = "support.type" },
    .{ .ts = "struct", .tm = "storage.type.struct" },
    .{ .ts = "class", .tm = "entity.name.type.class" },
    .{ .ts = "class.defaultLibrary", .tm = "support.class" },
    .{ .ts = "interface", .tm = "entity.name.type.interface" },
    .{ .ts = "enum", .tm = "entity.name.type.enum" },
    .{ .ts = "function", .tm = "entity.name.function" },
    .{ .ts = "function.defaultLibrary", .tm = "support.function" },
    .{ .ts = "method", .tm = "entity.name.function.member" },
    .{ .ts = "macro", .tm = "entity.name.function.macro" },
    .{ .ts = "variable", .tm = "variable.other.readwrite , entity.name.variable" },
    .{ .ts = "variable.readonly", .tm = "variable.other.constant" },
    .{ .ts = "variable.readonly.defaultLibrary", .tm = "support.constant" },
    .{ .ts = "parameter", .tm = "variable.parameter" },
    .{ .ts = "property", .tm = "variable.other.property" },
    .{ .ts = "property.readonly", .tm = "variable.other.constant.property" },
    .{ .ts = "enumMember", .tm = "variable.other.enummember" },
    .{ .ts = "event", .tm = "variable.other.event" },

    // zig
    .{ .ts = "attribute", .tm = "keyword" },
    .{ .ts = "number", .tm = "constant.numeric" },
    .{ .ts = "conditional", .tm = "keyword.control.conditional" },
    .{ .ts = "operator", .tm = "keyword.operator" },
    .{ .ts = "boolean", .tm = "keyword.constant.bool" },
    .{ .ts = "string", .tm = "string.quoted" },
    .{ .ts = "repeat", .tm = "keyword.control.flow" },
    .{ .ts = "field", .tm = "variable" },
};

/// Returns a pointer to the theme with the given name, or null if not found.
fn get_theme_by_name(name: []const u8) ?*const Theme {
    var i: usize = 0;
    while (i < themes.themes.len) : (i += 1) {
        if (std.mem.eql(u8, themes.themes[i].name, name)) {
            return &themes.themes[i];
        }
    }
    return null;
}

fn update_ansi_style(writer: anytype, ansi_style: term.style.Style, name: []const u8) !void {
    log.debug("update_style: {s}, fg: {any}\n", .{ name, ansi_style.foreground });
    try term.format.updateStyle(writer, ansi_style, null);
}

/// Sets the ANSI style on the writer based on the given theme style.
fn set_ansi_style(writer: anytype, style: Theme.Style, name: []const u8) !void {
    const ansi_style = term.style.Style{
        .foreground = if (style.fg) |color| to_rgb_color(color.color) else term.style.Color.Default,
        .background = if (style.bg) |color| to_rgb_color(color.color) else term.style.Color.Default,
        .font_style = switch (style.fs orelse .normal) {
            .normal => term.style.FontStyle{},
            .bold => term.style.FontStyle.bold,
            .italic => term.style.FontStyle.italic,
            .underline => term.style.FontStyle.underline,
            .undercurl => term.style.FontStyle.underline,
            .strikethrough => term.style.FontStyle.crossedout,
        },
    };
    try update_ansi_style(writer, ansi_style, name);
}

/// Resets the style on the writer to default.
fn unset_ansi_style(writer: anytype, style: Theme.Style) !void {
    _ = style;
    try update_ansi_style(writer, term.style.Style{
        .foreground = term.style.Color.Default,
        .background = term.style.Color.Default,
        .font_style = term.style.FontStyle{},
    }, "unset");
}

/// Converts a u24 color into an ansi-term Color.
fn to_rgb_color(color: u24) term.style.Color {
    const r: u8 = @intCast((color >> 16) & 0xFF);
    const g: u8 = @intCast((color >> 8) & 0xFF);
    const b: u8 = @intCast(color & 0xFF);
    return term.style.Color{ .RGB = .{ .r = r, .g = g, .b = b } };
}
