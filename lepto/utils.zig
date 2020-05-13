const std = @import("std");

pub fn ctIntToStr(comptime int: comptime_int) []const u8 {
    var buf: [32]u8 = undefined;
    return buf[0..std.fmt.formatIntBuf(&buf, int, 10, false, std.fmt.FormatOptions{})];
}
