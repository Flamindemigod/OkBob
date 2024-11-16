const std = @import("std");
const utils = @import("../utils.zig");
const db = @import("db.zig");
const zdt = @import("zdt");

const NOTIFICATION = struct {
    id: usize,
    name: []const u8,
    timeCreated: i64,
    timeNext: i64,
    timeInterval: []const u8,

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

    fn print(self: *const NOTIFICATION, allocator: std.mem.Allocator, display_idx: usize) void {
        std.log.info("Notification {d}:\n\t{s}\n\t{s}\n\tEvery: {s}\n", .{ display_idx, self.name, utils.parse_timestamp(allocator, self.timeNext) catch "Could not parse Timestamp", self.timeInterval });
    }
};

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

//TODO: Might be worth moving this and its sister function in reminders to utils
fn note_insert_from_builder(allocator: std.mem.Allocator, builder: *std.ArrayList([]const u8), note: *std.ArrayList(NOTIFICATION), timeStart: *i64, interval: *zdt.Duration.RelativeDelta, intervalString: []const u8) !void {
    if (builder.items.len > 0) {
        const timeStartDateTime = try zdt.Datetime.fromUnix(@intCast(timeStart.*), .second, null);
        const t = try timeStartDateTime.addRelative(interval.*);
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
    var interval = zdt.Duration.RelativeDelta{ .years = 1 };
    var intervalString: []const u8 = "1Y";
    var timeStart = std.time.timestamp();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "!")) {
            try note_insert_from_builder(allocator, &note_builder, &notes, &timeStart, &interval, intervalString);
            continue;
        } else if (std.mem.eql(u8, arg[0..3], "-t=")) {
            timeStart = try utils.parse_to_timestamp(allocator, arg[3..]);
            continue;
        } else if (std.mem.eql(u8, arg[0..3], "-i=")) {
            intervalString = arg[3..];
            interval = try utils.parse_durations(arg[3..]);
            continue;
        }
        try note_builder.append(arg);
    }
    try note_insert_from_builder(allocator, &note_builder, &notes, &timeStart, &interval, intervalString);
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
