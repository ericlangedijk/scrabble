const std = @import("std");

/// For now we only use this one to read text files.\
/// For the rest we avoid unicode now.
pub fn unicode_iterator(string: []const u8) !std.unicode.Utf8Iterator
{
    const view: std.unicode.Utf8View = try std.unicode.Utf8View.init(string);
    return view.iterator();
}

pub fn printline(string: []const u8) void
{
    std.debug.print("{s}\n", .{ string });
}
