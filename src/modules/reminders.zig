const std = @import("std");
const utils = @import("../utils.zig");

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
            const joined_string = try utils.string_join(note_builder, " ", allocator);
            try notes.append(joined_string);
            note_builder.items.len = 0;
            continue;
        }
        try note_builder.append(arg);
    }
    const joined_string = try utils.string_join(note_builder, " ", allocator);
    try notes.append(joined_string);
    std.debug.print("In Reminders {s}\n", .{notes.items});
}
