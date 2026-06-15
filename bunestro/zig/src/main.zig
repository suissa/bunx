const std = @import("std");

const default_concurrency = 10;
const max_concurrency = 64;
const stderr_limit = 64 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const command = args.next() orelse {
        printHelp();
        return;
    };

    if (std.mem.eql(u8, command, "run")) {
        var list = std.ArrayList([]const u8).init(allocator);
        defer list.deinit();
        while (args.next()) |arg| try list.append(arg);
        if (list.items.len == 0) return error.MissingRunFile;
        try runSupervised(allocator, list.items);
    } else if (std.mem.eql(u8, command, "install")) {
        var update = false;
        var package_json: []const u8 = "package.json";
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--update")) {
                update = true;
            } else if (std.mem.eql(u8, arg, "--package-json")) {
                package_json = args.next() orelse return error.MissingPackageJsonPath;
            } else {
                return error.UnknownInstallOption;
            }
        }
        try installManifest(allocator, package_json, update);
    } else if (std.mem.eql(u8, command, "cache")) {
        try cacheCommand(allocator, args.next() orelse "info");
    } else {
        printHelp();
    }
}

fn printHelp() void {
    std.debug.print(
        \\bunestro (Zig)
        \\
        \\Commands:
        \\  run <file.ts|file.js> [args...]       supervise bun run and recover missing packages
        \\  install [--update] [--package-json]  install manifest deps into the bunestro cache
        \\  cache info|dir|list|clean             inspect or clean the cache
        \\
    , .{});
}

fn bunestroHome(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "BUNESTRO_HOME")) |value| return value else |_| {}
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".bunestro" });
    } else |_| {}
    return allocator.dupe(u8, ".bunestro");
}

fn concurrency() usize {
    var buf: [32]u8 = undefined;
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "BUNESTRO_CONCURRENCY")) |value| {
        defer std.heap.page_allocator.free(value);
        const parsed = std.fmt.parseUnsigned(usize, value, 10) catch default_concurrency;
        if (parsed == 0) return default_concurrency;
        return @min(parsed, max_concurrency);
    } else |_| {}
    _ = &buf;
    return default_concurrency;
}

fn runSupervised(allocator: std.mem.Allocator, run_args: []const []const u8) !void {
    const home = try bunestroHome(allocator);
    defer allocator.free(home);
    try std.fs.cwd().makePath(home);
    const cache_nm = try std.fs.path.join(allocator, &.{ home, "node_modules" });
    defer allocator.free(cache_nm);
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    const project_nm = try std.fs.path.join(allocator, &.{ cwd, "node_modules" });
    defer allocator.free(project_nm);

    var deps = std.ArrayList([]const u8).init(allocator);
    defer deps.deinit();
    var dev_deps = std.ArrayList([]const u8).init(allocator);
    defer dev_deps.deinit();
    try collectManifestDependencies(allocator, "package.json", project_nm, cache_nm, &deps, &dev_deps, false);
    try installGroupsParallel(allocator, home, deps.items, dev_deps.items, false);
    for (deps.items) |pkg| try linkCachedPackage(allocator, project_nm, cache_nm, pkg);
    for (dev_deps.items) |pkg| try linkCachedPackage(allocator, project_nm, cache_nm, pkg);

    const node_path = try nodePathWithCache(allocator, cache_nm);
    defer allocator.free(node_path);
    const first = try spawnBunRun(allocator, run_args, node_path);
    defer allocator.free(first.stderr);
    if (first.code == 0) return;

    if (extractMissingPackage(allocator, first.stderr)) |pkg| {
        defer allocator.free(pkg);
        var one = [_][]const u8{pkg};
        try installPackagesParallel(allocator, home, &one, false);
        try linkCachedPackage(allocator, project_nm, cache_nm, pkg);
        const second = try spawnBunRun(allocator, run_args, node_path);
        defer allocator.free(second.stderr);
        if (second.stderr.len > 0) try std.io.getStdErr().writeAll(second.stderr);
        std.process.exit(second.code);
    } else |_| {
        if (first.stderr.len > 0) try std.io.getStdErr().writeAll(first.stderr);
        std.process.exit(first.code);
    }
}

fn installManifest(allocator: std.mem.Allocator, package_json: []const u8, update: bool) !void {
    const home = try bunestroHome(allocator);
    defer allocator.free(home);
    const cache_nm = try std.fs.path.join(allocator, &.{ home, "node_modules" });
    defer allocator.free(cache_nm);
    var deps = std.ArrayList([]const u8).init(allocator);
    defer deps.deinit();
    var dev_deps = std.ArrayList([]const u8).init(allocator);
    defer dev_deps.deinit();
    try collectManifestDependencies(allocator, package_json, "node_modules", cache_nm, &deps, &dev_deps, update);
    try installGroupsParallel(allocator, home, deps.items, dev_deps.items, update);
}

fn cacheCommand(allocator: std.mem.Allocator, command: []const u8) !void {
    const home = try bunestroHome(allocator);
    defer allocator.free(home);
    const cache_nm = try std.fs.path.join(allocator, &.{ home, "node_modules" });
    defer allocator.free(cache_nm);
    if (std.mem.eql(u8, command, "dir") or std.mem.eql(u8, command, "path")) {
        std.debug.print("{s}\n", .{home});
    } else if (std.mem.eql(u8, command, "info") or std.mem.eql(u8, command, "stats")) {
        std.debug.print("path: {s}\npackages: {d}\nbytes: {d}\nconcurrency: {d}\n", .{ home, try countPackages(allocator, cache_nm), try dirSize(cache_nm), concurrency() });
    } else if (std.mem.eql(u8, command, "list") or std.mem.eql(u8, command, "ls")) {
        try listPackages(allocator, cache_nm);
    } else if (std.mem.eql(u8, command, "clean") or std.mem.eql(u8, command, "prune")) {
        std.fs.cwd().deleteTree(home) catch {};
        std.debug.print("removed {s}\n", .{home});
    } else return error.UnknownCacheCommand;
}

const RunResult = struct { code: u8, stderr: []u8 };

fn spawnBunRun(allocator: std.mem.Allocator, run_args: []const []const u8, node_path: []const u8) !RunResult {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("bun");
    try argv.append("run");
    for (run_args) |arg| try argv.append(arg);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Pipe;
    try child.env_map.put("NODE_PATH", node_path);
    try child.spawn();

    var stderr = std.ArrayList(u8).init(allocator);
    if (child.stderr) |pipe| {
        var buf: [8192]u8 = undefined;
        while (true) {
            const n = try pipe.read(&buf);
            if (n == 0) break;
            const remaining = stderr_limit - @min(stderr.items.len, stderr_limit);
            if (remaining > 0) try stderr.appendSlice(buf[0..@min(n, remaining)]);
        }
    }
    const term = try child.wait();
    const code: u8 = switch (term) { .Exited => |c| c, else => 1 };
    return .{ .code = code, .stderr = try stderr.toOwnedSlice() };
}

fn installGroupsParallel(allocator: std.mem.Allocator, home: []const u8, deps: []const []const u8, dev_deps: []const []const u8, update: bool) !void {
    try installPackagesParallel(allocator, home, deps, update);
    try installPackagesParallel(allocator, home, dev_deps, update);
}

fn installPackagesParallel(allocator: std.mem.Allocator, home: []const u8, packages: []const []const u8, update: bool) !void {
    if (packages.len == 0) return;
    try std.fs.cwd().makePath(home);
    const package_json = try std.fs.path.join(allocator, &.{ home, "package.json" });
    defer allocator.free(package_json);
    if (!exists(package_json)) try std.fs.cwd().writeFile(.{ .sub_path = package_json, .data = "{\"private\":true,\"dependencies\":{}}\n" });

    for (packages) |package| try installPackage(allocator, home, package, update);
}

fn installPackage(allocator: std.mem.Allocator, home: []const u8, package: []const u8, update: bool) !void {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("bun");
    try argv.append("add");
    try argv.append("--no-save");
    if (update) {
        try argv.append("--force");
        try argv.append("--no-cache");
    }
    try argv.append(package);
    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = home;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) return error.InstallFailed;
}

fn collectManifestDependencies(allocator: std.mem.Allocator, path: []const u8, project_nm: []const u8, cache_nm: []const u8, deps: *std.ArrayList([]const u8), dev_deps: *std.ArrayList([]const u8), include_cached: bool) !void {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 4 * 1024 * 1024) catch return;
    defer allocator.free(source);
    try collectSection(allocator, source, "dependencies", project_nm, cache_nm, deps, include_cached);
    try collectSection(allocator, source, "devDependencies", project_nm, cache_nm, dev_deps, include_cached);
}

fn collectSection(allocator: std.mem.Allocator, source: []const u8, section: []const u8, project_nm: []const u8, cache_nm: []const u8, out: *std.ArrayList([]const u8), include_cached: bool) !void {
    const quoted = try std.fmt.allocPrint(allocator, "\"{s}\"", .{section});
    defer allocator.free(quoted);
    const idx = std.mem.indexOf(u8, source, quoted) orelse return;
    const open_rel = std.mem.indexOfScalar(u8, source[idx..], '{') orelse return;
    var i = idx + open_rel + 1;
    while (i < source.len and source[i] != '}') : (i += 1) {
        if (source[i] == '"') {
            const start = i + 1;
            const end_rel = std.mem.indexOfScalar(u8, source[start..], '"') orelse return;
            const end = start + end_rel;
            const name = source[start..end];
            var after_key = end + 1;
            while (after_key < source.len and std.ascii.isWhitespace(source[after_key])) : (after_key += 1) {}
            if (after_key < source.len and source[after_key] == ':') {
                if (packageName(name)) |pkg| {
                    if (include_cached or !try isCached(allocator, project_nm, cache_nm, pkg)) try out.append(try allocator.dupe(u8, pkg));
                }
            }
            i = end;
        }
    }
}

fn extractMissingPackage(allocator: std.mem.Allocator, stderr: []const u8) ![]u8 {
    for ([_][]const u8{ "Cannot find module '", "Cannot find package '", "Cannot find module \"", "Cannot find package \"" }) |needle| {
        if (std.mem.indexOf(u8, stderr, needle)) |idx| {
            const rest = stderr[idx + needle.len ..];
            const quote: u8 = if (needle[needle.len - 1] == '"') '"' else '\'';
            if (std.mem.indexOfScalar(u8, rest, quote)) |end| {
                if (packageName(rest[0..end])) |pkg| return allocator.dupe(u8, pkg);
            }
        }
    }
    return error.NotFound;
}

fn packageName(specifier: []const u8) ?[]const u8 {
    if (specifier.len == 0 or specifier[0] == '.' or specifier[0] == '/' or std.mem.startsWith(u8, specifier, "node:")) return null;
    if (specifier[0] == '@') {
        var seen_slash = false;
        for (specifier, 0..) |c, i| {
            if (c == '/') {
                if (seen_slash) return specifier[0..i];
                seen_slash = true;
            }
        }
        return if (seen_slash) specifier else null;
    }
    return specifier[0 .. std.mem.indexOfScalar(u8, specifier, '/') orelse specifier.len];
}

fn isCached(allocator: std.mem.Allocator, project_nm: []const u8, cache_nm: []const u8, package: []const u8) !bool {
    const a = try std.fs.path.join(allocator, &.{ project_nm, package });
    defer allocator.free(a);
    const b = try std.fs.path.join(allocator, &.{ cache_nm, package });
    defer allocator.free(b);
    return exists(a) or exists(b);
}

fn linkCachedPackage(allocator: std.mem.Allocator, project_nm: []const u8, cache_nm: []const u8, package: []const u8) !void {
    const source = try std.fs.path.join(allocator, &.{ cache_nm, package });
    defer allocator.free(source);
    if (!exists(source)) return;
    const dest = try std.fs.path.join(allocator, &.{ project_nm, package });
    defer allocator.free(dest);
    if (exists(dest)) return;
    if (std.fs.path.dirname(dest)) |parent| try std.fs.cwd().makePath(parent);
    std.fs.cwd().symLink(source, dest, .{ .is_directory = true }) catch {};
}

fn nodePathWithCache(allocator: std.mem.Allocator, cache_nm: []const u8) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "NODE_PATH")) |existing| {
        defer allocator.free(existing);
        return std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ cache_nm, std.fs.path.delimiter, existing });
    } else |_| {}
    return allocator.dupe(u8, cache_nm);
}

fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn countPackages(allocator: std.mem.Allocator, cache_nm: []const u8) !usize {
    var dir = std.fs.cwd().openDir(cache_nm, .{ .iterate = true }) catch return 0;
    defer dir.close();
    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.name.len > 0 and entry.name[0] != '.') count += 1;
    }
    _ = allocator;
    return count;
}

fn listPackages(allocator: std.mem.Allocator, cache_nm: []const u8) !void {
    var dir = std.fs.cwd().openDir(cache_nm, .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.name.len > 0 and entry.name[0] != '.') std.debug.print("{s}\n", .{entry.name});
    }
    _ = allocator;
}

fn dirSize(path: []const u8) !u64 {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return 0;
    defer dir.close();
    var total: u64 = 0;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) {
            const stat = dir.statFile(entry.name) catch continue;
            total += stat.size;
        }
    }
    return total;
}
