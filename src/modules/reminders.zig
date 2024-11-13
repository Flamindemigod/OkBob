const std = @import("std");
const utils = @import("../utils.zig");
const db = @import("db.zig");

const REMINDER = struct {
    id: usize,
    name: []const u8,
    timeCreated: i64,

    fn print(self: *const REMINDER, display_idx: usize) void {
        std.log.debug("Reminder {d}:\n\t{s}\n\t {d}\n", .{ display_idx, self.name, self.timeCreated });
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
    std.debug.print("In Reminders {s}\n", .{notes.items});
}

pub fn get(allocator: std.mem.Allocator) !void {
    const note_list = try fetch(allocator);
    for (note_list.items, 0..) |note, display_idx| {
        note.print(display_idx);
    }
}
