### 24-02-2025
* added syntax highlighting and possibly too many external deps. New feature: after you type a command,
  zepl removes it and prints back a highlighted version.
* now under MIT licence. Checkd licences of all deps for compatibility. They are also all under MIT.
* generated files are now under generated/ dir.
* proof-of-concept feature: you can set log level from within the interpreter. Through extern/export of a std.log.Level variable. You do e.g. `log_level.* = .debug;`. TODO: put this and `fn highlight` and future ones in an importable module so you'd do `@import("zepl").log_level.* = .debug;`. Similar for the `print("{any}", .{user_input})` that's generated in the snippets.

Next up: automatical AST rewriting so that you don't need to dereference, and so that we can ingest whole files. Also planned - documentation for how to set up zepl to make your deps importable.

### one week earlier
* initial release.