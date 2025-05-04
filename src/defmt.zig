//! Deferred formatting in zig

// TODO: Some mechanism to detect out-of-sync between MCU and host ELFs

const std = @import("std");
const Level = std.log.Level;
const Type = std.builtin.Type;

const inspect = @import("inspect.zig");

comptime {
    if (@TypeOf(@intFromEnum(Level.err)) != u2) {
        const msg = "Expected Level to fit in u2, serialization broken!.";
        @compileError(msg);
    }
}

const endianness: std.builtin.Endian = .little;

/// These are provided by linker script
/// By referencing them, we also make sure that the relevant section was added
/// ```ld
/// .defmt : {
///   PROVIDE_HIDDEN (__defmt_start = .);
///   KEEP (*(.defmt))
///   PROVIDE_HIDDEN (__defmt_end = .);
/// }
/// ```
/// NOTE: Im no linker expert but im pretty sure we dont need a custom section (for now?)
/// for the stuff we do... However it will make it easier to find stuff (eg: objdump | grep defmt)
const symbols = struct {
    extern var __defmt_start: anyopaque;
    extern var __defmt_end: anyopaque;
};

/// Create a type for the sole purpose of emiting a u8 with a custom
/// name: the format string. We can't do that with stack variables.
///
/// It is a u8 and not a u0 -despite its value being useless- so that each
/// symbol has a different address (ie: they can be told apart)
///
/// Returns an identifier for the symbol
fn idForFmt(comptime fmt: []const u8) u14 {
    const DummyType = struct {
        /// Make type depend on `fmt` so that each one call produces a new different type.
        /// Otherwise, `dummy_var` will always be the same thing due to memoization.
        const foo = fmt;

        /// Dont waste time initializing, we will never use the variable :)
        const dummy_var: u8 = undefined;
    };

    const ptr = &DummyType.dummy_var;

    // Apparently, if the exact same format string is used in several
    // places, they "land" on the same symbol.
    // ie: zig is handling collisions (and without waste)
    @export(ptr, .{ .name = fmt, .section = ".defmt" });

    // offset in the custom section
    // if id is bigger than our size for it (u14), this will throw safety-protected UB
    return @intCast(@intFromPtr(ptr) - @intFromPtr(&symbols.__defmt_start));
}

/// Given a number, return the smallest multiple of 8 bigger than it
/// This is used to find the smallest number of bytes capable of representing a bitwidth.
/// eg: if we receive a 10 (10 bits), we will return 16 (2 bytes).
fn roundUp(bits: u16) u16 {
    const size = std.mem.byte_size_in_bits;
    const bytes = (bits + size - 1) / size;
    return bytes * size;
}

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

    // check if format and args are valid
    const tokens = comptime inspect.validate(fmt, args) catch |e| {
        const msg = switch (e) {
            error.ExtraArgs => "Too many arguments to be logged with the given format",
            error.InvalidFmt => "Format string is invalid",
            error.MissingArgs => "Too few arguments to be logged with the given format",
            error.NotStruct => "Arguments to be logged must be placed in a struct",
            error.TooManyArgs => "Amount of arguments to be printed exceeds implementation limit",
            error.TypeMismatch => "The type of one argument is not compatible with its designated specifier",
        };
        @compileError(msg);
    };

    const id = idForFmt(fmt);

    // level (debug, info, warn, error) is represented as u2
    // string identifier is u14 (2 ** 14 strings sounds like enough room for a lifetime)
    const header: u16 = (@as(u16, @intFromEnum(level)) << 14) | id;
    try writer.writeInt(u16, header, .little);

    // send args
    const fields = @typeInfo(@TypeOf(args)).@"struct".fields;
    inline for (tokens, fields) |token, field| {
        const value = @field(args, field.name);

        switch (token) {
            // TODO: pack bools into a bitmask
            // bool is probably represented by a single bit internally
            // lets make it a whole byte to be sure about its representation over the wire
            .boolean => {
                try writer.writeByte(@intFromBool(value));
            },
            .char => {
                try writer.writeByte(value);
            },
            // TODO: implement some sort of identification for the type length
            //       right now, host couldn't know if value is u8(consume 1 byte) or u64(8)
            .integer => {
                const i = @typeInfo(field.type).int;
                const bits = comptime roundUp(i.bits);

                const Int = @Type(Type{
                    .int = .{
                        .signedness = i.signedness,
                        .bits = bits,
                    },
                });

                // since Int's bitsize is >= to original type, it can coerce
                try writer.writeInt(Int, value, endianness);
            },
            .pointer => {
                try writer.writeInt(usize, value, endianness);
            },
            .scientific => unreachable, // unimplemented
            .string => {
                try writer.writeAll(value);
            },

            // not sent over wire
            .brace,
            .text,
            => {}, 
        }
    }
}

pub fn err(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) !void {
    return log(.err, writer, fmt, args);
}

pub fn warn(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) !void {
    return log(.warn, writer, fmt, args);
}

pub fn info(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) !void {
    return log(.info, writer, fmt, args);
}

pub fn debug(writer: std.io.AnyWriter, comptime fmt: []const u8, args: anytype) !void {
    return log(.debug, writer, fmt, args);
}

/// Convenience to capture a writer, instead of having to pass it in each time
pub const Logger = struct {
    const Self = @This();

    writer: std.io.AnyWriter,

    pub fn from(writer: std.io.AnyWriter) Self {
        return .{
            .writer = writer,
        };
    }

    pub fn err(self: *const Self, comptime fmt: []const u8, args: anytype) !void {
        return defmt.err(self.writer, fmt, args);
    }

    pub fn warn(self: *const Self, comptime fmt: []const u8, args: anytype) !void {
        return defmt.warn(self.writer, fmt, args);
    }

    pub fn info(self: *const Self, comptime fmt: []const u8, args: anytype) !void {
        return defmt.info(self.writer, fmt, args);
    }

    pub fn debug(self: *const Self, comptime fmt: []const u8, args: anytype) !void {
        return defmt.debug(self.writer, fmt, args);
    }
};

const defmt = @This();
