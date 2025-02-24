//! Process a snippet into compilable code. Tries different ways until one compiles.
const std = @import("std");
pub const repl_context = @import("repl_context.zig");
const ReplContext = repl_context.ReplContext;
pub const parse = @import("parse.zig");
pub const compilation = @import("compilation.zig");

const log = std.log.scoped(.zepl_prpc);

/// This plus history is what we need to run a snippet.
pub const PreprocResult = struct {
    /// if snippet is `var x: i32 = ...`, this can be  `extern var x: i32;`
    extern_def: ?[]const u8 = null,
    /// if snippet is `var x = my_fun();`, this can be  `export var x: @TypeOf(my_fun()) = undefined;`
    export_symbol: ?[]const u8 = null,

    /// if snippet is `const x = i32;`, this is `const x = i32;`
    comptime_stmt: ?[]const u8 = null,
    /// if snippet is `x = f()`, this can be  `export fn __snippet_{d}() void { x = f(); }`
    side_effects: []const u8 = undefined,

    /// Each snippet has a unique side effects function name. Sometimes the function is empty.
    pub fn sideEffectsName(allocator: std.mem.Allocator, snippet_num: u32) ![:0]const u8 {
        return try std.fmt.allocPrintZ(allocator, "__snippet_{d}", .{snippet_num});
    }

    /// String manip to put code into a function.
    pub fn makeSideEffects(allocator: std.mem.Allocator, snippet_num: u32, actual_side_effect: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(allocator,
            \\export fn __snippet_{d} () void {{
            \\  {s}
            \\}}
            \\
        , .{ snippet_num, actual_side_effect });
    }
};

/// Context to preprocess a snippet. We need the history and results of parsing.
pub const PreprocArgs = struct {
    snippet_num: u32,
    source: []const u8,
    parsed: parse.ParseResult,
    rc: ReplContext,
    allocator: std.mem.Allocator,
};

const Error = error{PreprocError};

fn preprocDecl(pa: PreprocArgs, parsed: parse.ParsedDecl) !PreprocResult {
    log.debug("  trying exporting as C-ABI value ;y\n", .{});

    const exportDecl = try std.fmt.allocPrint(pa.allocator, "export var {s}: {s} = undefined;\n", .{ parsed.name, parsed.tpe.? });
    const assignment = try std.fmt.allocPrint(pa.allocator, "  {s} = {s};\n", .{ parsed.name, parsed.rhs orelse "undefined" });
    const snippet = try std.fmt.allocPrint(pa.allocator,
        \\{s}
        \\{s}
        \\
        \\ fn __snippet_side_effects_{d}() void {{
        \\   {s}
        \\ }}
        \\
    , .{ pa.rc.current_context.items, exportDecl, pa.snippet_num, assignment });
    if ((try compilation.snippetChecksOut(pa.allocator, snippet)).isSuccess()) {
        //log.debug("  wow, it compiles!\n", .{});
        return .{
            .extern_def = try std.fmt.allocPrint(pa.allocator, "extern {s} {s}: {s}; \n", .{ parsed.mut, parsed.name, parsed.tpe.? }),
            .export_symbol = exportDecl,
            .side_effects = try PreprocResult.makeSideEffects(pa.allocator, pa.snippet_num, assignment),
        };
    }
    log.debug("  no compile ;y\n", .{});

    log.debug("  trying exporting as ptr ;y\n", .{});

    const exportPtrDecl = try std.fmt.allocPrint(pa.allocator,
        \\var {s}: {s} = undefined;
        \\var {s}__ptr_snippet_{d} = &{s};
        \\ comptime {{
        \\    @export({s}__ptr_snippet_{d}, .{{ .name = "{s}" }});
        \\ }}
        \\
    , .{ parsed.name, parsed.tpe.?, parsed.name, pa.snippet_num, parsed.name, parsed.name, pa.snippet_num, parsed.name });
    const snippetPtr = try std.fmt.allocPrint(pa.allocator,
        \\{s}  // context
        \\{s}  // export stuff
        \\
        \\ pub fn __snippet_side_effects_{d}() void {{
        \\   {s}
        \\ }}
        \\
    , .{ pa.rc.current_context.items, exportPtrDecl, pa.snippet_num, assignment });
    if ((try compilation.snippetChecksOut(pa.allocator, snippetPtr)).isSuccess()) {
        //log.debug("  wow, it compiles!\n", .{});
        return .{
            .extern_def = try std.fmt.allocPrint(pa.allocator, "extern {s} {s}: *({s}); \n", .{ parsed.mut, parsed.name, parsed.tpe.? }),
            .export_symbol = exportPtrDecl,
            .side_effects = try PreprocResult.makeSideEffects(pa.allocator, pa.snippet_num, assignment),
        };
    }
    log.debug("  no compile ;y\n", .{});
    log.debug("  Trying top-level comptime decl ;y\n", .{});

    const snippetCmptm = try std.fmt.allocPrint(pa.allocator,
        \\{s}  // context, context.items
        \\{s}  // comptime, pa.source
        \\
        \\ export fn __snippet_side_effects_{d}() void {{  // pa.snippet_num
        \\    
        \\        const __std = @import("std");
        \\ const inputZ = __std.fmt.allocPrintZ(__std.heap.page_allocator, "{{any}}\n", 
        \\   .{{switch (@typeInfo(@TypeOf({s}))) {{
        \\      .Fn => &({s}),
        \\       else => {s},
        \\   }} }}) catch unreachable;        
        \\       
        \\  highlight(inputZ);    
        \\ }}
        \\
    , .{ pa.rc.current_context.items, pa.source, pa.snippet_num, parsed.name, parsed.name, parsed.name });
    const comp_out = try compilation.snippetChecksOut(pa.allocator, snippetCmptm);
    if (comp_out.isSuccess()) {
        return .{ .comptime_stmt = pa.source, .side_effects = try PreprocResult.makeSideEffects(pa.allocator, pa.snippet_num, "") };
    }
    log.info("  comp output: {s}", .{comp_out.stderr});
    return error.PreprocError;
}

fn preprocContainerLevel(pa: PreprocArgs) !PreprocResult {
    const rootDecls = pa.parsed.ast.rootDecls();
    if (rootDecls.len != 1) return error.NotOneRootDecl;
    const top_index = rootDecls[0];
    const top_tag = pa.parsed.ast.nodes.items(.tag)[top_index];
    log.debug("  Top level is: {}\n", .{top_tag});
    switch (top_tag) {
        .global_var_decl, .local_var_decl, .aligned_var_decl, .simple_var_decl => {
            var parsed = parse.parseDecl(pa.source, pa.parsed.ast);
            parsed.tpe = parsed.tpe orelse (std.fmt.allocPrint(pa.allocator, "@TypeOf( {s} )", .{parsed.rhs.?}) catch unreachable);
            log.debug(
                \\  parsed decl, before mut is: '{s}'
                \\    mut is: '{s}'
                \\    name is: '{s}'
                \\    tpe is '{s}'
                \\    rhs is '{s}'
                \\
            , .{ parsed.before_mut orelse "", parsed.mut, parsed.name, parsed.tpe orelse "", parsed.rhs orelse "" });
            return preprocDecl(pa, parsed);
        },
        else => {
            return .{
                .side_effects = try PreprocResult.makeSideEffects(pa.allocator, pa.snippet_num, ""),
                .comptime_stmt = pa.source,
            };
        },
    }
    return .{ .side_effects = "" };
}

/// Given history and parsed snippet, return what code to run and what to put in future snippet context.
pub fn preprocess(pa: PreprocArgs) !PreprocResult {
    switch (pa.parsed.tag) {
        .value => {
            const print_stmt = try std.fmt.allocPrint(pa.allocator,
                \\
                \\        const __std = @import("std");
                \\ const inputZ = __std.fmt.allocPrintZ(__std.heap.page_allocator, "{{any}}\n", 
                \\   .{{switch (@typeInfo(@TypeOf({s}))) {{
                \\      .Fn => &({s}),
                \\       else => {s},
                \\   }} }}) catch unreachable;        
                \\       
                \\  highlight(inputZ);    
                \\ 
            , .{ pa.source, pa.source, pa.source });
            const side_effects = try std.fmt.allocPrint(pa.allocator, "export fn __snippet_{d}() void {{ \n {s} \n }}\n", .{ pa.snippet_num, print_stmt });
            return .{ .side_effects = side_effects };
        },
        .block_level => {
            return .{
                .side_effects = try PreprocResult.makeSideEffects(pa.allocator, pa.snippet_num, pa.source),
            };
        },
        .container_level_decl => {
            return preprocContainerLevel(pa);
        },
    }
}
