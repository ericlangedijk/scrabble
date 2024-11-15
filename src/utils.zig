const std = @import("std");

pub fn str_iterator(string: []const u8) !std.unicode.Utf8Iterator
{
    const view: std.unicode.Utf8View = try std.unicode.Utf8View.init(string);
    return view.iterator();
}

// pub fn get_chars(string: []const u8)
// {

// }