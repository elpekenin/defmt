//! Inspect and validate format strings and their arguments.
//!
//! Still WIP!

const std = @import("std");

const Token = union(enum) {
    boolean, // b
    char, // c
    brace: enum {
        open, // {
        close, // }
    },
    integer: union(enum) {
        octal,  // o
        decimal, // d
        hex: enum {
            lower, // x
            upper, // X
        },
    },
    pointer, // *
    scientific, // e
    string, // s
    text: []const u8,

    fn from(char: u8) !Self {
        return switch (char) {
            'b' => .boolean,
            'c' => .char,
            'o' => .{.integer = .octal},
            'd' => .{.integer = .decimal},
            'x' => .{.integer = .{.hex = .lower}},
            'X' => .{.integer = .{.hex = .upper}},
            '*' => .pointer,
            'e' => .scientific,
            's' => .string,
            else => error.InvalidFmt,
        };
    }

    fn needsArg(self: Self) bool {
        return switch (self) {
            .boolean,
            .char,
            .integer,
            .pointer,
            .scientific,
            .string,
            => true,

            .brace,
            .text,
            => false,
        };
    }

    fn canRepresent(self: Self, comptime T: type) bool {
        const Info = @typeInfo(T);

        // TODO: add support for more types, eg:
        //   - using comptime_int, where int is expected
        //   - .integer printing a float value (floor)
        return switch (self) {
            .boolean => T == bool,
            .char => T == u8,
            .integer => switch (Info) {
                .int => true,
                else => false,
            },
            .scientific => switch (Info) {
                .float,
                .int,
                => true,
                else => error.TypeMismatch,
            },
            .pointer => switch (Info) {
                .array,
                .pointer,
                => true,
                else => false,
            },
            .string => switch (T) {
                []u8,
                []const u8,
                => return true,
                else => false,
            },

            .brace,
            .text,
            => false,
        };
    }

    const Self = @This();
};

const Tokenizer = struct {
    i: usize,
    fmt: []const u8,

    fn new(comptime fmt: []const u8) Self {
        return .{
            .i = 0,
            .fmt = fmt,
        };
    }

    fn next(self: *Self) TokenError!?Token {
        if (self.i >= self.fmt.len) {
            return null;
        }

        const start = self.i;
        const first_char = self.fmt[start];

        while (true) {
            switch (self.fmt[self.i]) {
                '{' => {
                    // ...{ -> ...
                    if (first_char != '{') {
                        return .{
                            .text = self.fmt[start .. self.i],
                        };
                    }

                    defer self.i += 1;
                    switch (self.i - start) {
                        0 => {},
                        // {{ => brace.open
                        1 => return .{
                            .brace = .open,
                        },
                        // {...{ -> invalid
                        else => return error.InvalidFmt,
                    }
                },
                '}' => {
                    switch (first_char) {
                        // {...}
                        '{' => {
                            // {<several_chars>} -> invalid
                            if (self.i != start + 2) {
                                return error.InvalidFmt;
                            }

                            // {<char>} -> token
                            defer self.i += 1;
                            return try .from(self.fmt[start + 1]);
                        },
                        '}' => {
                            defer self.i += 1;
                            switch (self.i - start) {
                                0 => {},
                                // }} => brace.close
                                1 => return .{
                                    .brace = .close,
                                },
                                // }...} -> invalid
                                else => return error.InvalidFmt,
                            }
                        },
                        else => {
                            // ...}<end_of_fmt> -> invalid
                            if (self.i == self.fmt.len - 1) {
                                return error.InvalidFmt;
                            }
    
                            const next_char = self.fmt[self.i + 1];
                            if (next_char == '}') {
                                self.i += 2;
                                return .{ .brace = .close };
                            } else {
                                return error.InvalidFmt;
                            }
                        }
                    }
                },
                else => self.i += 1,
            }
        }
    }

    const Self = @This();
};

pub fn validate(comptime fmt: []const u8, args: anytype) ValidationError![]Token {
    const Info = @typeInfo(@TypeOf(args));
    if (Info != .@"struct") {
        return error.NotStruct;
    }
    const fields = Info.@"struct".fields;

    var i: usize = 0;
    var tokens: [32]Token = undefined;

    var tokenizer: Tokenizer = .new(fmt);
    while (try tokenizer.next()) |token| {
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
        if (!token.canRepresent(field.type)) {
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
