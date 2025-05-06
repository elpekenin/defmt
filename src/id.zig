const builtin = @import("builtin");

const embedded = @import("id/embedded.zig");
const testing = @import("id/testing.zig");

pub const forFmt = switch (builtin.target.os.tag) {
    .freestanding => embedded.forFmt,
    else => testing.forFmt,
};
