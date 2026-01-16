const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    // Create the test executable
    const exe = b.addExecutable(.{
        .name = "test_built",
        .root_source_file = "test_ptr_export.zig",
        .target = target,
        .optimize = mode,
    });

    exe.linkLibrary(b.optionallyDynamicLibrary("libwry_zig_wrapper.so", .{ .paths = &.{"lib"} }));
    b.installArtifact(exe);
}
