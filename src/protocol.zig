//! Encode/decode data over the wire

// TODO: configure from user code?
const endianness: std.builtin.Endian = .little;

const HeaderT = u16;
const Header = packed struct(HeaderT) {
    level: u2,
    // unique value for each format string
    fmt_id: u14,

    fn new(level: Level, comptime fmt: []const u8) Self {
        return .{
            .level = @intFromEnum(level),
            .fmt_id = id.forFmt(fmt),
        };
    }

    fn read(reader: AnyReader) !Self {
        const raw = try reader.readInt(HeaderT, endianness);
        return @bitCast(raw);
    }

    const Self = @This();
};

/// Get an integer type with the same size as input
/// Aka: f32 -> u32, f64 -> u64
fn IntFor(comptime F: type) type {
    const float = @typeInfo(F).float;
    return @Type(Type{
        .int = .{
            .bits = float.bits,
            .signedness = .unsigned,
        }
    });
}

pub fn send(level: Level, writer: AnyWriter, comptime fmt: []const u8, args: anytype) !void {
    // check if format and args are valid
    const tokens = comptime format.getSpecifiers(fmt, args) catch |e| {
        const msg = switch (e) {
            error.ExtraArgs => "Too many arguments to be logged with the given format",
            error.InvalidFmt => "Format string is invalid",
            error.MissingArgs => "Too few arguments to be logged with the given format",
            error.NotStruct => "Arguments to be logged must be placed in a struct",
            error.TooManyArgs => "Amount of arguments to be formatted exceeds implementation limit",
            error.TypeMismatch => "The type of one argument is not compatible with its designated specifier",
        };
        @compileError(msg);
    };

    const header: Header = .new(level, fmt);
    try writer.writeInt(HeaderT, @bitCast(header), endianness);

    const fields = @typeInfo(@TypeOf(args)).@"struct".fields;
    inline for (tokens, fields) |token, field| {
        const value = @field(args, field.name);

        switch (token) {
            // TODO: pack bools into a bitmask
            .boolean => try writer.writeByte(@intFromBool(value)),
            .integer => try writer.writeInt(token.getType(), @intCast(value), endianness),
            // NOTE: can't @bitMask a comptime_float :/
            .float => {
                const Float = token.getType();
                const Int = IntFor(Float);
                try writer.writeInt(Int, @bitCast(@as(Float, value)), endianness);
            },

            // not sent over wire
            .brace,
            .text,
            => @compileError("unreachable"),
        }
    }
}

const std = @import("std");
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Level = std.log.Level;
const Type = std.builtin.Type;
const expectEqual = std.testing.expectEqual;

const id = @import("id.zig");
const format = @import("format.zig");

fn expectSent(comptime fmt: []const u8, args: anytype, payload: []const u8) !void {
    // setup to send message and later inspect the output
    var buffer: [1024]u8 = undefined;

    var tx_stream = std.io.fixedBufferStream(&buffer);
    var writer = tx_stream.writer();
    const anywriter = writer.any();

    const tx_level: Level = .warn;
    try send(tx_level, anywriter, fmt, args);

    var rx_stream = std.io.fixedBufferStream(tx_stream.getWritten());
    var reader = rx_stream.reader();
    const anyreader = reader.any();

    // header

    const header: Header = try .read(anyreader);
    try expectEqual(@intFromEnum(tx_level), header.level);
    try expectEqual(id.forFmt(fmt), header.fmt_id);

    // payload

    var payload_stream = std.io.fixedBufferStream(payload);
    var payload_reader = payload_stream.reader();
    const payload_anyreader = payload_reader.any();

    while (true) {
        const expected: ?u8 = payload_anyreader.readByte() catch |e| switch (e) {
            error.EndOfStream => null,
            else => return e,
        };
        const actual: ?u8 = anyreader.readByte() catch |e| switch (e) {
            error.EndOfStream => null,
            else => return e,
        };

        if (actual == null and expected == null) {
            break;
        }

        try expectEqual(expected, actual);
        std.debug.print("{?}", .{actual});
    }
}

test send {
    try expectSent("foo {d} bar", .{@as(u8, 123)}, &.{123});
}
