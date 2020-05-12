const std = @import("std");
usingnamespace (@import("lepto.zig"));

test "Ratio mod" {
    const res = Ratio.mod(Ratio.from(-3, 5), Ratio.from(1, 4));
    std.debug.assert(res.eql(Ratio.from(-1, 10)));
}

test "Ratio GCD" {
    const res = Ratio.gcd(Ratio.milli, Ratio.micro);
    std.debug.assert(res.divisor.eql(Ratio.micro));
    std.debug.assert(res.coeff1.eql(Ratio.zero));
    std.debug.assert(res.coeff2.eql(Ratio.one));
}

test "Duration arithmetic" {
    const dur = minutes.from(30).add(seconds.from(60));
    std.debug.assert(dur.value == 30 * 60 + 60);

    const double_dur = dur.mul(2);
    std.debug.assert(double_dur.value == 2 * (30 * 60 + 60));

    std.debug.assert(years.from(2010).add(10).compare(.eq, 2020));
}

test "Duration ordering, comparison" {
    std.debug.assert(years.from(2).order(seconds.from(1_000)) == .gt);
    std.debug.assert(nanoseconds.from(1000).compare(.eq, microseconds.from(1)));
}

test "Duration cast" {
    std.debug.assert(durationCast(milliseconds, seconds.from(4)).compare(.eq, 4_000));
}

test "SysClock times" {
    const t1 = SysClock.now();
    std.time.sleep(1_000_000_000);
    const t2 = SysClock.now();

    std.debug.assert(durationCast(seconds, t2.sub(t1)).compare(.eq, 1));
}
