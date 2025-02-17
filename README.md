## Zepl

Experimental Zig REPL.

### Usage
![examples/zepl_cast.svg](examples/zepl_cast.svg)

```C
$ git clone https://github.com/aleloi/zepl.git && cd zepl
$ zig build
$ ./zig-out/bin/zepl
zepl> var x: i32 = 123;
zepl> @import("std").debug.print("interactive zig!\n", .{});
 interactive zig!
 interactive zig!
zepl> const alloc = @import("std").heap.page_allocator;
 mem.Allocator{ .ptr = anyopaque@0, .vtable = mem.Allocator.VTable{ ... } }
 mem.Allocator{ .ptr = anyopaque@0, .vtable = mem.Allocator.VTable{ ... } }
zepl> x
 123
 123
zepl> @import("builtin").zig_version
 0.13.0
 0.13.0
zepl> const std = @import("std");
zepl> std.SemanticVersion.parse
 fn ([]const u8) @typeInfo(@typeInfo(@TypeOf(SemanticVersion.parse)).Fn.return_type.?).ErrorUnion.error_set!SemanticVersion@1032c0930
 fn ([]const u8) @typeInfo(@typeInfo(@TypeOf(SemanticVersion.parse)).Fn.return_type.?).ErrorUnion.error_set!SemanticVersion@1032c0930
zepl> std.json.parseFromSlice(struct {x: i32, y:i32}, alloc.*, "{\"x\": 10, \"y\": 0}", .{}) catch |err| err
 json.static.Parsed(snippet_4.__snippet_4__struct_1667){ .arena = {...} , .state = {...}, .end_index = 0, .value = snippet_4.__snippet_4__struct_1667{ .x = 10, .y = 0 } }
// suppose testfile.zig has `pub fn sqr(i32) i32` and `pub var string_constant = "abc"`
zepl> const tst = @import("testfile.zig");
zepl> tst.string_constant
{ 97, 98, 99 }
// change the constant to "123"
zepl> tst.string_constant
{ 49, 50, 51 }
```


### How it works
TDLR: check the zig docs https://aleloi.github.io/zepl/ 

If you set the log level to .debug in `main.zig` it prints
```python
```python
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

It tries to compile each command by itself and dynamically load it in the REPL process. We need the context of previous snippets which is included though lots of `@extern` and `@export` declarations. All comptime statements have to be zeplayed for each snippet. When we can't `@export` a variable, we export its adress. That's the reason for why your non-pointer types change to pointers.
It tries to compile each command by itself and dynamically load it in the REPL process. We need the context of previous snippets which is included though lots of `@extern` and `@export` declarations. All comptime statements have to be zeplayed for each snippet. When we can't `@export` a variable, we export its adress. That's the reason for why your non-pointer types change to pointers.

### Missing features, contributors welcome!
A list of features that are relatively easy to implement:
* handle more input, e.g. `command1; command2;`, `command; // comment`, `command_returning_error_without_catch_or_try;`
* code completion. E.g. feed a command history to ZLS and fetch completions.
* syntax highlighting
* `@export` for functions, not just variables. I think it only works for ABI-compatible param types.
* searchable history
* multiline input
* custom build-file to list additional dependencies.
* describe the semantics of what commands are allowed. Currenly it just tries to do a few (up to 3) versions of each command until it finds one that compiles.
* make it build with 0.14.0-pre
* make it respect `const` - I think I made a bug so that all non-ABI compatible vars are mutable


More complex:
* find free variables in the input snippet and only add their declarations in the context. std.zig.Ast doesn't make it easy.
* automatically dereference variables that we converted to pointers

A list of features that I'd like to have but don't know how to implement:
* don't re-evaluate the whole chain of comptime expressions on each snippet. ZLS uses a comptime interpreter somehow, look in to that?
* don't recompile non-generic functions. This requires understanding more of the compiler. Dynamic loading is not enough.

* Gurus say that [hot-reloading](https://github.com/ziglang/zig/issues/68) and [`--watch`](https://ziggit.dev/t/initial-implementation-of-zig-build-watch-just-landed-in-master-branch/5117) is relevant.

* Gurus say that [hot-reloading](https://github.com/ziglang/zig/issues/68) and [`--watch`](https://ziggit.dev/t/initial-implementation-of-zig-build-watch-just-landed-in-master-branch/5117) is relevant.

Chores
* stop leaking memory
* add a few tests
* make a test setup for feeding container-level statements one-by-one into the zepl. It will definitely crash for some.



### Known issues
Most variables enter the scope as pointers. When you type `const alloc = std.heap.page_allocator;`, you get `alloc: *std.mem.Allocator` instead of `alloc: std.mem.Allocator`. Sometimes you don't even notice, because members can be accessed on a struct without explicit dereferencing. 

Modules loaded with `const otherfile = @import("otherfile.zig")` are re-compiled on every snippet, meaning that changing `otherfile.mutable_var` from within the repl has no effect.

It allows a bit too much. E.g. `var x: i32 = x;` is OKAY because it's processed into
```zig
  // context
export var x: i32  = undefined;
  // export
  // comptime
export fn __snippet_1 () void {
    x = x;

}
  // side effects

```