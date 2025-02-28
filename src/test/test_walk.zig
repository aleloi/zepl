const std = @import("std");
const walk = @import("../Walk.zig");

const Set = std.StringHashMap(void);

const WalkArgs = struct {
    derefs: Set,
    ts: std.ArrayList(walk.Transformation),
    alloc: std.mem.Allocator,
    ast: std.zig.Ast,

    fn init(alloc: std.mem.Allocator, source: [:0]const u8) !WalkArgs {
        return WalkArgs{
            .derefs = Set.init(alloc),
            .ts = std.ArrayList(walk.Transformation).init(alloc),
            .alloc = alloc,
            .ast = try std.zig.Ast.parse(alloc, source, .zig),
        };
    }
    fn deinit(self: *WalkArgs) void {
        self.derefs.deinit();
        self.ts.deinit();
        self.ast.deinit(self.alloc);
    }
};

fn checkTrans(wa: WalkArgs, expected: [][]const u8) !void {
    // order depends on AST traversal order
    const alloc = std.testing.allocator;
    var actual = alloc.alloc([]const u8, wa.ts.items.len) catch unreachable;
    defer alloc.free(actual);
    for (wa.ts.items, 0..) |t, i| {
        switch (t) {
            .replace_with_deref => |idx| {
                actual[i] = wa.ast.tokenSlice(idx);
            },
        }
    }
    // sort actual
    const sliceComp = struct {
        fn lessThan(context: void, a: []const u8, b: []const u8) bool {
            _ = context;
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan;
    std.mem.sort([]const u8, actual, {}, sliceComp);
    std.mem.sort([]const u8, expected, {}, sliceComp);
    try std.testing.expectEqualDeep(actual, expected);
    for (actual, expected) |a, b| {
        try std.testing.expectEqualSlices(u8, a, b);
    }
}

test "test_walk" {
    var wa = try WalkArgs.init(std.testing.allocator, "var x: i32 = 0;");
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "test_walk_primitive_value" {
    var wa = try WalkArgs.init(std.testing.allocator, "var x: ?bool = null;");
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "test_walk_deref_free_var" {
    var wa = try WalkArgs.init(std.testing.allocator, "@import(\"std\").debug.print(\"{}\", .{my_free_variable_name});");
    defer wa.deinit();
    wa.derefs.put("my_free_variable_name", {}) catch unreachable;
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
    var expected = [1][]const u8{"my_free_variable_name"};
    try checkTrans(wa, &expected);
}

test "function_declaration" {
    if (false) {
        var wa = try WalkArgs.init(std.testing.allocator, "fn add(a: i32, b: i32) i32 { return a + b; }");
        defer wa.deinit();
        try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs, &wa.scope);
    }
    return error.SkipZigTest; // TODO: fix this
}

test "struct_declaration" {
    var wa = try WalkArgs.init(std.testing.allocator, "const Point = struct { x: i32, y: i32 };");
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "array_initialization" {
    var wa = try WalkArgs.init(std.testing.allocator, "const arr = [_]i32{1, 2, 3};");
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "switch_expression" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\const val: u8 = 1;
        \\const result = switch(val) {
        \\    0 => "zero",
        \\    1 => "one",
        \\    else => "other",
        \\};
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "if_statement" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\const x = 10;
        \\if (x > 5) {
        \\    const y = 20;
        \\} else {
        \\    const y = 30;
        \\}
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "while_loop" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\var i: usize = 0;
        \\while (i < 10) : (i += 1) {
        \\    const x = i * 2;
        \\}
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "for_loop" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\const items = [_]u8{1, 2, 3};
        \\for (items) |item| {
        \\    const doubled = item * 2;
        \\}
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "error_handling" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\fn mayFail() !void {
        \\    return error.Failed;
        \\}
        \\
        \\fn test() void {
        \\    mayFail() catch |err| {
        \\        const msg = @errorName(err);
        \\    };
        \\}
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "comptime_block" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\comptime {
        \\    var x: i32 = 10;
        \\    var y: i32 = 20;
        \\    const z = x + y;
        \\}
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "defer_statement" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\fn test() void {
        \\    var x: i32 = 10;
        \\    defer x += 1;
        \\}
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "slice_operation" {
    var wa = try WalkArgs.init(std.testing.allocator,
        \\fn test() void {
        \\    const arr = [_]u8{1, 2, 3, 4, 5};
        \\    const slice = arr[1..3];
        \\}
    );
    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
}

test "multiple_free_vars" {
    if (false) {
        var wa = try WalkArgs.init(std.testing.allocator,
            \\fn test() void {
            \\    const result = free_var_1 + free_var_2 * free_var_3;
            \\}
        );
        defer wa.deinit();
        wa.derefs.put("free_var_1", {}) catch unreachable;
        wa.derefs.put("free_var_2", {}) catch unreachable;
        wa.derefs.put("free_var_3", {}) catch unreachable;
        try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
        var expected = [_][]const u8{ "free_var_1", "free_var_2", "free_var_3" };
        try checkTrans(wa, &expected);
    }
    return error.SkipZigTest; // TODO: fix this
}

test "struct pseudo shadowing" {
    const src =
        \\const X = struct { var x: i32 };
        \\std.debug.print("X.x: {s}\n", .{X.x});
        \\X.x = x;
    ;
    var wa = try WalkArgs.init(std.testing.allocator, src);
    wa.derefs.put("x", {}) catch unreachable;
    // only the last 'x' should be dereferenced

    defer wa.deinit();
    try walk.findTransformations(wa.alloc, &wa.ast, &wa.ts, &wa.derefs);
    var expected = [_][]const u8{"x"};
    try checkTrans(wa, &expected);

    // Check that we found the right 'x' (it's the last 'x' in the source code).
    switch (wa.ts.items[0]) {
        .replace_with_deref => |idx| {
            const found = wa.ast.tokenSlice(idx);
            try std.testing.expectEqual(&found[0], &src[src.len - 2]);
        },
    }
}
