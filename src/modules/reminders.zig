const std = @import("std");
const utils = @import("../utils.zig");
const dt = @import("datetime.zig");
const db = @import("db.zig");

pub const REMINDER = struct {
    id: usize,
    name: []const u8,
    timeCreated: i64,

    pub fn insert(self: *const REMINDER) !void {
        var stmt = try db.db.prepare("INSERT INTO reminders(isActive, name, timeCreated) VALUES($isActive{bool}, $name{[]const u8}, $timeCreated{i64})");
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .isActive = @as(bool, true),
            .name = self.name,
            .timeCreated = self.timeCreated,
        });
    }
    fn dismiss(self: *REMINDER) !void {
        var stmt = try db.db.prepare("UPDATE reminders SET isActive = 0 WHERE id = $id{usize}");
        defer stmt.deinit();

        try stmt.exec(.{}, .{
            .id = self.id,
        });
    }

    fn format_name(self: *const REMINDER, allocator: std.mem.Allocator, leadingSpaces: []const u8) !std.ArrayList([]const u8) {
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

    fn print(self: *const REMINDER, allocator: std.mem.Allocator, display_idx: usize) void {
        const writer = std.io.getStdOut().writer();
        const leadingSpaces = "    ";
        writer.print("Reminder {d}\n", .{display_idx}) catch std.log.err("Failed to print to stdout", .{});
        const formatted_strings = self.format_name(allocator, leadingSpaces) catch return;
        for (formatted_strings.items) |str| {
            writer.print("{s}\n", .{str}) catch std.log.err("Failed to print to stdout", .{});
        }
        writer.print("{s}\n\n", .{dt.parse_timestamp(allocator, self.timeCreated) catch "Could not parse Timestamp"}) catch std.log.err("Failed to print to stdout", .{});
    }
};

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

fn note_insert_from_builder(allocator: std.mem.Allocator, builder: *std.ArrayList([]const u8), note: *std.ArrayList(REMINDER)) !void {
    if (builder.items.len > 0) {
        const joined_string = try utils.string_join(builder.*, " ", allocator);
        try note.append(REMINDER{ .name = joined_string, .timeCreated = std.time.timestamp(), .id = 0 });
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
    var notes = std.ArrayList(REMINDER).init(allocator);
    defer notes.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "!")) {
            try note_insert_from_builder(allocator, &note_builder, &notes);
            continue;
        }
        try note_builder.append(arg);
    }
    try note_insert_from_builder(allocator, &note_builder, &notes);
    for (notes.items) |note| {
        try note.insert();
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
