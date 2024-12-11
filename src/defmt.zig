//! Deferred formatting in zig

// TODO: Some mechanism to detect out-of-sync between MCU and host ELFs

const std = @import("std");
const Level = std.log.Level;
const Type = std.builtin.Type;

const defmt = @This();

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
    const Dummy = struct {
        /// Make it depend on fmt so that each `Dummy` is a different type.
        /// Otherwise, `dummy` is always the same thing.
        const foo = fmt;

        /// Dont waste time initializing, we will never use the variable :)
        const dummy: u8 = undefined;
    };

    const ptr = &Dummy.dummy;

    // Apparently, if the exact same format string is used in several
    // places, they "land" on the same symbol.
    // ie: zig is handling collisions (and without waste)
    @export(ptr, .{ .name = fmt, .section = ".defmt" });

    // offset in the custom section
    // if id is bigger than our size for it (u14), this will throw safety-protected UB
    return @intCast(@intFromPtr(ptr) - @intFromPtr(&symbols.__defmt_start));
}

/// Given a number, return the smallest multiple of 8 >= to it
/// This is: find the smallest number of bytes capable of representing this bitwidth.
/// eg: if we receive a 10 (10 bits), we will retun u16 (2 bytes).
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
    if (!comptime enabledFor(level)) return;

    const id = idForFmt(fmt);

    // level (debug, info, warn, error) is represented as u2
    // string identifier is little-endian u14 (2 ** 14 levels sounds good enough)
    const header: u16 = (@as(u16, @intFromEnum(level)) << 14) | id; 
    try writer.writeInt(u16, header, .little);

    // send arguments
    const A = @TypeOf(args);
    const AInfo = @typeInfo(A);

    if (AInfo != .@"struct") {
        const msg = "Expected a struct as argument to print";
        @compileError(msg);
    }

    inline for (AInfo.@"struct".fields) |field| {
        const T = field.type;
        const TInfo = @typeInfo(T);

        const value = @field(args, field.name);

        // TODO: some signaling of the type sent
        // eg: how would we tell apart a u8 from a u16 when receiving data on the host?
        switch (TInfo) {
            .array => return error.NotYetImplemented,
            .bool => {
                // bool is probably represented by single-bit representation internally
                // lets make it a whole byte to be sure about its representation over the wire
                try writer.writeInt(u8, @intFromBool(value), endianness);
            },
            .int => |int_info| {
                const bits = comptime roundUp(int_info.bits);
                if (bits > 8) {
                    const msg = "Integers bigger than a byte not supported yet";
                    @compileError(msg);
                }

                const Int = @Type(Type{
                    .int = .{
                        .signedness = int_info.signedness,
                        .bits = bits,
                    },
                });

                // since Int's bitsize is >= to original type, it can coerce safely
                try writer.writeInt(Int, value, endianness);
            },
            .float => return error.MaybeLater,
            else => {
                const msg = "Printing type '" ++ @typeName(T) ++ "' is not supported at the moment.";
                @compileError(msg);
            },
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
