const std = @import("std");
const zdt = @import("zdt");
pub fn to_lowercase(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result: []u8 = try allocator.alloc(u8, input.len);

    // Iterate through each character and convert it to lowercase
    for (input, 0..) |ch, i| {
        result[i] = std.ascii.toLower(ch);
    }

    return result;
}

pub fn string_join(input: std.ArrayList([]const u8), sep: []const u8, allocator: std.mem.Allocator) ![]u8 {
    //Calulate the size of the resulting string
    var total_len: usize = 0;
    for (input.items, 1..) |item, i| {
        total_len += item.len;
        if (i < input.items.len) {
            total_len += sep.len;
        }
    }

    //Allocate memory for the result
    var result = try allocator.alloc(u8, total_len);

    var cursor: usize = 0;
    for (input.items, 1..) |item, i| {
        std.mem.copyForwards(u8, result[cursor..], item);
        cursor += item.len;

        if (i < input.items.len) {
            std.mem.copyForwards(u8, result[cursor..], sep);
            cursor += sep.len;
        }
    }
    return result;
}

const directives = [_][]const u8{ "%d/%m", "%H:%M", "%d/%m/%y", "%d/%m %H:%M", "%d/%m/%y %H:%M" };

pub fn parse_to_timestamp(allocator: std.mem.Allocator, string: []const u8) !i64 {
    var local_zone = try zdt.Timezone.tzLocal(allocator);
    defer local_zone.deinit();

    var dt: zdt.Datetime = undefined;
    for (directives) |directive| {
        dt = zdt.Datetime.fromString(string, directive) catch continue;
        break;
    }
    var d = zdt.Datetime.nowUTC().toFields();

    d.second = 0;
    d.nanosecond = 0;
    d.hour = 0;
    d.minute = 0;

    const f = zdt.Datetime.Fields{};

    var fields = dt.toFields();
    fields = .{
        .year = if (fields.year == f.year) d.year else fields.year,
        .month = if (fields.month == f.month) d.month else fields.month,
        .day = if (fields.day == f.day) d.day else fields.day,
        .hour = if (fields.hour == f.hour) d.hour else fields.hour,
        .minute = if (fields.minute == f.minute) d.minute else fields.minute,
        .second = if (fields.second == f.second) d.second else fields.second,
        .nanosecond = if (fields.nanosecond == f.nanosecond) d.nanosecond else fields.nanosecond,
    };
    dt = try zdt.Datetime.fromFields(fields);

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
