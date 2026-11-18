const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.ExpectedArchiveAndDestination;

    const io = init.io;
    const destination = try std.Io.Dir.cwd().createDirPathOpen(io, args[2], .{});
    defer destination.close(io);
    const archive = try std.Io.Dir.cwd().openFile(io, args[1], .{});
    defer archive.close(io);
    var buffer: [8192]u8 = undefined;
    var reader = archive.reader(io, &buffer);
    try std.zip.extract(destination, &reader, .{});
}
