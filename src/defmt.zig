//! Deferred formatting in zig

fn enabledFor(level: Level) bool {
    // zig's order is: err, warn, info, debug
    // thus, despite being counter-intuitive (with my previous experience)
    // using "<" instead of ">" is correct
    return @intFromEnum(level) <= @intFromEnum(std.options.log_level);
}

fn log(comptime level: Level, writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) !void {
    // this level of logging is disabled
    if (!comptime enabledFor(level)) {
        return;
    }

    return protocol.send(level, writer, fmt, args);
}

pub fn err(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) void {
    log(.err, writer, fmt, args) catch {};
}

pub fn warn(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) void {
    log(.warn, writer, fmt, args) catch {};
}

pub fn info(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) void {
    log(.info, writer, fmt, args) catch {};
}

pub fn debug(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) void {
    log(.debug, writer, fmt, args) catch {};
}

/// Convenience to capture a writer, instead of having to pass it in each time
pub const Logger = struct {
    writer: std.io.AnyWriter,

    pub fn from(writer: std.io.AnyWriter) Logger {
        return .{
            .writer = writer,
        };
    }

    pub fn err(self: Logger, comptime fmt: []const u8, args: anytype) void {
        return defmt.err(self.writer, fmt, args);
    }

    pub fn warn(self: Logger, comptime fmt: []const u8, args: anytype) void {
        return defmt.warn(self.writer, fmt, args);
    }

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        return defmt.info(self.writer, fmt, args);
    }

    pub fn debug(self: Logger, comptime fmt: []const u8, args: anytype) void {
        return defmt.debug(self.writer, fmt, args);
    }
};

const std = @import("std");
const Level = std.log.Level;

const defmt = @This();

const protocol = @import("protocol.zig");

comptime {
    if (@TypeOf(@intFromEnum(Level.err)) != u2) {
        const msg = "Expected Level to fit in u2, serialization broken!.";
        @compileError(msg);
    }
}
