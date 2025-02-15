/// parse.zig
/// All parsing- and AST-related activities are done though here.
/// I first tried to only use zig.Ast, but couldn't figure out how to avoid compilation.
/// Could maybe use std.zig.{AstGen / AstRIAnnotate}
const std = @import("std");
pub const repl_context = @import("repl_context.zig");
const ReplContext = repl_context.ReplContext;
pub const compilation = @import("compilation.zig");
const Ast = std.zig.Ast;

const log = std.log.scoped(.zepl_parse);

pub const ParseError = error{
    ParseError,
    NotOneRootDecl,
};

pub const ParseResult = struct {
    const Tag = enum { value, container_level_decl, block_level };

    tag: Tag,
    ast: Ast,
    // TODO: include top-level node tag.
};

fn itCompiles(source: []const u8, zepl_context: ReplContext, alloc: std.mem.Allocator) bool {
    const full_source = std.fmt.allocPrint(alloc,
        \\{s}
        \\{s}
        \\
    , .{ zepl_context.current_context.items, source }) catch unreachable;
    return compilation.snippetChecksOut(alloc, full_source) catch unreachable;
}

/// Tries to parse in a few different ways. Ast.parse is too permissive, so also runs the compiler.
pub fn parse(allocator: std.mem.Allocator, src: []const u8, zepl_context: ReplContext) ParseError!ParseResult {
    const srcZ = std.fmt.allocPrintZ(allocator, "{s}", .{src}) catch unreachable;
    const valueZ = std.fmt.allocPrintZ(allocator, "test {{ _ = @TypeOf({s}); }}", .{src}) catch unreachable;
    const blockZ = std.fmt.allocPrintZ(allocator, "test {{ {s} }}", .{src}) catch unreachable;

    var ast = std.zig.Ast.parse(allocator, valueZ, .zig) catch unreachable;
    if (ast.errors.len == 0 and itCompiles(valueZ, zepl_context, allocator)) {
        log.debug("  parsed as a value using {s}\n", .{valueZ});
        return ParseResult{ .tag = .value, .ast = ast };
    } else {
        ast.deinit(allocator);
        log.debug("  ParseError as a value, trying container-level member\n", .{});
    }

    ast = std.zig.Ast.parse(allocator, srcZ, .zig) catch unreachable;
    if (ast.errors.len == 0 and itCompiles(srcZ, zepl_context, allocator)) {
        return ParseResult{ .tag = .container_level_decl, .ast = ast };
    } else {
        ast.deinit(allocator);
        log.debug("  ParseError as container-level, trying block-level\n", .{});
    }
    ast = std.zig.Ast.parse(allocator, blockZ, .zig) catch unreachable;
    if (ast.errors.len == 0 and itCompiles(blockZ, zepl_context, allocator)) {
        return ParseResult{ .tag = .block_level, .ast = ast };
    } else {
        ast.deinit(allocator);
        return error.ParseError;
    }
}

/// Used for generating code from a declaration. We change the mut, add @TypeOf,
///split it into declaration and assignment and probably more. See `preprocess.zig`.
pub const ParsedDecl = struct {
    // Zig syntax (0.13 and unreleased 0.14):
    // ?VISIBILITY ?EXTERN_EXPORT ?THREAD_LOCAL ?COMPTIME MUT NAME ?(: TYPE) ?ALIGN ?ADDSPACE ?SECTION ?(= INIT)
    before_mut: ?[]const u8 = null,
    mut: []const u8,
    name: []const u8,
    rhs: ?[]const u8 = null,
    tpe: ?[]const u8 = null,
};

/// Things we want from a declaration. Ast.full.VarDecl has
/// this info in a (much) less convenient way.
pub fn parseDecl(source: []const u8, ast: std.zig.Ast) ParsedDecl {
    const top_index = ast.rootDecls()[0];
    const main_node = ast.nodes.get(top_index);

    var res: ParsedDecl = .{ .mut = undefined, .name = undefined };

    const var_decl = ast.fullVarDecl(top_index).?;
    const comp = var_decl.ast;
    const tokStart = ast.tokens.items(.start);

    if (tokStart[comp.mut_token] != 0) {
        res.before_mut = source[0..tokStart[comp.mut_token]];
    }

    res.mut = source[tokStart[comp.mut_token]..tokStart[comp.mut_token + 1]];
    res.mut = std.mem.trimRight(u8, res.mut, &std.ascii.whitespace);

    const name_tok = comp.mut_token + 1;
    const name_start = tokStart[name_tok];
    const name_end = tokStart[name_tok + 1];
    res.name = source[name_start..name_end];
    res.name = std.mem.trimRight(u8, res.name, &std.ascii.whitespace);
    if (main_node.data.rhs != 0) {
        const start_token_idx = ast.firstToken(main_node.data.rhs);
        const start_offset = tokStart[start_token_idx];
        const end_offset = tokStart[ast.lastToken(main_node.data.rhs) + 1];
        res.rhs = source[start_offset..end_offset];
    }

    if (var_decl.ast.type_node != 0) {
        const start_tok = ast.firstToken(comp.type_node);
        var end_node = comp.type_node;
        for ([_]u32{ comp.align_node, comp.addrspace_node, comp.section_node }) |node_idx| {
            if (node_idx != 0) {
                end_node = node_idx;
            }
        }
        const end_tok = ast.lastToken(end_node);
        const start_offset = tokStart[start_tok];
        const end_offset = if (end_tok + 1 >= tokStart.len) source.len else tokStart[end_tok + 1];
        res.tpe = source[start_offset..end_offset];
    }
    return res;
}
