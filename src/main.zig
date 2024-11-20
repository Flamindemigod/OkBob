const std = @import("std");
const utils = @import("utils.zig");
const modules = @import("modules/mod.zig");
const termSize = @import("termSize");
const SubCommands = enum {
    Reminder,
    DismissReminder,
    Notification,
    DismissNotification,
    Help,
};

pub var WINDOW: termSize.TermSize = undefined;
pub fn main() !void {
    WINDOW = try termSize.termSize(std.io.getStdOut()) orelse termSize.TermSize{ .width = 160, .height = 90 };
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
    try subcommand_map.put("help", SubCommands.Help);
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
                SubCommands.Help => {
                    try modules.reminders.printHelpText();
                    try modules.notifications.printHelpText();
                },
            }
        } else {
            const writer = std.io.getStdErr().writer();
            try writer.print("{s} is not a valid subcommand\n", .{subcommand});
            try writer.print("The Valid Subcommands are\n", .{});
            try writer.print("remind\n", .{});
            try writer.print("\tSets a reminder\n", .{});
            try writer.print("-remind\n", .{});
            try writer.print("\tRemoves a reminder\n", .{});
            try writer.print("notify\n", .{});
            try writer.print("\tSets a Notification\n", .{});
            try writer.print("-notify\n", .{});
            try writer.print("\tRemoves a Notification\n", .{});
            try writer.print("help\n", .{});
            try writer.print("\tPrints Help for Reminder and Notification Subcommands\n", .{});
        }
    } else {
        try modules.notifications.generateRemindersFromNotifs(allocator);
        try modules.reminders.get(allocator);
    }
}
