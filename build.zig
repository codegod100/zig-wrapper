const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // =========================================================================
    // Step 1: Build Rust Library
    // =========================================================================
    const cargo_build = b.addSystemCommand(&[_][]const u8{
        "cargo",
        "build",
        "--release",
        "--lib",
        "--features",
        "gtk",
    });
    cargo_build.cwd = b.path(".");

    // =========================================================================
    // Step 2: Create Zig Application
    // =========================================================================
    // Create root module with target and optimize
    const root_mod = b.createModule(.{
        .root_source_file = b.path("test_app.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add wry wrapper module import
    const wry_module = b.createModule(.{
        .root_source_file = b.path("wry.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("wry", wry_module);

    const exe = b.addExecutable(.{
        .name = "wry_window_app",
        .root_module = root_mod,
    });

    // Link against Rust library
    exe.linkSystemLibrary("wry_zig_wrapper");
    exe.addLibraryPath(.{ .cwd_relative = "target/release" });

    // CRITICAL FIX: Link against libc to fix Zig 0.15 PLT/GOT bug
    // See: https://github.com/ziglang/zig/issues/12010
    exe.linkSystemLibrary("c");

    // Make exe depend on cargo build
    exe.step.dependOn(&cargo_build.step);

    // =========================================================================
    // Install & Run Steps
    // =========================================================================
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run wry window application");
    run_step.dependOn(&run_cmd.step);

    // Add install-libs step to copy Rust .so file
    const install_libs = b.addInstallFile(
        b.path("target/release/libwry_zig_wrapper.so"),
        "lib/libwry_zig_wrapper.so",
    );
    b.getInstallStep().dependOn(&install_libs.step);

    // Add "install-all" step that installs both exe and lib
    const install_all = b.step("install-all", "Install app and all libraries");
    install_all.dependOn(b.getInstallStep());

    // Add "run-local" step that runs with LD_LIBRARY_PATH
    const run_local_cmd = b.addSystemCommand(&[_][]const u8{
        "./zig-out/bin/wry_window_app",
    });
    run_local_cmd.cwd = b.path(".");

    // Set LD_LIBRARY_PATH to find Rust library
    run_local_cmd.has_side_effects = true;
    run_local_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", "zig-out/lib:$LD_LIBRARY_PATH");

    if (b.args) |args| {
        run_local_cmd.addArgs(args);
    }

    const run_local_step = b.step("run-local", "Run app (sets LD_LIBRARY_PATH automatically)");
    run_local_step.dependOn(b.getInstallStep());
    run_local_step.dependOn(&run_local_cmd.step);
}
