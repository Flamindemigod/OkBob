const std = @import("std");
pub fn to_lowercase(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result: []u8 = try allocator.alloc(u8, input.len);

    // Iterate through each character and convert it to lowercase
    for (input, 0..) |ch, i| {
        result[i] = std.ascii.toLower(ch);
    }

    return result;
}

pub fn string_join(input: std.ArrayList([]const u8), sep: []const u8, allocator: std.mem.Allocator) ![]u8 {
    //Calulate the size of the resulting string
    var total_len: usize = 0;
    for (input.items, 1..) |item, i| {
        total_len += item.len;
        if (i < input.items.len) {
            total_len += sep.len;
        }
    }

    //Allocate memory for the result
    var result = try allocator.alloc(u8, total_len);

    var cursor: usize = 0;
    for (input.items, 1..) |item, i| {
        std.mem.copyForwards(u8, result[cursor..], item);
        cursor += item.len;

        if (i < input.items.len) {
            std.mem.copyForwards(u8, result[cursor..], sep);
            cursor += sep.len;
        }
    }
    return result;
}
