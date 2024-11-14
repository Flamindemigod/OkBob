const std = @import("std");

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
const DATETIME = struct {
    day: u8 = 1,
    month: u8 = 1,
    year: u16 = 1970,

    hours: u8 = 0,
    mins: u8 = 0,

    fn format(self: *DATETIME, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{d}/{d}/{d} {d}:{d}", .{ self.day, self.month, self.year, self.hours, self.mins });
    }
};

// Returns the number of days in a month for a given year and month (1-based)
fn days_in_month(year: u16, month: u8) u8 {
    switch (month) {
        1, 3, 5, 7, 8, 10, 12 => return 31,
        4, 6, 9, 11 => return 30,
        2 => {
            // Check for leap year
            if ((year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)) {
                return 29;
            }
            return 28;
        },
        else => return 0, // Invalid month
    }
}
const SECONDS_IN_A_DAY: i64 = 86400; // 60 * 60 * 24
//
pub fn parse_timestamp(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    var ts: i64 = timestamp;
    var datetime: DATETIME = DATETIME{};

    var current_year = datetime.year;
    while (ts >= SECONDS_IN_A_DAY * 365) {
        const days_in_year: u16 = if ((current_year % 4 == 0 and current_year % 100 != 0) or (current_year % 400 == 0)) 366 else 365;
        if (ts >= SECONDS_IN_A_DAY * days_in_year) {
            ts -= SECONDS_IN_A_DAY * days_in_year;
            current_year += 1;
        } else {
            break;
        }
    }
    datetime.year = current_year;

    // Loop over months in the current year
    var current_month: u8 = 1;
    while (ts >= SECONDS_IN_A_DAY * days_in_month(datetime.year, current_month)) {
        const days_in_current_month = days_in_month(datetime.year, current_month);
        if (ts >= SECONDS_IN_A_DAY * days_in_current_month) {
            ts -= SECONDS_IN_A_DAY * days_in_current_month;
            current_month += 1;
        } else {
            break;
        }
    }
    datetime.month = current_month;

    // Now, calculate the day
    while (ts >= SECONDS_IN_A_DAY) {
        ts -= SECONDS_IN_A_DAY;
        datetime.day += 1;
    }

    // Calculate hours, minutes, and seconds from the remaining seconds
    // Now, calculate the day
    while (ts >= 3600) {
        ts -= 3600;
        datetime.hours += 1;
    }

    while (ts >= 60) {
        ts -= 60;
        datetime.mins += 1;
    }
    return try datetime.format(allocator);
}
