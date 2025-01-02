const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("defmt", .{
        .root_source_file = b.path("src/defmt.zig"),
        .optimize = optimize,
        .target = target,
    });
}
