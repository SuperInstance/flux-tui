const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core VM library module
    _ = b.addModule("flux_vm", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests
    const test_step = b.step("test", "Run all VM tests");
    const test_artifact = b.addTest(.{
        .name = "flux_vm_tests",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(test_artifact).step);
}
