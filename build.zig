const std = @import("std");

pub fn build(b: *std.Build) !void {
    const opt = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable(.{
        .name = "OkBob",
        .root_source_file = b.path("src/main.zig"),
        .optimize = opt,
        .target = target,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run OkBob");
    run_step.dependOn(&run_cmd.step);
}
