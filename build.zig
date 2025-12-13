const std = @import("std");

pub fn build(b: *std.Build) void {
    const opt = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{ .name = "radio", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = opt,
        .target = target,
    }) });

    exe.linkLibC();
    exe.linkSystemLibrary("cfitsio");
    b.installArtifact(exe);
}
