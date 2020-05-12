const std = @import("std");

num: comptime_int,
denom: comptime_int = 1,

const Ratio = @This();

pub fn from(comptime num: comptime_int, comptime denom: comptime_int) Ratio {
    return .{ .num = num, .denom = denom };
}

pub const nano = Ratio.from(1, 1_000_000_000);
pub const micro = Ratio.from(1, 1_000_000);
pub const milli = Ratio.from(1, 1_000);
pub const zero = Ratio.from(0, 1);
pub const one = Ratio.from(1, 1);
pub const kilo = Ratio.from(1_000, 1);
pub const mega = Ratio.from(1_000_000, 1);
pub const giga = Ratio.from(1_000_000_000, 1);

pub fn ctStr(comptime ratio: Ratio) []const u8 {
    // fn formatIntBuf(out_buf: []u8, value: var, base: u8, uppercase: bool, options: FormatOptions) usize
    var buf_one: [32]u8 = undefined;
    var buf_two: [32]u8 = undefined;
    return buf_one[0..std.fmt.formatIntBuf(&buf_one, ratio.num, 10, false, std.fmt.FormatOptions{})] ++
        "/" ++ buf_two[0..std.fmt.formatIntBuf(&buf_two, ratio.denom, 10, false, std.fmt.FormatOptions{})];
}

pub fn sub(comptime ratio1: Ratio, comptime ratio2: Ratio) Ratio {
    return .{
        .num = (ratio1.num * ratio2.denom) - (ratio2.num * ratio1.denom),
        .denom = ratio1.denom * ratio2.denom,
    };
}

pub fn abs(comptime self: Ratio) Ratio {
    if (self.denom < 0) unreachable;

    return if (self.num >= 0) self else .{
        .num = -self.num,
        .denom = self.denom,
    };
}

pub fn simplify(comptime self: Ratio) Ratio {
    const is_negative = self.num * self.denom < 0;

    var num = (Ratio{ .num = self.num }).abs();
    var denom = (Ratio{ .num = self.denom }).abs();
    const gcd_res = gcd(num.abs(), denom.abs());

    num = div(num, gcd_res.divisor);
    denom = div(denom, gcd_res.divisor);

    return .{
        .num = @divExact(if (is_negative) -num.num else num.num, num.denom),
        .denom = @divExact(denom.num, denom.denom),
    };
}

pub fn mod(comptime ratio1: Ratio, comptime ratio2: Ratio) Ratio {
    const dived = div(ratio1, ratio2);
    const k = @divTrunc(dived.num, dived.denom);

    const r2 = Ratio{
        .num = k * ratio2.num,
        .denom = ratio2.denom,
    };
    return sub(ratio1, r2);
}

pub fn div(comptime ratio1: Ratio, comptime ratio2: Ratio) Ratio {
    return .{
        .num = ratio1.num * ratio2.denom,
        .denom = ratio1.denom * ratio2.num,
    };
}

pub fn mul(comptime ratio1: Ratio, comptime ratio2: Ratio) Ratio {
    return .{
        .num = ratio1.num * ratio2.num,
        .denom = ratio1.denom * ratio2.denom,
    };
}

pub fn mulRt(comptime ratio: Ratio, arg: var) @TypeOf(arg) {
    // TODO: divFloor perhaps?
    return @divTrunc(ratio.num * arg, ratio.denom);
}

pub const GcdResult = struct {
    divisor: Ratio,
    coeff1: Ratio,
    coeff2: Ratio,
};

/// Extended Euclidean algorithm
pub fn gcd(comptime ratio1: Ratio, comptime ratio2: Ratio) GcdResult {
    var prev_x = one;
    var x = zero;

    var prev_y = zero;
    var y = one;

    var a = ratio1;
    var b = ratio2;
    while (b.num != 0) {
        const q = div(a, b);

        const tmp_x = x;
        x = sub(prev_x, mul(q, x));
        prev_x = tmp_x;

        const tmp_y = y;
        y = sub(prev_y, mul(q, y));
        prev_y = tmp_y;

        const tmp_a = a;
        a = b;
        b = mod(tmp_a, b);
    }

    return .{
        .divisor = a,
        .coeff1 = prev_x,
        .coeff2 = prev_y,
    };
}

pub fn eql(comptime ratio1: Ratio, comptime ratio2: Ratio) bool {
    const s1 = ratio1.simplify();
    const s2 = ratio2.simplify();
    if (s1.num == 0 and s1.num == s2.num) return true;

    return s1.num == s2.num and s1.denom == s2.denom;
}
