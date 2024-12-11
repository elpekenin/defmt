const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("defmt", .{ .root_source_file = b.path("src/defmt.zig") });
}
