const std = @import("std");
const string = []const u8;
const gpa = std.heap.c_allocator;

const inquirer = @import("inquirer");
const knownfolders = @import("known-folders");
const ini = @import("ini");
const u = @import("./../util/index.zig");

//
//

const s_in_y = std.time.s_per_week * 52;

pub fn execute(args: [][]u8) !void {
    _ = args;

    std.debug.print("This utility will walk you through creating a zig.mod file.\n", .{});
    std.debug.print("That will give a good launching off point to get your next project started.\n", .{});
    std.debug.print("Use `zigmod aq add <pkg>` to add a dependency from https://aquila.red/\n", .{});
    std.debug.print("Press ^C at any time to quit.\n", .{});
    std.debug.print("\n", .{});

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    const cwd = std.fs.cwd();

    const id = try inquirer.answer(stdout, "ID (this gets autogenerated):", string, "{s}", try u.random_string(gpa, 48));

    const ptype = try inquirer.forEnum(stdout, stdin, "Are you making an application or a library?", gpa, enum { exe, lib }, null);

    const name = try inquirer.forString(stdout, stdin, "package name:", gpa, u.detect_pkgname(gpa, u.try_index(string, args, 0, ""), "") catch |err| switch (err) {
        error.NoBuildZig => {
            u.fail("init requires a build.zig file", .{});
        },
        else => return err,
    });

    const entry = if (ptype == .lib) try inquirer.forString(stdout, stdin, "package entry point:", gpa, u.detct_mainfile(gpa, u.try_index(string, args, 1, ""), null, name) catch |err| switch (err) {
        error.CantFindMain => null,
        else => return err,
    }) else null;

    const license = try inquirer.forString(stdout, stdin, "license:", gpa, null);

    const description = try inquirer.forString(stdout, stdin, "description:", gpa, null);

    std.debug.print("\n", .{});
    std.debug.print("About to write local zig.mod:\n", .{});

    std.debug.print("\n", .{});
    switch (ptype) {
        .exe => try writeExeManifest(stdout, id, name, license, description),
        .lib => try writeLibManifest(stdout, id, name, entry.?, license, description),
    }

    std.debug.print("\n", .{});
    switch (try inquirer.forConfirm(stdout, stdin, "Is this okay?", gpa)) {
        false => {
            std.debug.print("okay. quitting...", .{});
            return;
        },
        true => {
            const file = try cwd.createFile("zig.mod", .{});
            defer file.close();
            const w = file.writer();
            switch (ptype) {
                .exe => try writeExeManifest(w, id, name, license, description),
                .lib => try writeLibManifest(w, id, name, entry.?, license, description),
            }
            std.debug.print("\n", .{});
            u.print("Successfully initialized new package {s}!\n", .{name});
        },
    }

    // ask about LICENSE
    // disabled because detectlicense is slow

    // if (!(try u.does_file_exist(null, "LICENSE"))) {
    //     if (detectlicense.licenses.find(license)) |text| {
    //         if (try inquirer.forConfirm(stdout, stdin, "It appears you don't have a LICENSE file defined, would you like init to add it for you?", gpa)) {
    //             var realtext = text;
    //             realtext = try std.mem.replaceOwned(u8, gpa, realtext, "<year>", try inquirer.answer(
    //                 stdout,
    //                 "year:",
    //                 string,
    //                 "{s}",
    //                 try std.fmt.allocPrint(gpa, "{d}", .{1970 + @divFloor(std.time.timestamp(), s_in_y)}),
    //             ));
    //             realtext = try std.mem.replaceOwned(u8, gpa, realtext, "<copyright holders>", try inquirer.forString(
    //                 stdout,
    //                 stdin,
    //                 "copyright holder's name:",
    //                 gpa,
    //                 try guessCopyrightName(),
    //             ));

    //             const file = try cwd.createFile("LICENSE", .{});
    //             defer file.close();
    //             const w = file.writer();
    //             try w.writeAll(realtext);
    //         }
    //     }
    // }

    // ask about .gitignore
    if (try u.does_folder_exist(".git")) {
        const do = try inquirer.forConfirm(stdout, stdin, "It appears you're using git. Do you want init to add Zigmod to your .gitignore?", gpa);
        if (do) {
            const exists = try u.does_file_exist(null, ".gitignore");
            const file: std.fs.File = try (if (exists) cwd.openFile(".gitignore", .{ .read = true, .write = true }) else cwd.createFile(".gitignore", .{}));
            defer file.close();
            const len = try file.getEndPos();
            if (len > 0) try file.seekTo(len - 1);
            const w = file.writer();
            if (len > 0 and (try file.reader().readByte()) != '\n') {
                try w.writeAll("\n");
            }
            if (!exists) try w.writeAll("zig-*\n");
            try w.writeAll(".zigmod\n");
            try w.writeAll("deps.zig\n");
        }
    }

    // ask about .gitattributes
    if (try u.does_folder_exist(".git")) {
        const do = try inquirer.forConfirm(stdout, stdin, "It appears you're using git. Do you want init to add Zigmod to your .gitattributes?", gpa);
        if (do) {
            const exists = try u.does_file_exist(null, ".gitattributes");
            const file: std.fs.File = try (if (exists) cwd.openFile(".gitattributes", .{ .read = true, .write = true }) else cwd.createFile(".gitattributes", .{}));
            defer file.close();
            const len = try file.getEndPos();
            if (len > 0) try file.seekTo(len - 1);
            const w = file.writer();
            if (len > 0 and (try file.reader().readByte()) != '\n') {
                try w.writeAll("\n");
            }
            try w.writeAll(
                \\# See https://github.com/ziglang/zig-spec/issues/38
                \\*.zig text eol=lf
                \\zig.mod text eol=lf
                \\zigmod.* text eol=lf
                \\zig.mod linguist-language=YAML
                \\zig.mod gitlab-language=yaml
                \\
            );
        }
    }
}

pub fn writeExeManifest(w: std.fs.File.Writer, id: string, name: string, license: ?string, description: ?string) !void {
    try w.print("id: {s}\n", .{id});
    try w.print("name: {s}\n", .{name});
    if (license) |_| try w.print("license: {s}\n", .{license.?});
    if (description) |_| try w.print("description: {s}\n", .{description.?});
    try w.print("dev_dependencies:\n", .{});
}

pub fn writeLibManifest(w: std.fs.File.Writer, id: string, name: string, entry: string, license: string, description: string) !void {
    try w.print("id: {s}\n", .{id});
    try w.print("name: {s}\n", .{name});
    try w.print("main: {s}\n", .{entry});
    try w.print("license: {s}\n", .{license});
    try w.print("description: {s}\n", .{description});
    try w.print("dependencies:\n", .{});
}

fn guessCopyrightName() !?string {
    const home = (try knownfolders.open(gpa, .home, .{})).?;
    if (!(try u.does_file_exist(home, ".gitconfig"))) return null;
    const file = try home.openFile(".gitconfig", .{});
    const content = try file.reader().readAllAlloc(gpa, 1024 * 1024);
    var iniO = try ini.parseIntoMap(content, gpa);
    return iniO.map.get("user.name");
}
