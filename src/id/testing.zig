const std = @import("std");
const Hasher = std.hash.RapidHash;

pub fn forFmt(comptime fmt: []const u8) u14 {
    const raw = Hasher.hash(fmt.len, fmt);
    return @truncate(raw);
}
