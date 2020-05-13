const std = @import("std");
pub const Ratio = @import("lepto/ratio.zig");

const Order = std.math.Order;
const CompareOperator = std.math.CompareOperator;

fn isValueArithmetic(comptime T: type, comptime Repr: type) bool {
    return T == Repr or
        T == comptime_int;
}

fn isInteger(comptime T: type) bool {
    return std.meta.trait.is(.Int)(T);
}

fn checkInteger(comptime T: type) void {
    if (comptime !isInteger(T)) {
        @compileError("Type " ++ @typeName(T) ++ " is not an integer type.");
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

    const Period = Ratio.gcd(Duration1.period, Duration2.period);

    const min1 = @as(comptime_int, std.math.minInt(Repr1));
    const max1 = @as(comptime_int, std.math.maxInt(Repr1));

    const min_secs1 = Duration1.period.mulInt(min1);
    const max_secs1 = Duration1.period.mulInt(max1);

    const min2 = @as(comptime_int, std.math.minInt(Repr2));
    const max2 = @as(comptime_int, std.math.maxInt(Repr2));

    const min_secs2 = Duration2.period.mulInt(min2);
    const max_secs2 = Duration2.period.mulInt(max2);

    const min_repr = Period.inverse().mulInt(std.math.min(min_secs1, min_secs2));
    const max_repr = Period.inverse().mulInt(std.math.max(max_secs1, max_secs2));

    if (min_repr == 0) {
        const bits = std.math.ceil(@as(f64, std.math.log2(@intToFloat(comptime_float, max_repr + 1))));
        return Duration(@Type(std.builtin.TypeInfo{
            .Int = .{
                .is_signed = true,
                .bits = @floatToInt(comptime_int, bits),
            },
        }), Period);
    }

    const bits = std.math.ceil(@as(f64, std.math.log2(@intToFloat(comptime_float, -min_repr - 1)))) + 1;
    return Duration(@Type(std.builtin.TypeInfo{
        .Int = .{
            .is_signed = true,
            .bits = @floatToInt(comptime_int, bits),
        },
    }), Period);

}

pub fn Duration(comptime Representation: type, comptime Period: Ratio) type {
    checkInteger(Representation);

    return struct {
        const Self = @This();

        pub const period = Period;
        pub const representation = Representation;

        pub const zero = Self.from(0);
        pub const min = Self.from(std.math.minInt(representation));
        pub const max = Self.from(std.math.maxInt(representation));

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
            const Rhs = @TypeOf(rhs);
            if (comptime isValueArithmetic(Rhs, representation))
                return .{ .value = lhs.value - rhs };

            const NewPeriod = ArithmeticResult(Rhs).period;
            const NewRepr = ArithmeticResult(Rhs).representation;

            const lhs_value = period.div(NewPeriod).simplify().mulInt(@intCast(NewRepr, lhs.value));
            const rhs_value = Rhs.period.div(NewPeriod).simplify().mulInt(@intCast(NewRepr, rhs.value));

            return .{ .value = lhs_value - rhs_value };
        }

        pub fn add(lhs: Self, rhs: var) ArithmeticResult(@TypeOf(rhs)) {
            const Rhs = @TypeOf(rhs);
            if (comptime isValueArithmetic(Rhs, representation))
                return .{ .value = lhs.value + rhs };

            const NewPeriod = ArithmeticResult(Rhs).period;
            const NewRepr = ArithmeticResult(Rhs).representation;

            const lhs_value = period.div(NewPeriod).simplify().mulInt(@intCast(NewRepr, lhs.value));
            const rhs_value = Rhs.period.div(NewPeriod).simplify().mulInt(@intCast(NewRepr, rhs.value));

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
            const Rhs = @TypeOf(rhs);
            if (comptime isValueArithmetic(Rhs, representation))
                return std.math.order(lhs.value, rhs);

            const NewPeriod = ArithmeticResult(Rhs).period;
            const NewRepr = ArithmeticResult(Rhs).representation;

            const lhs_value = scaleDurationTo(lhs, NewRepr, NewPeriod);
            const rhs_value = scaleDurationTo(rhs, NewRepr, NewPeriod);

            return std.math.order(lhs_value, rhs_value);
        }

        pub fn compare(lhs: Self, op: CompareOperator, rhs: var) bool {
            const Rhs = @TypeOf(rhs);
            if (comptime isValueArithmetic(Rhs, representation))
                return std.math.compare(lhs.value, op, rhs);

            const NewPeriod = ArithmeticResult(Rhs).period;
            const NewRepr = ArithmeticResult(Rhs).representation;

            const lhs_value = scaleDurationTo(lhs, NewRepr, NewPeriod);
            const rhs_value = scaleDurationTo(rhs, NewRepr, NewPeriod);

            return std.math.compare(lhs_value, op, rhs_value);
        }

        pub fn ctStr() []const u8 {
            return "Duration(" ++ @typeName(representation) ++ ", " ++ period.ctStr() ++ " secs)";
        }
    };
}

fn scaleDurationTo(duration: var, comptime NewRepr: type, comptime NewPeriod: Ratio) NewRepr {
    const OldDuration = @TypeOf(duration);
    comptime checkDuration(OldDuration);

    if (comptime (std.meta.bitCount(NewRepr) > std.meta.bitCount(OldDuration.representation)))
        return Ratio.mulInt(OldDuration.period.div(NewPeriod).simplify(), @intCast(NewRepr, duration.value));

    return @intCast(NewRepr, Ratio.mulInt(OldDuration.period.div(NewPeriod).simplify(), duration.value));
}

pub fn durationCast(comptime Dest: type, duration: var) Dest {
    comptime checkDuration(Dest);

    const Src = @TypeOf(duration);
    comptime checkDuration(Src);
    if (Src == Dest) return duration;

    return .{ .value = scaleDurationTo(duration, Dest.representation, Dest.period) };
}

// These duration types cover a range of at least +- 292 years
// Years is equal to 365.2425 days (the average length of a Gregorian year)
// Months is equal to 1/12 of years, weeks to 7 days
pub const nanoseconds = Duration(i64, Ratio.nano);
pub const microseconds = Duration(i55, Ratio.micro);
pub const milliseconds = Duration(i45, Ratio.milli);
pub const seconds = Duration(i35, Ratio.one);
pub const minutes = Duration(i29, Ratio.from(60, 1));
pub const hours = Duration(i23, Ratio.from(3600, 1));
pub const days = Duration(i25, Ratio.from(86400, 1));
pub const weeks = Duration(i22, Ratio.from(604800, 1));
pub const months = Duration(i20, Ratio.from(2629746, 1));
pub const years = Duration(i17, Ratio.from(31556952, 1));

pub fn TimePoint(comptime _Clock: type, comptime _Duration: type) type {
    return struct {
        const Self = @This();

        pub const clock = _Clock;
        pub const duration = _Duration;

        pub const zero = Self.from(duration.zero);
        pub const min = Self.from(duration.min);
        pub const max = Self.from(duration.max);

        duration_since_epoch: duration,

        // TODO: More overloads for this? Initialize from another TimePoint?
        fn from(dur: var) Self {
            return .{ .duration_since_epoch = durationCast(duration, dur) };
        }

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
                return Self.from(lhs.duration_since_epoch.sub(rhs));

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
            return Self.from(lhs.duration_since_epoch.add(rhs));
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

            const duration_in_hns = Duration(i64, Ratio.mul(nanoseconds.period, Ratio.from(100, 1)).simplify()).from(ft64);
            return time_point.from(duration_in_hns.sub(nt_to_unix_epoch));
        }
        if (std.builtin.os.tag == .wasi and !std.builtin.link_libc) {
            var ns: std.os.wasi.timestamp_t = undefined;
            const err = std.os.wasi.clock_time_get(std.os.wasi.CLOCK_REALTIME, 1, &ns);
            std.debug.assert(err == std.os.wasi.ESUCCESS);

            return time_point.from(nanoseconds.from(@intCast(i64, ns)));
        }
        if (comptime std.Target.current.isDarwin()) {
            var tv: std.os.darwin.timeval = undefined;
            var err = std.os.darwin.gettimeofday(&tv, null);
            std.debug.assert(err == 0);
            const secs = seconds.from(@intCast(seconds.representation, tv.tv_sec));
            const microsecs = microseconds.from(@intCast(microseconds.representation, tv.tv_usec));

            return time_point.from(secs.add(microsecs));
        }

        var ts: std.os.timespec = undefined;
        std.os.clock_gettime(std.os.CLOCK_REALTIME, &ts) catch unreachable;
        const secs = seconds.from(@intCast(seconds.representation, ts.tv_sec));
        const nanosecs = nanoseconds.from(@intCast(nanoseconds.representation, ts.tv_nsec));

        return time_point.from(secs.add(nanosecs));
    }
};

pub fn SysTime(comptime PeriodInSecs: var) type {
    return TimePoint(SysClock, PeriodInSecs);
}
pub const SysDays = SysTime(days);

// TODO: SteadyClock
// TODO: Write a good description, docs
// TODO: Zoned times, field types
