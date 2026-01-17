const std = @import("std");
const builtin = @import("builtin");

const AppDir = "wry-zig-wrapper.AppDir";
const AppImage = "wry-zig-wrapper-x86_64.AppImage";
const AppImageToolUrl =
    "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage";

const AppRunContents =
    "#!/bin/bash\n" ++
    "SELF=$(readlink -f \"$0\")\n" ++
    "HERE=${SELF%/*}\n" ++
    "export LD_LIBRARY_PATH=\"${HERE}/usr/lib:${LD_LIBRARY_PATH}\"\n" ++
    "export XDG_DATA_DIRS=\"${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/share}\"\n" ++
    "exec \"${HERE}/usr/bin/wry_window_app\" \"$@\"\n";

const DesktopContents =
    "[Desktop Entry]\n" ++
    "Name=Wry Zig Wrapper\n" ++
    "Comment=File Browser built with Zig and Wry\n" ++
    "Exec=wry_zig_wrapper\n" ++
    "Icon=wry-zig-wrapper\n" ++
    "Type=Application\n" ++
    "Categories=Utility;FileTools;\n" ++
    "Terminal=false\n" ++
    "StartupNotify=true\n";

const SvgContents =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ++
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" width=\"256\" height=\"256\">\n" ++
    "    <defs>\n" ++
    "        <linearGradient id=\"grad1\" x1=\"0%\" y1=\"0%\" x2=\"100%\" y2=\"100%\">\n" ++
    "            <stop offset=\"0%\" style=\"stop-color:#667eea;stop-opacity:1\" />\n" ++
    "            <stop offset=\"100%\" style=\"stop-color:#764ba2;stop-opacity:1\" />\n" ++
    "        </linearGradient>\n" ++
    "    </defs>\n" ++
    "    <rect width=\"256\" height=\"256\" rx=\"40\" fill=\"url(#grad1)\"/>\n" ++
    "    <text x=\"128\" y=\"128\" font-family=\"Arial, sans-serif\" font-size=\"80\" font-weight=\"bold\" fill=\"white\" text-anchor=\"middle\" dominant-baseline=\"middle\">Wry</text>\n" ++
    "    <rect x=\"76\" y=\"150\" width=\"104\" height=\"65\" rx=\"10\" fill=\"rgba(255,255,255,0.3)\"/>\n" ++
    "    <text x=\"128\" y=\"190\" font-family=\"monospace\" font-size=\"20\" fill=\"white\" text-anchor=\"middle\">Zig + Rust</text>\n" ++
    "</svg>\n";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const appimagetool = try resolveAppImageTool(allocator);

    try deleteTreeIfExists(AppDir);
    try std.fs.cwd().makePath(AppDir);
    try std.fs.cwd().makePath(AppDir ++ "/usr/bin");
    try std.fs.cwd().makePath(AppDir ++ "/usr/lib");
    try std.fs.cwd().makePath(AppDir ++ "/usr/share/applications");
    try std.fs.cwd().makePath(AppDir ++ "/usr/share/icons/hicolor/256x256/apps");

    try copyFile("zig-out/bin/wry_window_app", AppDir ++ "/usr/bin/wry_window_app");
    try copyFile("zig-out/lib/libwry_zig_wrapper.so", AppDir ++ "/usr/lib/libwry_zig_wrapper.so");

    try writeFile(AppDir ++ "/AppRun", AppRunContents, 0o755);
    try writeFile(AppDir ++ "/wry-zig-wrapper.desktop", DesktopContents, null);
    try copyFile(AppDir ++ "/wry-zig-wrapper.desktop", AppDir ++ "/usr/share/applications/wry-zig-wrapper.desktop");
    try writeFile(AppDir ++ "/wry-zig-wrapper.svg", SvgContents, null);
    try copyFile(AppDir ++ "/wry-zig-wrapper.svg", AppDir ++ "/usr/share/icons/hicolor/256x256/apps/wry-zig-wrapper.svg");

    const arch = try appImageArch();
    const arch_env = [_]EnvVar{.{ .key = "ARCH", .value = arch }};

    if (canUseFuse()) {
        try runCommand(allocator, &[_][]const u8{ appimagetool, AppDir, AppImage }, null, &arch_env);
    } else {
        try deleteTreeIfExists("/tmp/squashfs-root");
        try runCommand(allocator, &[_][]const u8{ appimagetool, "--appimage-extract" }, "/tmp", &arch_env);
        const app_run = "/tmp/squashfs-root/AppRun";
        try runCommand(allocator, &[_][]const u8{ app_run, AppDir, AppImage }, null, null);
    }
}

fn resolveAppImageTool(allocator: std.mem.Allocator) ![]const u8 {
    const env = std.process.getEnvVarOwned(allocator, "APPIMAGETOOL") catch null;
    if (env) |path| {
        if (fileExistsAbsolute(path)) {
            return path;
        }
        std.log.err("APPIMAGETOOL is set but not found: {s}", .{path});
        return error.FileNotFound;
    }

    const fallback = "/tmp/appimagetool";
    if (fileExistsAbsolute(fallback)) {
        return fallback;
    }

    std.log.info("appimagetool not found; downloading to {s}", .{fallback});
    try downloadAppImageTool(allocator, AppImageToolUrl, fallback);
    return fallback;
}

fn fileExistsAbsolute(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}

fn deleteTreeIfExists(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        try std.fs.deleteTreeAbsolute(path);
        return;
    }
    try std.fs.cwd().deleteTree(path);
}

fn copyFile(src: []const u8, dst: []const u8) !void {
    std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("missing required file: {s}", .{src});
            return err;
        },
        else => return err,
    };
}

fn writeFile(path: []const u8, contents: []const u8, mode: ?std.fs.File.Mode) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
    if (mode) |value| {
        try file.chmod(value);
    }
}

fn canUseFuse() bool {
    const file = std.fs.openFileAbsolute("/dev/fuse", .{}) catch return false;
    file.close();
    return true;
}

fn runCommand(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    cwd: ?[]const u8,
    env_overrides: ?[]const EnvVar,
) !void {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    if (cwd) |dir| {
        child.cwd = dir;
    }
    var envmap: ?std.process.EnvMap = null;
    defer if (envmap) |*map| map.deinit();
    if (env_overrides) |vars| {
        envmap = try std.process.getEnvMap(allocator);
        const map_ptr = &envmap.?;
        for (vars) |entry| {
            try map_ptr.put(entry.key, entry.value);
        }
        child.env_map = map_ptr;
    }
    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }
}

const EnvVar = struct {
    key: []const u8,
    value: []const u8,
};

fn appImageArch() ![]const u8 {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .arm => "arm",
        else => error.UnsupportedArch,
    };
}

fn downloadAppImageTool(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
) !void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var req = try client.request(.GET, uri, .{});
    defer req.deinit();
    try req.sendBodiless();

    var redirect_buffer: [4096]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);
    if (response.head.status != .ok) return error.DownloadFailed;

    var out = try std.fs.createFileAbsolute(dest_path, .{ .truncate = true });
    defer out.close();

    var transfer_buffer: [8192]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    var buf: [8192]u8 = undefined;
    while (true) {
        const read_len = try reader.readSliceShort(&buf);
        if (read_len == 0) break;
        try out.writeAll(buf[0..read_len]);
        if (read_len < buf.len) break;
    }
    try out.chmod(0o755);
}
