### 25-02-2025
* added breakpoints. If user code calls `zepl_externs.breakpoint()` from anywhere, it immediately returns to the zepl prompt. That's done by libc setjmp/longjmp. I don't think you can do this from zig; I think setjmp has to be inlined and be in an active stack frame of the one that calls breakpoints. Also, https://github.com/ziglang/zig/issues/1656 says it's not supported. Seems to work for me when calling from C in 0.13.0 though. I  made `src/breakpoint.c` that sets up the long jump destination frame and calls user code from it.
Example:
```
zepl> fn b() void { const std = @import("std"); std.debug.print("before\n", .{}); zepl_externs.breakpoint(); std.debug.print("should not run\n", .{}); }

zepl> b()
before
[call with] continuing after from breakpoint. Breakpoint hit: 1
```

* added `zepl_externs` and `zepl_exports` for organizing exports/externs. 

### 24-02-2025
* added syntax highlighting and possibly too many external deps. New feature: after you type a command,
  zepl removes it and prints back a highlighted version.
* now under MIT licence. Checkd licences of all deps for compatibility. They are also all under MIT.
* generated files are now under generated/ dir.
* proof-of-concept feature: you can set log level from within the interpreter. Through extern/export of a std.log.Level variable. You do e.g. `log_level.* = .debug;`. TODO: put this and `fn highlight` and future ones in an importable module so you'd do `zepl_externs.log_level.* = .debug;`. Similar for the `print("{any}", .{user_input})` that's generated in the snippets.

Next up: automatical AST rewriting so that you don't need to dereference, and so that we can ingest whole files. Also planned - documentation for how to set up zepl to make your deps importable.

### one week earlier
* initial release.