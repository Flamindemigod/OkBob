const std = @import("std");
const zdt = @import("zdt");

const PARSER = struct {
    directive: []const u8,
    postProcess: *const fn (dt: zdt.Datetime) zdt.ZdtError!zdt.Datetime,
};

const parserDirectives = [_]PARSER{
    PARSER{ .directive = "%d/%m", .postProcess = struct {
        pub fn call(dt: zdt.Datetime) !zdt.Datetime {
            const temp = try zdt.Datetime.now(if (dt.tz) |tz| .{ .tz = tz } else null);
            const ddt = temp.toFields();
            var dtf = dt.toFields();
            dtf.year = ddt.year;
            return try zdt.Datetime.fromFields(dtf);
        }
    }.call },

    PARSER{ .directive = "%H:%M", .postProcess = struct {
        pub fn call(dt: zdt.Datetime) !zdt.Datetime {
            const temp = try zdt.Datetime.now(if (dt.tz) |tz| .{ .tz = tz } else null);
            const ddt = temp.toFields();
            var dtf = dt.toFields();
            dtf.day = ddt.day;
            dtf.month = ddt.month;
            dtf.year = ddt.year;
            return try zdt.Datetime.fromFields(dtf);
        }
    }.call },
    PARSER{ .directive = "%d/%m/%y", .postProcess = struct {
        pub fn call(dt: zdt.Datetime) !zdt.Datetime {
            return dt;
        }
    }.call },
    PARSER{ .directive = "%d/%m %H:%M", .postProcess = struct {
        pub fn call(dt: zdt.Datetime) !zdt.Datetime {
            const temp = try zdt.Datetime.now(if (dt.tz) |tz| .{ .tz = tz } else null);
            const ddt = temp.toFields();
            var dtf = dt.toFields();
            dtf.year = ddt.year;
            return try zdt.Datetime.fromFields(dtf);
        }
    }.call },
    PARSER{ .directive = "%d/%m/%y %H:%M", .postProcess = struct {
        pub fn call(dt: zdt.Datetime) !zdt.Datetime {
            return dt;
        }
    }.call },
};

pub fn parse_to_timestamp(allocator: std.mem.Allocator, string: []const u8) !i64 {
    var local_zone = try zdt.Timezone.tzLocal(allocator);
    defer local_zone.deinit();
    var dt: zdt.Datetime = undefined;
    for (parserDirectives) |pd| {
        dt = zdt.Datetime.fromString(string, pd.directive) catch continue;
        dt = try pd.postProcess(dt);
        break;
    }

    dt = try dt.tzLocalize(.{ .tz = &local_zone });
    return @intCast(dt.toUnix(zdt.Duration.Resolution.second));
}

pub fn parse_timestamp(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    var formatted = std.ArrayList(u8).init(allocator);
    defer formatted.deinit();

    var local_zone = try zdt.Timezone.tzLocal(allocator);
    defer local_zone.deinit();

    const now = try zdt.Datetime.fromUnix(timestamp, zdt.Duration.Resolution.second, .{ .tz = &local_zone });
    try now.toString("%a %b %d %Y %H:%M", formatted.writer());
    return formatted.toOwnedSlice();
}

pub fn parse_durations(str: []const u8) !zdt.Duration.RelativeDelta {
    var delta = zdt.Duration.RelativeDelta{};
    var cursor: usize = 0;
    for (str, 0..) |char, idx| {
        switch (char) {
            'Y' => {
                delta.years = try std.fmt.parseInt(u32, str[cursor..idx], 0);
                cursor = idx + 1;
            },
            'M' => {
                delta.months = try std.fmt.parseInt(u32, str[cursor..idx], 0);
                cursor = idx + 1;
            },
            'D' => {
                delta.days = try std.fmt.parseInt(u32, str[cursor..idx], 0);
                cursor = idx + 1;
            },
            'W' => {
                delta.weeks = try std.fmt.parseInt(u32, str[cursor..idx], 0);
                cursor = idx + 1;
            },
            'h' => {
                delta.hours = try std.fmt.parseInt(u32, str[cursor..idx], 0);
                cursor = idx + 1;
            },
            'm' => {
                delta.minutes = try std.fmt.parseInt(u32, str[cursor..idx], 0);
                cursor = idx + 1;
            },
            's' => {
                delta.seconds = try std.fmt.parseInt(u32, str[cursor..idx], 0);
                cursor = idx + 1;
            },
            else => {},
        }
    }
    return delta;
}
