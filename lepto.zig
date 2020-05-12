const std = @import("std");
pub const Ratio = @import("lepto/ratio.zig");

const Order = std.math.Order;
const CompareOperator = std.math.CompareOperator;

// TODO: Split these into another file
fn numericLowestValue(comptime T: type) T {
    std.debug.assert(isNumeric(T));

    if (std.meta.trait.is(.Int)(T)) {
        return std.math.minint(T);
    }

    // Floating point representations
    return switch (T) {
        f16 => -std.math.f16_max,
        f32 => -std.math.f32_max,
        f64 => -std.math.f64_max,
        f128 => -std.math.f128_max,
        else => unreachable,
    };
}

fn numericHighestValue(comptime T: type) T {
    std.debug.assert(isNumeric(T));

    if (std.meta.trait.is(.Int)(T)) {
        return std.math.maxint(T);
    }

    // Floating point representations
    return switch (T) {
        f16 => std.math.f16_max,
        f32 => std.math.f32_max,
        f64 => std.math.f64_max,
        f128 => std.math.f128_max,
        else => unreachable,
    };
}

fn isValueArithmetic(comptime T: type, comptime Repr: type) bool {
    return T == Repr or
        T == comptime_int or
        (std.meta.trait.is(.Float)(Repr) and T == comptime_float);
}

fn isNumeric(comptime T: type) bool {
    return std.meta.trait.is(.Int)(T) or std.meta.trait.is(.Float)(T);
}

fn checkNumeric(comptime T: type) void {
    if (comptime !isNumeric(T)) {
        @compileError("Type " ++ @typeName(T) ++ " is non-numeric.");
    }
}

fn isDuration(comptime T: type) bool {
    if (!@hasDecl(T, "period") or !@hasDecl(T, "representation")) return false;
    const value_info = std.meta.fieldInfo(T, "value");
    return value_info.field_type == T.representation;
}

fn checkDuration(comptime T: type) void {
    if (comptime !isDuration(T)) {
        @compileError("Type " ++ @typeName(T) ++ " is not a duration type.");
    }
}

fn isTimePoint(comptime T: type) bool {
    if (!@hasDecl(T, "clock") or !@hasDecl(T, "duration")) return false;
    if (comptime !isDuration(T.duration)) return false;

    const dur_info = std.meta.fieldInfo(T, "duration_since_epoch");
    return dur_info.field_type == T.duration;
}

pub fn isClock(comptime T: type) bool {
    if (!@hasDecl(T, "duration") or !@hasDecl(T, "time_point") or !@hasDecl(T, "is_steady")) return false;
    if (comptime (!isDuration(T.duration) or !isTimePoint(T.time_point) or @TypeOf(T.is_steady) != bool)) return false;

    // TODO: Check for `now()`
}

pub fn CommonDuration(comptime Duration1: type, comptime Duration2: type) type {
    checkDuration(Duration2);
    checkDuration(Duration1);

    if (Duration1 == Duration2) return Duration1;

    const Repr1 = Duration1.representation;
    const Repr2 = Duration2.representation;

    const is_float1 = comptime std.meta.trait.is(.Float)(Repr1);
    const is_float2 = comptime std.meta.trait.is(.Float)(Repr2);

    // TODO: Split this into a CommonNumericalType
    const Repr = if (is_float1 and !is_float2)
        Repr1
    else if (!is_float1 and is_float2)
        Repr2
    else if (is_float1 and is_float2)
        if (std.meta.bitCount(Repr1) > std.meta.bitCount(Repr2))
            Repr1
        else
            Repr2
    else block: {
        // TODO: Check this more correctly by taking periods into account, choosing the widest duration possible
        //       and returning a type that fits that duration with the new period
        const min1 = std.math.minInt(Repr1);
        const max1 = std.math.maxInt(Repr1);

        const min2 = std.math.minInt(Repr2);
        const max2 = std.math.maxInt(Repr2);

        if (min1 <= min2 and max1 >= max2)
            break :block Repr1
        else if (min2 <= min1 and max2 >= max1)
            break :block Repr2;

        @compileError("TODO: Unsafe common duration.");
    };

    const Period1 = Duration1.period;
    const Period2 = Duration2.period;
    const Period = Ratio.gcd(Period1, Period2).divisor.simplify();

    return Duration(Repr, Period);
}

pub fn Duration(comptime Representation: type, comptime Period: Ratio) type {
    checkNumeric(Representation);

    return struct {
        const Self = @This();

        pub const period = Period;
        pub const representation = Representation;

        pub const zero = Self{ .value = 0 };
        pub const min = Self{ .value = numericLowestValue(representation) };
        pub const max = Self{ .value = numericHighestValue(representation) };

        value: representation,

        pub fn from(value: representation) Self {
            return .{
                .value = value,
            };
        }

        // Arithmetic
        fn ArithmeticResult(comptime T: type) type {
            if (comptime isValueArithmetic(T, representation)) return Self;
            if (comptime !isDuration(T))
                @compileError("Expected representation type " ++ @typeName(representation) ++ " or duration type, got " ++ @typeName(T));

            return CommonDuration(Self, T);
        }

        pub fn sub(lhs: Self, rhs: var) ArithmeticResult(@TypeOf(rhs)) {
            if (comptime isValueArithmetic(@TypeOf(rhs), representation))
                return .{ .value = lhs.value - rhs };

            const NewPeriod = ArithmeticResult(@TypeOf(rhs)).period;
            const NewRepr = ArithmeticResult(@TypeOf(rhs)).representation;
            const lhs_value = scaleDurationTo(lhs, NewRepr, NewPeriod);
            const rhs_value = scaleDurationTo(rhs, NewRepr, NewPeriod);
            return .{ .value = lhs_value - rhs_value };
        }

        pub fn add(lhs: Self, rhs: var) ArithmeticResult(@TypeOf(rhs)) {
            if (comptime isValueArithmetic(@TypeOf(rhs), representation))
                return .{ .value = lhs.value + rhs };

            const NewPeriod = ArithmeticResult(@TypeOf(rhs)).period;
            const NewRepr = ArithmeticResult(@TypeOf(rhs)).representation;
            const lhs_value = scaleDurationTo(lhs, NewRepr, NewPeriod);
            const rhs_value = scaleDurationTo(rhs, NewRepr, NewPeriod);
            return .{ .value = lhs_value + rhs_value };
        }

        // These only make sense with plain values, not other durations.
        pub fn mul(lhs: Self, rhs: representation) Self {
            return .{ .value = lhs.value * rhs };
        }

        pub fn div(lhs: Self, rhs: representation) Self {
            return .{ .value = lhs.value * rhs };
        }

        // Order and compare
        pub fn order(lhs: Self, rhs: var) Order {
            if (comptime isValueArithmetic(@TypeOf(rhs), representation))
                return std.math.order(lhs.value, rhs);

            const NewPeriod = ArithmeticResult(@TypeOf(rhs)).period;
            const NewRepr = ArithmeticResult(@TypeOf(rhs)).representation;
            const lhs_value = scaleDurationTo(lhs, NewRepr, NewPeriod);
            const rhs_value = scaleDurationTo(rhs, NewRepr, NewPeriod);
            return std.math.order(lhs_value, rhs_value);
        }

        pub fn compare(lhs: Self, op: CompareOperator, rhs: var) bool {
            if (comptime isValueArithmetic(@TypeOf(rhs), representation))
                return std.math.compare(lhs.value, op, rhs);

            const NewPeriod = ArithmeticResult(@TypeOf(rhs)).period;
            const NewRepr = ArithmeticResult(@TypeOf(rhs)).representation;
            const lhs_value = scaleDurationTo(lhs, NewRepr, NewPeriod);
            const rhs_value = scaleDurationTo(rhs, NewRepr, NewPeriod);
            return std.math.compare(lhs_value, op, rhs_value);
        }
    };
}

fn scaleDurationTo(duration: var, comptime NewRepr: type, comptime NewPeriod: Ratio) NewRepr {
    comptime checkDuration(@TypeOf(duration));
    return Ratio.mulRt(@TypeOf(duration).period.div(NewPeriod).simplify(), @intCast(NewRepr, duration.value));
}

pub fn durationCast(comptime Dest: type, duration: var) Dest {
    comptime checkDuration(Dest);

    const Src = @TypeOf(duration);
    comptime checkDuration(Src);
    if (Src == Dest) return duration;

    return .{ .value = scaleDurationTo(duration, Dest.representation, Dest.period) };
}

// These duration types cover a range of at least +- 40_000 years
// Years is equal to 365.2425 days (the average length of a Gregorian year)
// Months is equal to 1/12 of years, weeks to 7 days
pub const nanoseconds = Duration(i64, Ratio.nano);
pub const microseconds = Duration(i55, Ratio.micro);
pub const milliseconds = Duration(i45, Ratio.milli);
pub const seconds = Duration(i35, Ratio.one);
pub const minutes = Duration(i29, Ratio{ .num = 60 });
pub const hours = Duration(i29, Ratio{ .num = 3600 });
pub const days = Duration(i29, Ratio{ .num = 86400 });
pub const weeks = Duration(i29, Ratio{ .num = 604800 });
pub const months = Duration(i29, Ratio{ .num = 2629746 });
pub const years = Duration(i29, Ratio{ .num = 31556952 });

pub fn TimePoint(comptime _Clock: type, comptime _Duration: type) type {
    return struct {
        const Self = @This();

        pub const clock = _Clock;
        pub const duration = _Duration;

        pub const zero = Self{ .duration_since_epoch = 0 };
        pub const min = Self{ .duration_since_epoch = duration.min };
        pub const max = Self{ .duration_since_epoch = duration.max };

        duration_since_epoch: duration,

        // Arithmetic
        fn SubResult(comptime T: type) type {
            if (comptime isValueArithmetic(T, duration.representation)) return Self;
            if (comptime isDuration(T)) {
                return Time(Clock, CommonDuration(duration, T));
            }
            if (!comptime isTimePoint(T))
                @compileError("Expected representation type " ++ @typeName(duration.representation) ++ ", duration type or time type, got " ++ @typeName(T));

            return CommonDuration(duration, T.duration);
        }

        pub fn sub(lhs: Self, rhs: var) SubResult(@TypeOf(rhs)) {
            if (comptime !isTimePoint(@TypeOf(rhs)))
                return .{ .duration_since_epoch = lhs.duration_since_epoch.sub(rhs) };

            const casted_rhs = clockCast(clock, rhs);
            return lhs.duration_since_epoch.sub(casted_rhs.duration_since_epoch);
        }

        fn AddResult(comptime T: type) type {
            if (comptime isValueArithmetic(T, duration.representation))
                return T;

            if (!comptime isDuration(T))
                @compileError("Expected representation type " ++ @typeName(duration.representation) ++ " or duration type, got " ++ @typeName(T));

            return Time(Clock, CommonDuration(duration, T));
        }

        pub fn add(lhs: Self, rhs: var) AddResult(@TypeOf(rhs)) {
            return .{ .duration_since_epoch = lhs.duration_since_epoch.add(rhs) };
        }

        // Order and compare
        pub fn order(lhs: Self, rhs: var) Order {
            if (comptime isTimePoint(@TypeOf(rhs))) {
                const casted_rhs = clockCast(Clock, rhs);
                return lhs.duration_since_epoch.order(casted_rhs.duration_since_epoch);
            }

            return lhs.duration_since_epoch.order(rhs);
        }

        pub fn compare(lhs: Self, op: CompareOperator, rhs: var) bool {
            if (comptime isTimePoint(@TypeOf(rhs))) {
                const casted_rhs = clockCast(Clock, rhs);
                return lhs.duration_since_epoch.compare(op, casted_rhs.duration_since_epoch);
            }

            return lhs.duration_since_epoch.compare(op, rhs);
        }
    };
}

/// Casts a time from a clock to another.
pub fn clockCast(comptime DestClock: type, time: var) TimePoint(DestClock, @TypeOf(time).duration) {
    if (DestClock == @TypeOf(time).clock) return time;

    @compileError("TODO: Implement clock cast");
}

// Unix epoch (01/01/1970 00:00:00 UTC in the Gregorian calendar.)
pub const SysClock = struct {
    pub const duration = nanoseconds;
    pub const time_point = TimePoint(SysClock, duration);
    pub const is_steady = false;

    pub fn now() time_point {
        if (std.builtin.os.tag == .windows) {
            const nt_to_unix_epoch = seconds.from(11644473600);

            // TODO: Use GetSystemTimePreciseAsFileTime instead when available
            // (win8+ on desktop platforms)
            var ft: std.os.windows.FILETIME = undefined;
            // This clock has a granularity of 100 nanoseconds.
            std.os.windows.kernel32.GetSystemTimeAsFileTime(&ft);
            const ft64 = (@as(i64, ft.dwHighDateTime) << 32) | (@as(i64, ft.dwLowDateTime));

            const duration_in_hns = Duration(i64, Ratio.mul(nanoseconds.period, Ratio{ .num = 100 }).simplify()).from(ft64);
            return .{ .duration_since_epoch = durationCast(duration, duration_in_hns.sub(nt_to_unix_epoch)) };
        }
        if (std.builtin.os.tag == .wasi and !std.builtin.link_libc) {
            var ns: std.os.wasi.timestamp_t = undefined;
            const err = std.os.wasi.clock_time_get(std.os.wasi.CLOCK_REALTIME, 1, &ns);
            std.debug.assert(err == std.os.wasi.ESUCCESS);

            return .{ .duration_since_epoch = durationCast(duration, nanoseconds.from(@intCast(i64, ns))) };
        }
        if (comptime std.Target.current.isDarwin()) {
            var tv: std.os.darwin.timeval = undefined;
            var err = std.os.darwin.gettimeofday(&tv, null);
            std.debug.assert(err == 0);
            const secs = seconds.from(@intCast(seconds.representation, tv.tv_sec));
            const microsecs = microseconds.from(@intCast(microseconds.representation, tv.tv_usec));

            return .{ .duration_since_epoch = durationCast(duration, secs.add(microsecs)) };
        }

        var ts: std.os.timespec = undefined;
        std.os.clock_gettime(std.os.CLOCK_REALTIME, &ts) catch unreachable;
        const secs = seconds.from(@intCast(seconds.representation, ts.tv_sec));
        const nanosecs = nanoseconds.from(@intCast(nanoseconds.representation, ts.tv_nsec));

        return .{ .duration_since_epoch = durationCast(duration, secs.add(nanosecs)) };
    }
};

pub fn SysTime(comptime PeriodInSecs: var) type {
    return TimePoint(SysClock, PeriodInSecs);
}
pub const SysDays = SysTime(days);

// TODO: SteadyClock
// TODO: Write a good description, docs
// TODO: Zoned times, field types
