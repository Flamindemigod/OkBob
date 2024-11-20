const std = @import("std");
const utils = @import("../utils.zig");
const dt = @import("datetime.zig");
const db = @import("db.zig");
const zdt = @import("zdt");
const REMINDER = @import("reminders.zig").REMINDER;

const NOTIFICATION = struct {
    id: usize,
    name: []const u8,
    timeCreated: i64,
    timeNext: i64,
    timeInterval: []const u8,

    fn generateReminder(self: *const NOTIFICATION) !void {
        const reminder = REMINDER{
            .id = 0,
            .name = self.name,
            .timeCreated = self.timeNext,
        };
        try reminder.insert();
        var timeNext = try zdt.Datetime.fromUnix(self.timeNext, .second, null);
        timeNext = try dt.getTimeNext(timeNext, self.timeInterval);
        var stmt = try db.db.prepare("UPDATE notifications SET timeNext = $timeNext{i64} WHERE id = $id{usize}");
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .timeNext = @as(i64, @intCast(timeNext.toUnix(.second))),
            .id = self.id,
        });
    }

    fn insert(self: *const NOTIFICATION) !void {
        var stmt = try db.db.prepare("INSERT INTO notifications(isActive, name, timeCreated, timeNext, timeInterval) VALUES($isActive{bool}, $name{[]const u8}, $timeCreated{i64}, $timeNext{i64}, $timeInterval{[]const u8})");
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .isActive = @as(bool, true),
            .name = self.name,
            .timeCreated = self.timeCreated,
            .timeNext = self.timeNext,
            .timeInterval = self.timeInterval,
        });
    }
    fn dismiss(self: *NOTIFICATION) !void {
        var stmt = try db.db.prepare("UPDATE notifications SET isActive = 0 WHERE id = $id{usize}");
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .id = self.id,
        });
    }

    fn format_name(self: *const NOTIFICATION, allocator: std.mem.Allocator, leadingSpaces: []const u8) !std.ArrayList([]const u8) {
        const WINDOW = @import("../main.zig").WINDOW;
        const max_width = std.math.clamp(WINDOW.width, 5, 75);
        var stringBuffer = std.ArrayList([]const u8).init(allocator);
        var sb = std.ArrayList(u8).init(allocator);
        defer sb.deinit();
        var it = std.mem.splitScalar(u8, self.name, ' ');
        while (it.next()) |x| {
            if ((sb.items.len + x.len) >= max_width) {
                try stringBuffer.append(try sb.toOwnedSlice());
            }
            if (sb.items.len == 0) try sb.appendSlice(leadingSpaces);
            try sb.appendSlice(x);
            try sb.append(' ');
        }
        if (sb.items.len >= 0) try stringBuffer.append(try sb.toOwnedSlice());
        return stringBuffer;
    }

    fn print(self: *const NOTIFICATION, allocator: std.mem.Allocator, display_idx: usize) void {
        const writer = std.io.getStdOut().writer();
        const leadingSpaces = "    ";
        writer.print("Notification {d}\n", .{display_idx}) catch std.log.err("Failed to print to stdout", .{});
        const formatted_strings = self.format_name(allocator, leadingSpaces) catch return;
        for (formatted_strings.items) |str| {
            writer.print("{s}\n", .{str}) catch std.log.err("Failed to print to stdout", .{});
        }
        writer.print("{s}\n\n", .{dt.parse_timestamp(allocator, self.timeCreated) catch "Could not parse Timestamp"}) catch std.log.err("Failed to print to stdout", .{});
    }
};

pub fn fetchValid(allocator: std.mem.Allocator) !std.ArrayListUnmanaged(NOTIFICATION) {
    var note_list = std.ArrayListUnmanaged(NOTIFICATION){};
    var stmt = try db.db.prepare("SELECT id, name, timeCreated, timeNext, timeInterval FROM notifications where isActive = 1 and timeNext <= $currentTime{i64}");
    defer stmt.deinit();

    var iter = try stmt.iterator(NOTIFICATION, .{ .currentTime = std.time.timestamp() });
    while (try iter.nextAlloc(allocator, .{})) |vals| {
        try note_list.append(allocator, @as(NOTIFICATION, vals));
    }
    return note_list;
}
fn fetch(allocator: std.mem.Allocator) !std.ArrayListUnmanaged(NOTIFICATION) {
    var note_list = std.ArrayListUnmanaged(NOTIFICATION){};
    var stmt = try db.db.prepare("SELECT id, name, timeCreated, timeNext, timeInterval FROM notifications where isActive = 1");
    defer stmt.deinit();

    var iter = try stmt.iterator(NOTIFICATION, .{});
    while (try iter.nextAlloc(allocator, .{})) |vals| {
        try note_list.append(allocator, @as(NOTIFICATION, vals));
    }
    return note_list;
}

fn note_insert_from_builder(allocator: std.mem.Allocator, builder: *std.ArrayList([]const u8), note: *std.ArrayList(NOTIFICATION), timeStart: *i64, intervalString: []const u8) !void {
    if (builder.items.len > 0) {
        const timeStartDateTime = try zdt.Datetime.fromUnix(@intCast(timeStart.*), .second, null);
        const t = try dt.getTimeNext(timeStartDateTime, intervalString);
        const tNext: i64 = @intCast(t.toUnix(.second));
        const joined_string = try utils.string_join(builder.*, " ", allocator);
        try note.append(NOTIFICATION{ .id = 0, .name = joined_string, .timeCreated = timeStart.*, .timeNext = tNext, .timeInterval = intervalString });
        builder.items.len = 0;
    }
}

//NOTE: Setting Notifications should be of format
// `OkBob notify Buy Milk`
// Where the notification text is "Buy Milk"IF NOT EXISTS
// This would create a notification that generates a reminder every day
// at the time the notification was created at.
// If we want to specify the time that a notification trigger is based on then
// we can suppy flags like -t="{time}" for setting the start time
// and -i="{interval}" for setting the reminder interval
// At each trigger of the notification it generates a reminder
// that must be dismissed throught he -remind subcommand
// and using -notify will remove the notification
// and it will not generate any subsequent reminders
// You can still chain notifications using ! as a seperator

//NOTE: If you dont add any more arguments. It will display what notifications are currently active
pub fn set(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
    var note_builder = std.ArrayList([]const u8).init(allocator);
    defer note_builder.deinit();
    var notes = std.ArrayList(NOTIFICATION).init(allocator);
    defer notes.deinit();
    var intervalString: []const u8 = "1Y";
    var timeStart = std.time.timestamp();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "!")) {
            try note_insert_from_builder(allocator, &note_builder, &notes, &timeStart, intervalString);
            continue;
        } else if (arg.len > 3 and std.mem.eql(u8, arg[0..3], "-t=")) {
            timeStart = try dt.parse_to_timestamp(allocator, arg[3..]);
            continue;
        } else if (arg.len > 3 and std.mem.eql(u8, arg[0..3], "-i=")) {
            intervalString = arg[3..];
            continue;
        }
        try note_builder.append(arg);
    }
    try note_insert_from_builder(allocator, &note_builder, &notes, &timeStart, intervalString);
    for (notes.items) |note| {
        try note.insert();
    }
    if (notes.items.len == 0) {
        const n = try fetch(allocator);
        for (n.items, 0..) |notif, idx| {
            notif.print(allocator, idx);
        }
    }
}

//NOTE: Dismissing Notifications should be of format
// `OkBob -notify {idx}`
// Where the idx is the display index that gets listed by the normal
//Though that gets fairly inconvient when
//needing to dismiss multiple reminders at once.
//So to dismiss notifications we can use
//`OkBob -notify 0 ! 2 ! 5`
//While we could just split them by spaces as indexes would never have spaces within them.
//I prefer having it split by ! for consistency with other interfaces
//So i'll also support just spliting by spaces as well
//`OkBob -notify 0 ! 2 5`
//So that would dismiss reminders 0, 2, 5
pub fn dismiss(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
    const note_list = try fetch(allocator);
    var dismissQueue = std.ArrayList(usize).init(allocator);
    defer dismissQueue.deinit();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "!")) {
            continue;
        }
        var parsedIdx = std.ArrayListUnmanaged(usize){};

        try parsedIdx.append(allocator, std.fmt.parseInt(usize, arg, 0) catch |err| blk: {
            switch (err) {
                std.fmt.ParseIntError.InvalidCharacter => {
                    var start: usize = undefined;
                    var end: usize = undefined;
                    if (std.mem.indexOf(u8, arg, "..")) |point| {
                        start = try std.fmt.parseInt(usize, arg[0..point], 0);
                        end = if (point + 2 >= arg.len) note_list.items.len - 1 else (try std.fmt.parseInt(u8, arg[point + 2 ..], 0));
                    } else if (std.mem.indexOf(u8, arg, ":")) |point| {
                        start = try std.fmt.parseInt(usize, arg[0..point], 0);
                        end = if (point + 1 >= arg.len) note_list.items.len - 1 else (start + try std.fmt.parseInt(u8, arg[point + 1 ..], 0) - 1);
                    } else {
                        @panic("Not Valid Seperators");
                    }
                    for (start..end) |val| {
                        try parsedIdx.append(allocator, val);
                    }
                    break :blk end;
                },
                else => unreachable,
            }
        });

        if (std.mem.max(usize, parsedIdx.items) < note_list.items.len) {
            try dismissQueue.appendSlice(parsedIdx.items);
            parsedIdx.deinit(allocator);
        } else {
            std.log.err("{any} is not within the index bounds of the active notifications\n", .{parsedIdx.items});
        }
    }
    std.log.info("Removing the following notifications", .{});
    for (dismissQueue.items) |idx| {
        note_list.items[idx].print(allocator, idx);
        try note_list.items[idx].dismiss();
    }
}

pub fn generateRemindersFromNotifs(allocator: std.mem.Allocator) !void {
    var notifications = try fetchValid(allocator);
    defer notifications.deinit(allocator);
    for (notifications.items) |notif| {
        try notif.generateReminder();
    }
}

pub fn printHelpText() !void {
    const writer = std.io.getStdErr().writer();
    try writer.print("OkBob Notify Subcommand Usage\n", .{});
    try writer.print("\tOkBob notify\n", .{});
    try writer.print("\tOkBob notify [..reminder_name] -t=[date_time] -i=[interval] ! ...\n", .{});
    try writer.print("\tOkBob -notify [id] ...\n", .{});
    try writer.print("\n", .{});
    try writer.print("Date Time:\n", .{});
    try writer.print("\tThe parser supports several formats\n", .{});
    try writer.print("\tDD/MM\n", .{});
    try writer.print("\t\tSets the day and month. Year is current year\n", .{});
    try writer.print("\thh:mm\n", .{});
    try writer.print("\t\tSets the Hours and Minutes. Day is today\n", .{});
    try writer.print("\tDD/MM/YY\n", .{});
    try writer.print("\t\tSets the date. Time is 00:00\n", .{});
    try writer.print("\tDD/MM hh:mm\n", .{});
    try writer.print("\t\tSets the day, month, hour, minutes\n", .{});
    try writer.print("\tDD/MM/YY hh:mm\n", .{});
    try writer.print("\t\tSets the day, month, year, hour, minutes\n", .{});
    try writer.print("\n", .{});
    try writer.print("Interval:\n", .{});
    try writer.print("\tIntervals are pretty simple\n", .{});
    try writer.print("\tThey are essentially a single string with concatenated params\n", .{});
    try writer.print("\t\t1Y => 1 Year\n", .{});
    try writer.print("\t\t1M => 1 Month\n", .{});
    try writer.print("\t\t1W => 1 Week\n", .{});
    try writer.print("\t\t1D => 1 Day\n", .{});
    try writer.print("\t\t1h => 1 Hour\n", .{});
    try writer.print("\t\t1m => 1 Minute\n", .{});
    try writer.print("\t\t1s => 1 Second\n", .{});
    try writer.print("\tSo you can effectively use it like\n", .{});
    try writer.print("\t\t1Y2W20h10m\n", .{});
    try writer.print("\tWhich sets the interval to 1 Year, 14 days, 20 Hours and 10 minutes\n", .{});
    try writer.print("\n", .{});
    try writer.print("Ids:\n", .{});
    try writer.print("\tIds are basically the indexes of the active notifications\n", .{});
    try writer.print("\tYou can see them when you use\n", .{});
    try writer.print("\t\tOkBob notify\n", .{});
    try writer.print("\tWithout any additional parameters\n", .{});
    try writer.print("\tIds are kinda interesting in that they can be a single number or a slice\n", .{});
    try writer.print("\tSo you can represent them as\n", .{});
    try writer.print("\t\t1 2 3 4\n", .{});
    try writer.print("\t\t1..4\n", .{});
    try writer.print("\t\t1:3\n", .{});
    try writer.print("\tAll the 3 above id representations are equivalent\n", .{});
    try writer.print("\tThe way the slices are defined are\n", .{});
    try writer.print("\t\tstart..end\n", .{});
    try writer.print("\t\tstart:len\n", .{});
    try writer.print("\tYou can also not specify the len and end for the slices and it will default the end of the nofifications\n", .{});
    try writer.print("\n", .{});
    try writer.print("Examples\n", .{});
    try writer.print("\tA basic example\n", .{});
    try writer.print("\t\tOkBob notify Clean Room\n", .{});
    try writer.print("\tThis sets a notification to remind you to clean your room once a year.\n", .{});
    try writer.print("\tYou probs want to clean it more often than that though\n", .{});
    try writer.print("\t\tOkBob notify Clean Room -i=1W\n", .{});
    try writer.print("\tThis Sets the reminder for every week\n", .{});
    try writer.print("\tA bit more advanced example setting the date and interval\n", .{});
    try writer.print("\t\tOkBob notify Bob's Birthday -t=29/10 -i=1Y\n", .{});
    try writer.print("\tIf you want to see all the active notifications\n", .{});
    try writer.print("\t\tOkBob notify\n", .{});
    try writer.print("\tIf you want to remove a notification\n", .{});
    try writer.print("\tOkBob -notify [id]\n", .{});
    try writer.print("\tWhere the id is the index of the notification\n", .{});
    try writer.print("\tYou can also dismiss multiple items with\n", .{});
    try writer.print("\t\tOkBob -notify [id1] [id2] ! [id3]\n", .{});
    try writer.print("\n", .{});
}
