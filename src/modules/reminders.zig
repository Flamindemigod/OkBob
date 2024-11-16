const std = @import("std");
const utils = @import("../utils.zig");
const db = @import("db.zig");

const REMINDER = struct {
    id: usize,
    name: []const u8,
    timeCreated: i64,

    fn dismiss(self: *REMINDER) !void {
        var stmt = try db.db.prepare("UPDATE reminders SET isActive = 0 WHERE id = $id{usize}");
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .id = self.id,
        });
    }

    fn print(self: *const REMINDER, allocator: std.mem.Allocator, display_idx: usize) void {
        std.log.info("Reminder {d}:\n\t{s}\n\t{s}\n", .{ display_idx, self.name, utils.parse_timestamp(allocator, self.timeCreated) catch "Could not parse Timestamp" });
    }
};

fn insert(text: []const u8) !void {
    var stmt = try db.db.prepare("INSERT INTO reminders(isActive, name, timeCreated) VALUES($isActive{bool}, $name{[]const u8}, $timeCreated{i64})");
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .isActive = @as(bool, true),
        .name = text,
        .timeCreated = std.time.timestamp(),
    });
}

fn fetch(allocator: std.mem.Allocator) !std.ArrayListUnmanaged(REMINDER) {
    var note_list = std.ArrayListUnmanaged(REMINDER){};
    var stmt = try db.db.prepare("SELECT id, name, timeCreated FROM reminders where isActive = 1");
    defer stmt.deinit();

    var iter = try stmt.iterator(REMINDER, .{});
    while (try iter.nextAlloc(allocator, .{})) |vals| {
        try note_list.append(allocator, @as(REMINDER, vals));
    }
    return note_list;
}

fn note_insert_from_builder(allocator: std.mem.Allocator, comptime T: type, builder: *std.ArrayList(T), note: *std.ArrayList(T)) !void {
    if (builder.items.len > 0) {
        const joined_string = try utils.string_join(builder.*, " ", allocator);
        try note.append(joined_string);
        builder.items.len = 0;
    }
}

//NOTE: Setting Reminders should be of format
// `OkBob remind Buy Milk`
// Where the reminder text is "Buy Milk"
//Though that gets fairly inconvient when
//needing to add multiple reminders at once.
//So perhaps having the interface be
// `OkBob remind "Buy Milk" "Buy Cookies" "Buy Ramen"`
//this however requires each argument to be encased in quoutes
//which is fairly inconvient in and of itself.
//Whereas the first formatting option doesnt have that issue
//as you can read till the end of the supplied arguments
//and build it into a single string
//Another option exists where you supply a delimtter within your arugments
// `OkBob remind buy milk ! buy cookies ! buy ramen`
//This might be the best long term solution because it removes the need for
//quotes. though im pretty sure the delimtter must be choosen carefully as
//to not collide with bash and need to be escaped
pub fn set(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
    var note_builder = std.ArrayList([]const u8).init(allocator);
    defer note_builder.deinit();
    var notes = std.ArrayList([]const u8).init(allocator);
    defer notes.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "!")) {
            try note_insert_from_builder(allocator, []const u8, &note_builder, &notes);
            continue;
        }
        try note_builder.append(arg);
    }
    try note_insert_from_builder(allocator, []const u8, &note_builder, &notes);
    for (notes.items) |note| {
        try insert(note);
    }
}

pub fn get(allocator: std.mem.Allocator) !void {
    const note_list = try fetch(allocator);
    for (note_list.items, 0..) |note, display_idx| {
        note.print(allocator, display_idx);
    }
}

//NOTE: Dismissing Reminders should be of format
// `OkBob -remind {idx}`
// Where the idx is the display index that gets listed by the normal
//Though that gets fairly inconvient when
//needing to dismiss multiple reminders at once.
//So to dismiss reminders we can use
//`OkBob -remind 0 ! 2 ! 5`
//While we could just split them by spaces as indexes would never have spaces within them.
//I prefer having it split by ! for consistency with other interfaces
//So i'll also support just spliting by spaces as well
//`OkBob -remind 0 ! 2 5`
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
            std.log.err("{any} is not within the index bounds of the active reminders\n", .{parsedIdx.items});
        }
    }
    std.log.info("Removing the following reminders", .{});
    for (dismissQueue.items) |idx| {
        note_list.items[idx].print(allocator, idx);
        try note_list.items[idx].dismiss();
    }
}
