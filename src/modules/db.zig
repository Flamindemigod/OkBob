const std = @import("std");
const sqlite = @import("sqlite");

pub var db: sqlite.Db = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    var db_path: [:0]const u8 = "./OkBob.db";
    {
        var sb = std.ArrayList(u8).init(allocator);
        defer sb.deinit();
        //Connecting to db
        const home_path = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home_path);

        try sb.appendSlice(home_path);
        try sb.appendSlice("/.OkBob");

        _ = std.fs.cwd().makeDir(sb.items) catch null;
        try sb.appendSlice("/OkBob.db");

        db_path = try sb.toOwnedSliceSentinel(0);
    }

    db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
    });
    try setup();
}

fn setup() !void {
    try db.exec("CREATE TABLE IF NOT EXISTS reminders (id INTEGER PRIMARY KEY AUTOINCREMENT, isActive BOOLEAN, name TEXT, timeCreated INTEGER)", .{}, .{});
    try db.exec("CREATE TABLE IF NOT EXISTS notifications (id INTEGER PRIMARY KEY AUTOINCREMENT, isActive BOOLEAN, name TEXT, timeCreated INTEGER, timeNext INTEGER, timeInterval TEXT)", .{}, .{});
}

pub fn close() void {
    db.deinit();
}
