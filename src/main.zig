const std = @import("std");

const utils = @import("utils.zig");

const scrabble = @import("scrabble.zig");
const gaddag = @import("gaddag.zig");

const Settings = scrabble.Settings;
const Graph = gaddag.Graph;
const Node = gaddag.Node;

pub fn main() !void
{

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

      const settings = try Settings.init(.Dutch);

    // new graph
    {
        var timer: std.time.Timer = try std.time.Timer.start();
        var g: gaddag.Graph = try gaddag.load_graph_from_text_file("C:\\Data\\ScrabbleData\\nl.txt", allocator, &settings);
        const elapsed = timer.lap();
        try g.validate();
        std.debug.print("loading time ms {}\n", .{ elapsed / 1000000 });
        std.debug.print("nodes len {}\n", .{g.nodes.items.len});
        std.debug.print("nodecount {}\n", .{g.node_count});
        std.debug.print("wasted {}\n", .{g.wasted});
        utils.printline("check out memory usage graph now");
        try readline();
        defer g.deinit();
    }

    try readline();


}


fn readline() !void
{
    // Wait for the user to press Enter before exiting
    const stdin = std.io.getStdIn().reader();
    //try stdout.print("Press Enter to continue...\n", .{});
    var buffer: [256]u8 = undefined; // Buffer for input
    _ = try stdin.readUntilDelimiter(&buffer, '\n'); // Read until Enter is pressed
}

// the old deleted gaddag
// separate block to debug memory leaks
    // {
    //     var g: Gaddag = try Gaddag.init(allocator, &settings);
    //     defer g.deinit();
    //     var timer: std.time.Timer = try std.time.Timer.start();
    //     try g.load_from_file("C:\\Data\\ScrabbleData\\en.txt");
    //     const elapsed = timer.lap();
    //     std.debug.print("loading time ms {}\n", .{ elapsed / 1000000 });
    //     std.debug.print("nr of nodes {} words {}\n", .{g.node_count, g.word_count});
    //     //std.debug.print("MAX CHILDREN {}\n", .{ gaddag.MAX_CHILDREN });


    //     //const node: ?*Node = g.find_node("boterha");
    //     if (g.find_node("appel")) |node|
    //     {
    //         std.debug.print("FOUND {} bow={} eow={} whole={}\n", .{node.data.code, node.is_bow(), node.is_eow(), node.is_whole()});
    //     }
    //     else
    //     {
    //         utils.printline("NOT FOUND");
    //     }
    //     utils.printline("check out memory usage gaddag now");
    //     try readline();
    // }

    //utils.printline("press enter to finish program");
    //try readline();