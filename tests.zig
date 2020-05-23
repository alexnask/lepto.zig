const std = @import("std");
usingnamespace (@import("lepto.zig"));

test "Ratio mod" {
    const res = Ratio.mod(Ratio.from(-3, 5), Ratio.from(1, 4));
    comptime std.debug.assert(res.eql(Ratio.from(-1, 10)));
}

test "Ratio GCD" {
    const res = Ratio.gcd(Ratio.milli, Ratio.micro);
    comptime std.debug.assert(res.eql(Ratio.micro));
}

test "Duration arithmetic" {
    const dur = comptime minutes.from(30).add(seconds.from(60));
    std.debug.assert(dur.value == 30 * 60 + 60);

    const double_dur = dur.mul(2);
    std.debug.assert(double_dur.value == 2 * (30 * 60 + 60));

    std.debug.assert(years.from(2010).add(10).compare(.eq, 2020));
}

test "Duration ordering, comparison" {
    comptime std.debug.assert(years.from(2).order(seconds.from(1_000)) == .gt);
    comptime std.debug.assert(nanoseconds.from(1000).compare(.eq, microseconds.from(1)));
}

fn testRange(comptime Dur: type) void {
    std.debug.assert(Dur.max.compare(.gte, years.from(292)));
    std.debug.assert(Dur.min.compare(.lte, years.from(-292)));
}

test "Standard duration rages" {
    @setEvalBranchQuota(2000);
    comptime testRange(nanoseconds);
    comptime testRange(microseconds);
    comptime testRange(milliseconds);
    comptime testRange(seconds);
    comptime testRange(minutes);
    comptime testRange(hours);
    comptime testRange(days);
    comptime testRange(weeks);
    comptime testRange(months);
    comptime testRange(years);
}

test "Duration cast" {
    comptime std.debug.assert(durationCast(milliseconds, seconds.from(4)).compare(.eq, 4_000));
}

fn testClock(comptime Clock: type) void {
     const t1 = Clock.now();
    std.time.sleep(1_000_000_000);
    const t2 = Clock.now();

    std.debug.assert(durationCast(seconds, t2.sub(t1)).compare(.eq, 1));
}

test "SysClock times" {
   testClock(SysClock);
}

test "SteadyClock times" {
    testClock(SteadyClock);
}
