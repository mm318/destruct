const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("root", .{
        .root_source_file = b.path("assets.zig"),
        .target = target,
        .optimize = optimize,
    });

    const assets_cmd = ExtractAssetsStep.create(b, b.path("tyrian2000.zip"), b.path("."));

    const lib = b.addStaticLibrary(.{
        .name = "assets",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("assets.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.step.dependOn(&assets_cmd.step);

    b.installArtifact(lib);
}

const ExtractAssetsStep = struct {
    step: std.Build.Step,
    src_path: std.Build.LazyPath,
    dst_path: std.Build.LazyPath,

    pub fn create(
        owner: *std.Build,
        src_path: std.Build.LazyPath,
        dst_path: std.Build.LazyPath,
    ) *ExtractAssetsStep {
        const extract_step = owner.allocator.create(ExtractAssetsStep) catch @panic("OOM");
        extract_step.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = owner.fmt("extract assets to {s}", .{dst_path.getDisplayName()}),
                .owner = owner,
                .makeFn = make,
            }),
            .src_path = src_path.dupe(owner),
            .dst_path = dst_path.dupe(owner),
        };
        return extract_step;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const b = step.owner;
        const extract_step: *ExtractAssetsStep = @fieldParentPtr("step", step);
        try step.singleUnchangingWatchInput(extract_step.src_path);

        const full_src_path = extract_step.src_path.getPath2(b, step);
        const full_dst_path = extract_step.dst_path.getPath2(b, step);

        const dest_dir = try std.fs.openDirAbsolute(full_dst_path, .{});
        const src_file = try std.fs.openFileAbsolute(full_src_path, .{});
        const src_stream = std.fs.File.seekableStream(src_file);
        std.zip.extract(dest_dir, src_stream, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };

        step.result_cached = true;
    }
};
