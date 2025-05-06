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

/// Generate an identifier for the given format string
pub fn forFmt(comptime fmt: []const u8) u14 {
    // Create a type for the sole purpose of exporting a u8.
    // Can't do that with a regular variable.
    //
    // u8 and not a u0 -despite its value being useless- so that each
    // symbol ends on a different address (ie: can be used as identifier)
    const DummyType = struct {
        // Make type depend on `fmt` so that each one call produces a new different type.
        // Otherwise, `dummy_var` will always be the same thing due to memoization.
        const foo = fmt;

        // undefined = no initialized, never using it anyway
        const dummy_var: u8 = undefined;
    };

    // Duplicated format strings end up on the same symbol/location due to zig's memoization
    // This might break/change if there's ever a second compiler, or something gets rewritten
    const ptr = &DummyType.dummy_var;
    @export(ptr, .{ .name = fmt, .section = ".defmt" });

    // offset in the custom section
    // if id is bigger than our size for it (u14), this will throw safety-protected UB
    return @intCast(@intFromPtr(ptr) - @intFromPtr(&symbols.__defmt_start));
}
