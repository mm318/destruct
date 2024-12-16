const std = @import("std");
const sdl = @import("SDLzig");

const tyrian_srcs = [_][]const u8{
    "src/lib/arg_parse.c",
    "src/lib/config.c",
    "src/lib/config_file.c",
    "src/lib/destruct.c",
    "src/lib/file.c",
    "src/lib/fonthand.c",
    "src/lib/helptext.c",
    "src/lib/joystick.c",
    "src/lib/keyboard.c",
    "src/lib/lds_play.c",
    "src/lib/loudness.c",
    "src/lib/mtrand.c",
    "src/lib/network.c",
    "src/lib/nortsong.c",
    "src/lib/opentyr.c",
    "src/lib/opl.c",
    "src/lib/palette.c",
    "src/lib/params.c",
    "src/lib/pcxmast.c",
    "src/lib/picload.c",
    "src/lib/sprite.c",
    "src/lib/varz.c",
    "src/lib/vga256d.c",
    "src/lib/vga_palette.c",
    "src/lib/video.c",
    "src/lib/video_scale.c",
    "src/lib/video_scale_hqNx.c",
};

const c_flags = [_][]const u8{
    "-std=iso9899:1999",
    "-pedantic",
    "-Wall",
    "-Wextra",
    "-Wno-format-truncation",
    "-Wno-missing-field-initializers",
    "-O2",
    "-MMD",
    "-DNDEBUG",
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Determine compilation target
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Create a new instance of the SDL2 Sdk
    // Specifiy dependency name explicitly if necessary (use sdl by default)
    const sdk = sdl.init(b, .{ .dep_name = "SDLzig" });

    // Create executable for our example
    const exe = b.addExecutable(.{
        .name = "destruct",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{ .files = &tyrian_srcs, .flags = &c_flags });

    // Add "sdl2" package that exposes the SDL2 api (like SDL_Init or SDL_CreateWindow)
    exe.root_module.addImport("sdl2", sdk.getNativeModule());
    exe.root_module.addIncludePath(b.path("src/lib/"));

    sdk.link(exe, .dynamic, sdl.Library.SDL2); // link SDL2 as a shared library

    // Install the executable into the prefix when invoking "zig build"
    b.installArtifact(exe);

    const assets_cmd = ExtractAssetsStep.create(b, b.path("assets/tyrian2000.zip"), .bin, "");

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(.{ .cwd_relative = b.getInstallPath(.bin, "") });

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&assets_cmd.step);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const ExtractAssetsStep = struct {
    step: std.Build.Step,
    source: std.Build.LazyPath,
    dest_type: std.Build.InstallDir,
    dest_subpath: []const u8,

    pub fn create(
        owner: *std.Build,
        source: std.Build.LazyPath,
        dest_type: std.Build.InstallDir,
        dest_subpath: []const u8,
    ) *ExtractAssetsStep {
        const extract_step = owner.allocator.create(ExtractAssetsStep) catch @panic("OOM");
        extract_step.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = owner.fmt("extract {s} assets to {s}", .{ @tagName(dest_type), dest_subpath }),
                .owner = owner,
                .makeFn = make,
            }),
            .source = source.dupe(owner),
            .dest_type = dest_type.dupe(owner),
            .dest_subpath = owner.dupePath(dest_subpath),
        };
        return extract_step;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const b = step.owner;
        const extract_step: *ExtractAssetsStep = @fieldParentPtr("step", step);
        try step.singleUnchangingWatchInput(extract_step.source);

        const full_src_path = extract_step.source.getPath2(b, step);
        const full_dest_path = b.getInstallPath(extract_step.dest_type, extract_step.dest_subpath);

        const dest_dir = try std.fs.openDirAbsolute(full_dest_path, .{});
        const src_file = try std.fs.openFileAbsolute(full_src_path, .{});
        const src_stream = std.fs.File.seekableStream(src_file);
        std.zip.extract(dest_dir, src_stream, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };

        step.result_cached = true;
    }
};
