const std = @import("std");

const scrabble = @import("scrabble.zig");
const gaddag = @import("gaddag.zig");

const InitialNode = gaddag.Node;
const Gaddag = gaddag.Gaddag;

pub fn main() !void
{

    //std.debug.print("{any}", .{ scrabble.DutchDef });

    var g: Gaddag = try Gaddag.init();
    defer g.deinit();
    try g.load_from_file("C:\\Data\\ScrabbleData\\nltest.txt");

    //try g.load_example();


    // var n = try InitialNode.init(12);
    // defer n.deinit();

    // n.print();
    // try n.add_child(24);
    // n.print();
    // try n.add_child(31);
    // n.print();
    // try n.add_child(27);
    // n.print();
    // try n.add_child(14);
    // n.print();
    // try n.add_child(28);
    // try n.add_child(1);
    // n.print();


    //std.debug.print("{any}\n", .{ n });

    // // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
