const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Extraction runs on the build host, including when cross-compiling to WASM.
    const extractor = b.addExecutable(.{
        .name = "extract-assets",
        .root_module = b.createModule(.{
            .root_source_file = b.path("extract.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
    const extract = b.addRunArtifact(extractor);
    extract.addFileArg(b.path("tyrian2000.zip"));
    const extracted = extract.addOutputDirectoryArg("assets");

    // Keep generated assets in the cache, beside the module's @embedFile calls.
    const files = b.addWriteFiles();
    _ = files.addCopyDirectory(extracted, ".", .{});
    const source = files.addCopyFile(b.path("assets.zig"), "assets.zig");
    _ = b.addModule("root", .{
        .root_source_file = source,
        .target = target,
        .optimize = optimize,
    });
}
