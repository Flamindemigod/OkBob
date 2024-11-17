const std = @import("std");
const utils = @import("utils.zig");
const modules = @import("modules/mod.zig");
const SubCommands = enum {
    Reminder,
    DismissReminder,
    Notification,
    DismissNotification,
};

pub fn main() !void {
    const page_allocator = std.heap.page_allocator;
    var Aallocator = std.heap.ArenaAllocator.init(page_allocator);
    defer Aallocator.deinit();
    const allocator = Aallocator.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    try modules.db.init(allocator);
    defer modules.db.close();
    _ = args.next();

    var subcommand_map = std.StringHashMap(SubCommands).init(allocator);
    try subcommand_map.put("remind", SubCommands.Reminder);
    try subcommand_map.put("-remind", SubCommands.DismissReminder);
    try subcommand_map.put("notify", SubCommands.Notification);
    try subcommand_map.put("-notify", SubCommands.DismissNotification);

    if (args.next()) |subcommand| {
        const subcommand_lower = try utils.to_lowercase(subcommand, allocator);
        defer allocator.free(subcommand_lower);
        if (subcommand_map.get(subcommand_lower)) |SC| {
            switch (SC) {
                SubCommands.Reminder => try modules.reminders.set(&args, allocator),
                SubCommands.DismissReminder => try modules.reminders.dismiss(&args, allocator),
                SubCommands.Notification => try modules.notifications.set(&args, allocator),
                SubCommands.DismissNotification => try modules.notifications.dismiss(&args, allocator),
            }
        } else {
            std.debug.print("{s} {s} is not a valid subcommand", .{ subcommand, subcommand_lower });
        }
    } else {
        try modules.notifications.generateRemindersFromNotifs(allocator);
        try modules.reminders.get(allocator);
    }
}
