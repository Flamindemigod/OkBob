const std = @import("std");

pub fn build(b: *std.Build) !void {
    const opt = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const sqlite = b.addModule("sqlite", .{
        .root_source_file = b.path("external/zig-sqlite/sqlite.zig"),
    });

    sqlite.addCSourceFiles(.{
        .files = &[_][]const u8{
            "external/zig-sqlite/c/workaround.c",
        },
        .flags = &[_][]const u8{"-std=c99"},
    });
    sqlite.addIncludePath(b.path("external/zig-sqlite/c"));

    const exe = b.addExecutable(.{
        .name = "OkBob",
        .root_source_file = b.path("src/main.zig"),
        .optimize = opt,
        .target = target,
    });
    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");
    exe.root_module.addImport("sqlite", sqlite);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run OkBob");
    run_step.dependOn(&run_cmd.step);
}
