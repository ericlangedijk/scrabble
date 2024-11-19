const std = @import("std");

const utils = @import("utils.zig");

const scrabble = @import("scrabble.zig");
const gaddag = @import("gaddag.zig");
const movgen = @import("movgen.zig");

const Settings = scrabble.Settings;
const Graph = gaddag.Graph;
const Node = gaddag.Node;

//const Board = scrabble.Board;

pub fn main() !void
{

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    // std.debug.print("size of moveletter {}\n", .{@sizeOf(scrabble.MoveLetter)});
    // std.debug.print("size of move {}\n", .{@sizeOf(scrabble.Move)});
    // std.debug.print("size of node {}\n", .{@sizeOf(gaddag.Node)});
    //std.debug.print("size of charcodemask {}\n", .{@sizeOf(scrabble.CharCodeMask)});

    const settings = try Settings.init(.Dutch);
    var timer: std.time.Timer = try std.time.Timer.start();
    var g: gaddag.Graph = try gaddag.load_graph_from_text_file("C:\\Data\\ScrabbleData\\nltest.txt", allocator, &settings);
    defer g.deinit();
    const elapsed = timer.lap();
    try g.validate();
    std.debug.print("loading time ms {}\n", .{ elapsed / 1000000 });
    std.debug.print("nodes len {}\n", .{g.nodes.items.len});
    //std.debug.print("nodecount {}\n", .{g.node_count});
    //std.debug.print("wasted {}\n", .{g.wasted});
    //utils.printline("check out memory usage graph now");
    //try gaddag.save_graph_to_file(&g, "C:\\Data\\ScrabbleData\\nl.bin");
    //std.debug.print("{any}\n", .{g.rootnode()});
    //try readline();

    try test_board(allocator, &settings, &g);


    try readline();
}


fn test_board(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    const MovGen = movgen.MovGen;

    var board: scrabble.Board = scrabble.Board.init(settings);

    if (false)
    {
        board.set(108, 't');
        board.set(109, 'a');
        board.set(110, 'f');
        //board.set(115, 'h');
        board.set(112, 'l');
        //board.set(113, 'l');
    }

    var gen = try MovGen.init(allocator, settings, graph);
    defer gen.deinit();


    // if (graph.find_word("tafel")) |w|
    // {
    //     std.debug.print("{any}", .{w});
    // }

    gen.preprocess(&board);

    const rack = try scrabble.Rack.init_string(settings, "tafel");
    //rack.blanks = 1;

    gen.gen_rack_moves(&board, 0, 112, graph.get_rootnode(), rack, scrabble.Move.EMPTY);

    // for (gen.square_cache) |info|
    // {
    //     std.debug.print("{any}\n", .{info});
    // }

    // const node = graph.find_raw(&.{5});
    // if (node) |n|
    // {
    //     const ch = graph.get_children(n);
    //     for (ch) |c|
    //     {
    //         std.debug.print("c={c}, ", .{settings.code_to_char(c.data.code)});
    //     }
    // }
    // var node = graph.find_node(graph.rootnode(), 5);
    // if (node) |n| node = graph.find_node(n, 6);
    //std.debug.print("{any}\n", .{node == null});

     const ok: bool = gen.do_crosscheck(&board, &gen.square_cache[111], 5, .Vertical);
     std.debug.print("crosscheck {}\n", .{ok});
     std.debug.print("DONE\n", .{});
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
