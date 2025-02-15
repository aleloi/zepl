## Zepl

Experimental Zig REPL.

### Usage

```
zig build
./zig-out/bin/zepl
zepl> var x: i32 = 123;
zepl> @import("std").debug.print("interactive zig!\n", .{});
interactive zig!
zepl> const alloc = @import("std").heap.page_allocator;
mem.Allocator{ .ptr = anyopaque@0, .vtable = mem.Allocator.VTable{ ... } }
zepl> x
123
zepl> @import("builtin").zig_version
0.13.0
zepl> const std = @import("std");
zepl> std.SemanticVersion.parse
fn ([]const u8) @typeInfo(@typeInfo(@TypeOf(SemanticVersion.parse)).Fn.return_type.?).ErrorUnion.error_set!SemanticVersion@1032c0930
zepl> std.json.parseFromSlice(struct {x: i32, y:i32}, alloc.*, "{\"x\": 10, \"y\": 0}", .{}) catch |err| err
json.static.Parsed(snippet_4.__snippet_4__struct_1667){ .arena = {...} , .state = {...}, .end_index = 0, .value = snippet_4.__snippet_4__struct_1667{ .x = 10, .y = 0 } }
```

### Examples
TODO put make a gif and put it here

### How it works
If you set the log level to .debug in `main.zig` it prints
```
zepl> var x: i32 = 0;
  [debug] (zepl_parse)  ParseError as a value, trying container-level member
  [debug] (zepl_comp)  wrote tmpfile_0.zig, checking if it compiles
  [debug] (zepl_comp)  tmpfile_0.zig compilation exit code: 0
  [debug] (zepl)  Parsed AST: parse.ParseResult.Tag.container_level_decl
  [debug] (zepl_prpc)  Top level is: zig.Ast.Node.Tag.simple_var_decl
  [debug] (zepl_prpc)  parsed decl, before mut is: ''
    mut is: 'var'
    name is: 'x'
    tpe is 'i32 '
    rhs is '0'
  [debug] (zepl_prpc)  trying exporting as C-ABI value ;y
  [debug] (zepl_comp)  wrote tmpfile_1.zig, checking if it compiles
  [debug] (zepl_comp)  tmpfile_1.zig compilation exit code: 0
  [debug] (zepl_comp)  wrote tmpfile_2.zig, checking if it compiles
  [debug] (zepl_comp)  tmpfile_2.zig compilation exit code: 0
  [debug] (zepl_comp)  compiling snippet_1.zig
  [debug] (zepl_comp)  compiled snippet_1.zig into ./libsnippet_1.dylib
  [debug] (zepl)  loading dylib: ./libsnippet_1.dylib
```

It tries to compile each command by itself and dynamically load it in the REPL process. We need the context of previous snippets which is included though lots of `@extern` and `@export` declarations. All comptime statements have to be zeplayed for each snippet. When we can't `@export` a variable, we export its adress. That means that e.g. when you write `zepl> const alloc = std.heap.page_allocator;`, `alloc` will be `*std.mem.Allocator`.


### Missing features, contributors welcome!
A list of features that are relatively easy to implement:
* visible compilation errors
* handle more input, e.g. `command1; command2;`, `command; // comment`, `command_returning_error_without_catch_or_try;`
* code completion. E.g. feed a command history to ZLS and fetch completions.
* syntax highlighting
* `@export` for functions, not just variables. I think it only works for ABI-compatible param types.
* searchable history
* multiline input
* custom build-file to list additional dependencies.
* describe the semantics of what commands are allowed. Currenly it just tries to do a few (up to 3) versions of each command until it finds one that compiles.
* make it build with 0.14


More complex:
* find free variables in the input snippet and only add their declarations in the context. std.zig.Ast doesn't make it easy.
* automatically dereference variables that we converted to pointers

A list of features that I'd like to have but don't know how to implement:
* don't re-evaluate the whole chain of comptime expressions on each snippet. ZLS uses a comptime interpreter somehow, look in to that?
* don't recompile non-generic functions. This requires understanding more of the compiler. Dynamic loading is not enough.
* Gurus say that hot-reloading and the `--watch`

Chores
* stop leaking memory
* add a few tests
* make a test setup for feeding container-level statements one-by-one into the zepl. It will definitely crash for some.