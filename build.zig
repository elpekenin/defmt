const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("defmt", .{ .root_source_file = b.path("src/defmt.zig") });

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("defmt", module);

    b.installArtifact(exe);
}
