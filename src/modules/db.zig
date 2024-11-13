const std = @import("std");
const sqlite = @import("sqlite");

var db: sqlite.Db = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    var db_path: [:0]const u8 = "./OkBob.db";
    var db_exists: bool = true;
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

        _ = std.fs.cwd().statFile(sb.items) catch {
            std.debug.print("First Time\n", .{});
            db_exists = false;
        };

        db_path = try sb.toOwnedSliceSentinel(0);
    }

    db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
    });

    if (!db_exists) {
        try setup();
    }
}

fn setup() !void {
    try db.exec("CREATE TABLE reminders (id INTEGER PRIMARY KEY AUTOINCREMENT, isActive BOOLEAN, name TEXT, timeCreated INTEGER)", .{}, .{});
    try db.exec("CREATE TABLE notifications (id INT, isActive BOOLEAN, name TEXT, timeCreated INTEGER, frequency INT)", .{}, .{});
}

pub fn insertReminder(text: []const u8) !void {
    var stmt = try db.prepare("INSERT INTO reminders(isActive, name, timeCreated) VALUES($isActive{bool}, $name{[]const u8}, $timeCreated{i64})");
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .isActive = @as(bool, true),
        .name = text,
        .timeCreated = std.time.timestamp(),
    });
}

pub fn close() void {
    db.deinit();
}
