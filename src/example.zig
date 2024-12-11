//! Run a tiny example using defmt

const std = @import("std");
const defmt = @import("defmt");

pub fn main() !void {
    std.debug.print("Hello world", .{});
    const stdout = std.io.getStdOut().writer().any();
    const foo: u7 = 33;

    try defmt.info(stdout, "Hello {d}", .{@as(u120, foo)});
    try defmt.info(stdout, "Foo {x}", .{false});
    try defmt.info(stdout, "Hello {d}", .{foo});
    try defmt.info(stdout, "Bar {u}", .{foo});
}
