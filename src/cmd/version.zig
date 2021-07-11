const std = @import("std");
const gpa = std.heap.c_allocator;
const builtin = std.builtin;

const u = @import("./../util/index.zig");

//
//

pub fn execute(args: [][]u8) !void {
    _ = args;

    const root = @import("root");
    const build_options = if (@hasDecl(root, "build_options")) root.build_options else struct {};
    const version = if (@hasDecl(build_options, "version")) build_options.version else "unknown";

    const stdout = std.io.getStdOut();
    const w = stdout.writer();

    try w.writeAll("zigmod");

    try w.print(" {s}", .{version});
    if (std.mem.eql(u8, version, "dev")) {
        try w.print(
            "-{s}",
            .{
                (try u.git_rev_HEAD(gpa, std.fs.cwd()))[0..7],
            },
        );
    }

    try w.print(" {s}", .{@tagName(builtin.os.tag)});

    try w.print(" {s}", .{@tagName(builtin.cpu.arch)});

    try w.print(" {s}", .{@tagName(builtin.abi)});

    try w.writeAll("\n");
}
