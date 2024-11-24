// https://github.com/dwyl/english-words
// https://raw.githubusercontent.com/andrazjelenc/Slovenian-wordlist/refs/heads/master/wordlist.txt
// https://github.com/raun/Scrabble/blob/master/words.txt

// TODO: check if a gaddag 'min or max path length tricked u5 value' could speed up things
// TODO: make random tester.

const std = @import("std");

const utils = @import("utils.zig");

const scrabble = @import("scrabble.zig");
const gaddag = @import("gaddag.zig");
const movgen = @import("movgen.zig");

const Settings = scrabble.Settings;
const Graph = gaddag.Graph;
const Node = gaddag.Node;
const MovGen = movgen.MovGen;

pub fn main() !void
{

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    // std.debug.print("size of State {}\n", .{@sizeOf(movgen.State)});
    //std.debug.print("size of Node {}\n", .{@sizeOf(Node)});
    //std.debug.print("size of Node3 {}\n", .{@sizeOf(gaddag.Node3)});
    //if (true) return;
    // std.debug.print("size of Move {}\n", .{@sizeOf(scrabble.Move)});
    // std.debug.print("size of Rack {}\n", .{@sizeOf(scrabble.Rack)});
    // std.debug.print("size of Letter {}\n", .{@sizeOf(scrabble.Letter)});
    // std.debug.print("size of Path {}\n", .{@sizeOf(movgen.Path)});
    // std.debug.print("size of SquareInfo {}\n", .{@sizeOf(movgen.SquareInfo)});
    //try printcolored();
    const settings = try Settings.init(.Dutch);
    var timer: std.time.Timer = try std.time.Timer.start();
    var g: gaddag.Graph = try gaddag.load_graph_from_text_file("C:\\Data\\ScrabbleData\\nl.txt", allocator, &settings);
    defer g.deinit();
    const elapsed = timer.lap();
    std.debug.print("loading time ms {}\n", .{ elapsed / 1000000 });
    std.debug.print("nodes len {}\n", .{g.nodes.items.len});
    try g.validate();



    // const a: *Node = g.get_rootnode_ptr();// find_node(g.get_rootnode_ptr(), 20) orelse return;

    // // const children = g.get_children(a);
    // // for (children) |child|
    // // {
    // //     std.debug.print("{c}", .{settings.code_to_char(child.data.code)});
    // // }

    // const b = g.find_node_ptr(a, 20);
    // const c = g.find_node_ptr_by_mask(a, 20);

    // // const b = g.find_node_ptr_by_mask(g.get_rootnode_ptr(), 20);

    // std.debug.print("{any}\n", .{b});
    // std.debug.print("{any}\n", .{c});

    //if(true) return;

    try test_board(allocator, &settings, &g);
    try readline();

}


fn test_board(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    //const MovGen = movgen.MovGen;

    var board: scrabble.Board = scrabble.Board.init(settings);

    if (true)
    {
    //    board.set(112, 'd');
        //board.set(113, 'e');
        //board.set(114, 'n');
        //board.set(115, 'd');
        //board.set(113, 'l');
    }
    //board.set_string(settings, 105, "zendinstallati", .Horizontal);
    //board.set_string(settings, 106, "endinstallati", .Horizontal);
    board.set_string(settings, 112, "zend", .Horizontal);
    board.set_string(settings, 112, "zag", .Vertical);
            //zendinstallatie

    utils.printboard(&board, settings);

    var gen = try MovGen.init(allocator, settings, graph);
    defer gen.deinit();

    //const ok = gen.do_crosscheck(&board, 116, settings.char_to_code('t'), .Horizontal);
    //std.debug.print("crosscheck {}\n", .{ok});

    //if (true) return;

    var rack = try scrabble.Rack.init_string(settings, "talen");
    //var rack = scrabble.Rack.init();
    rack.blanks = 2;
    var timer: std.time.Timer = try std.time.Timer.start();

    //gen.gen_rack_moves(&board, 0, 112, graph.get_rootnode(), rack, scrabble.Move.EMPTY);
    gen.generate_moves(&board, rack);
    gen.sort();

    const elapsed = timer.lap();

    var idx: usize = 0;
    for (gen.movelist.items) |*m|
    {
        //if (m.letters.len == 7)// and m.flags.is_horizontally_generated and m.flags.is_crossword_generated and m.first().square == 98)
        {
            utils.printmove(&board, m, settings);
            idx += 1;
        }
        if (idx > 20) break;
    }

    var total: u32 = 0;
    for(gen.movelist.items) |move|
    {
        total += move.score;

    }

    std.debug.print("\n\ngenerate {} moves time ms {} {} nanos sum-score {}\n", .{ gen.movelist.items.len, elapsed / 1000000, elapsed, total });
    std.debug.print("moves per second {}", .{utils.nps(gen.movelist.items.len, elapsed)});
    //std.debug.print("CUTOFFS {}", .{movgen.CUTOFFS});
    //std.debug.print("ONEMOVESKIPS {}", .{movgen.ONESKIPS});

    // var dups: usize = 0;
    // var map = std.AutoHashMap(std.BoundedArray(scrabble.MoveLetter, 7), void).init(allocator);
    // for(gen.movelist.items) |mov|
    // {
    //     const result = try map.getOrPut(mov.letters);
    //     if (result.found_existing) dups += 1;
    // }
    // std.debug.print("dups {} total mapped {}", .{dups, map.count()});
}

fn printcolored() !void
{

    std.debug.print("\x1b[31mThis is red text\x1b[0m\n", .{}); // Red text
    std.debug.print("\x1b[32mThis is green text\x1b[0m\n", .{}); // Green text
    std.debug.print("\x1b[34mThis is blue text\x1b[0m\n", .{}); // Blue text
}

// const stdout = std.io.getStdOut().writer();
//     try stdout.print("\x1b[31mThis is red text\x1b[0m\n", .{}); // Prints red text
//     try stdout.print("\x1b[32mThis is green text\x1b[0m\n", .{}); // Prints green text
//     try stdout.print("\x1b[33mThis is yellow text\x1b[0m\n", .{}); // Prints yellow text

fn readline() !void
{
    // Wait for the user to press Enter before exiting
    const stdin = std.io.getStdIn().reader();
    //try stdout.print("Press Enter to continue...\n", .{});
    var buffer: [256]u8 = undefined; // Buffer for input
    _ = try stdin.readUntilDelimiter(&buffer, '\n'); // Read until Enter is pressed
}



    // std.debug.print("bytes used {}\n", .{g.as_bytes().len}); // 78.813.918       78813918
    // try readline();
    // g.debug_find_word("hallo");
    // if (true) return;
    //var g: gaddag.Graph = try gaddag.load_debug_graph(allocator, &settings);

    // for (g.nodes.items[0..30], 0..) |n, i|
    // {
    //     std.debug.print("#{} code={} bow {} eow {} whole {} childcount {} child_ptr {}\n", .{i, n.data.code, n.data.is_bow, n.data.is_eow, n.data.is_whole_word, n.count, n.child_ptr});
    // }

    // for (g.nodes.items) |n|
    // {
    //     if (n.data.code > 26)
    //     {
    //         std.debug.print("KRAK", .{});
    //         break;
    //     }
    // }
    // try gaddag.save_graph_to_file(&g, "C:\\Data\\ScrabbleData\\nl.bin");


    // const children = g.get_children(g.get_rootnode());
    // std.debug.print("{} {}\n", .{g.get_rootnode().count, g.get_rootnode().child_ptr});
    // for(children) |c|
    // {
    //     std.debug.print("{}/", .{c.data.code});
    // }

    // if (true) return;