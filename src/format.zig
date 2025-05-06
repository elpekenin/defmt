//! Inspect and validate format strings and their arguments.
//!
//! Still WIP!

const map: []const struct { []const u8, Token } = &.{
    .{ "{{", .brace },
    .{ "}}", .brace },
    .{ "{b}", .boolean },

    .{ "{i8}", .{ .integer = .{ .signedness = .signed, .bits = 8 } } },
    .{ "{i16}", .{ .integer = .{ .signedness = .signed, .bits = 16 } } },
    .{ "{i32}", .{ .integer = .{ .signedness = .signed, .bits = 32 } } },
    .{ "{i64}", .{ .integer = .{ .signedness = .signed, .bits = 64 } } },

    .{ "{c}", .{ .integer = .{ .signedness = .unsigned, .bits = 8 } } },
    .{ "{u8}", .{ .integer = .{ .signedness = .unsigned, .bits = 8 } } },
    .{ "{u16}", .{ .integer = .{ .signedness = .unsigned, .bits = 16 } } },
    .{ "{u32}", .{ .integer = .{ .signedness = .unsigned, .bits = 32 } } },
    .{ "{u64}", .{ .integer = .{ .signedness = .unsigned, .bits = 64 } } },

    .{ "{f32}", .{ .float = 32 } },
    .{ "{f64}", .{ .float = 64 } },
};

const specifiers: std.StaticStringMap(Token) = .initComptime(map);

const Token = union(enum) {
    boolean,
    integer: struct { signedness: Signedness, bits: usize },
    float: usize,

    text,
    brace,

    fn from(str: []const u8) !Token {
        return specifiers.get(str) orelse error.InvalidFmt;
    }

    fn needsArg(self: Token) bool {
        return switch (self) {
            .boolean,
            .integer,
            .float,
            => true,

            .text,
            .brace,
            => false,
        };
    }

    pub fn getType(self: Token) type {
        return switch (self) {
            .boolean => bool,
            .integer => |int| @Type(Type{
                .int = .{
                    .bits = int.bits,
                    .signedness = int.signedness,
                },
            }),
            .float => |bits| @Type(Type{
                .float = .{
                    .bits = bits,
                },
            }),

            .text,
            .brace,
            => @compileError("unreachable"),
        };
    }

    fn canRepresent(self: Token, comptime T: type, default: ?T) bool {
        const Info = @typeInfo(T);

        // TODO: add support for more types, eg:
        //   - using comptime_int, where int is expected
        //   - .integer printing a float value (floor)
        return switch (self) {
            .boolean => T == bool,
            .integer => |int| switch (Info) {
                .comptime_int => {
                    const value = default orelse unreachable;
                    return value <= std.math.maxInt(self.getType());
                },
                .int => |info| int.bits >= info.bits and info.signedness == int.signedness,
                else => false,
            },
            .float => |bits| switch (Info) {
                .comptime_float => {
                    const value = default orelse unreachable;
                    return value <= std.math.floatMax(self.getType());
                },
                .float => |info| bits >= info.bits,
                .int => true,
                else => error.TypeMismatch,
            },

            .text,
            .brace,
            => false,
        };
    }
};

const Tokenizer = struct {
    i: usize,
    fmt: []const u8,

    fn new(comptime fmt: []const u8) Tokenizer {
        return .{
            .i = 0,
            .fmt = fmt,
        };
    }

    fn next(self: *Tokenizer) TokenError!?Token {
        const start = self.i;

        while (true) {
            if (self.i >= self.fmt.len) {
                return null;
            }

            switch (self.fmt[self.i]) {
                '{' => {
                    if (self.i == start) {
                        self.i += 1;
                        continue;
                    }

                    // ...{ -> ...
                    if (self.fmt[start] != '{') {
                        return .text;
                    }

                    defer self.i += 1;

                    return if (self.i == start + 1)
                        .brace
                    else
                        error.InvalidFmt;
                },
                '}' => {
                    if (self.i == start) {
                        self.i += 1;
                        continue;
                    }

                    switch (self.fmt[start]) {
                        '{', '}' => {
                            self.i += 1;
                            return .from(self.fmt[start..self.i]);
                        },
                        else => {
                            // ...}<end_of_fmt> -> invalid
                            if (self.i == self.fmt.len - 1) {
                                return error.InvalidFmt;
                            }

                            defer self.i += 1;

                            const next_char = self.fmt[self.i + 1];
                            if (next_char == '}') {
                                self.i += 1; // need to consume extra char here
                                return .brace;
                            } else {
                                return error.InvalidFmt;
                            }
                        },
                    }
                },
                else => self.i += 1,
            }
        }
    }
};

pub fn getSpecifiers(comptime fmt: []const u8, args: anytype) ValidationError![]Token {
    const Info = @typeInfo(@TypeOf(args));
    if (Info != .@"struct") {
        return error.NotStruct;
    }
    const fields = Info.@"struct".fields;

    var i: usize = 0;
    var tokens: [32]Token = undefined;

    var tokenizer: Tokenizer = .new(fmt);
    while (true) {
        const maybe_token = try tokenizer.next();
        const token = maybe_token orelse break;
        if (token.needsArg()) {
            if (i == tokens.len) {
                return error.TooManyArgs;
            }

            tokens[i] = token;
            i += 1;
        }
    }

    if (fields.len < i) {
        return error.MissingArgs;
    }

    if (fields.len > i) {
        return error.ExtraArgs;
    }

    inline for (tokens[0..i], fields) |token, field| {
        const val = if (field.is_comptime)
            field.defaultValue()
        else
            null;

        if (!token.canRepresent(field.type, val)) {
            return error.TypeMismatch;
        }
    }

    return tokens[0..i];
}

pub const TokenError = error{
    InvalidFmt,
};

pub const ValidationError = TokenError || error{
    ExtraArgs, // more fields in struct than specs in fmt
    MissingArgs, // less fields in struct than specs in fmt
    NotStruct, // args is not a struct
    TooManyArgs, // received +32 arguments
    TypeMismatch, // the type of a field does not match its specifier
};

const std = @import("std");
const Signedness = std.builtin.Signedness;
const Type = std.builtin.Type;
