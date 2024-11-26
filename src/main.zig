// https://github.com/dwyl/english-words
// https://raw.githubusercontent.com/andrazjelenc/Slovenian-wordlist/refs/heads/master/wordlist.txt
// https://github.com/raun/Scrabble/blob/master/words.txt

// TODO: check if a gaddag 'min or max path length tricked u5 value' could speed up things
// TODO: make random tester.

const std = @import("std");

const utils = @import("utils.zig");
const tests = @import("tests.zig");

const scrabble = @import("scrabble.zig");
const gaddag = @import("gaddag.zig");
const movgen = @import("movgen.zig");

const Settings = scrabble.Settings;
const Graph = gaddag.Graph;
const Node = gaddag.Node;
const MovGen = movgen.MovGen;

pub fn main() !void
{
    // std.debug.print("\x1b[31mThis is red text\x1b[0m\n", .{}); // Red text
    run() catch |err|
    {
        std.debug.print("\x1b[31mError: {}, Message: {s}\x1b[0m\n", .{err, scrabble.get_last_error()});
    };

    //try test_board(allocator, &settings, &g);

    std.debug.print("Program ready. press enter to quit\n", .{});
    try readline();
}

fn run()!void
{
    // memory
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();
    // settings + graph
    const settings = try Settings.init(.Dutch);
    var g: gaddag.Graph = try gaddag.load_graph_from_text_file("C:\\Data\\ScrabbleData\\nl.txt", allocator, &settings);
    //try gaddag.save_graph_to_file(&g, "C:\\Data\\ScrabbleData\\nltest.bin");
    defer g.deinit();
    try g.validate();
    try test_random_game(allocator, &settings, &g);
    //try test_board(allocator, &settings, &g);
}

fn test_random_game(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    var game: tests.RndGame = try tests.RndGame.init(allocator, settings, graph);
    defer game.deinit();
    try game.play();
}

fn readline() !void
{
    // Wait for the user to press Enter before exiting
    const stdin = std.io.getStdIn().reader();
    //try stdout.print("Press Enter to continue...\n", .{});
    var buffer: [256]u8 = undefined; // Buffer for input
    _ = try stdin.readUntilDelimiter(&buffer, '\n'); // Read until Enter is pressed
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

    var gen = try MovGen.init(allocator, settings, graph, null);
    defer gen.deinit();

    //const ok = gen.do_crosscheck(&board, 116, settings.char_to_code('t'), .Horizontal);
    //std.debug.print("crosscheck {}\n", .{ok});

    //if (true) return;

    //var total: u64 = 0;
    var rack = try scrabble.Rack.init_string(settings, "talen");
    //var rack = scrabble.Rack.init();
    rack.blanks = 2;
    var timer: std.time.Timer = try std.time.Timer.start();
    //gen.gen_rack_moves(&board, 0, 112, graph.get_rootnode(), rack, scrabble.Move.EMPTY);
    gen.generate_moves(&board, &rack);
    const elapsed = timer.lap();
    gen.sort();


    var idx: usize = 0;
    for (gen.movelist.items) |*m|
    {
        //if (m.letters.len == 7)// and m.flags.is_horizontally_generated and m.flags.is_crossword_generated and m.first().square == 98)
        {
            utils.printmove(&board, m, settings, null);
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
    std.debug.print("moves per second {}\n", .{utils.nps(gen.movelist.items.len, elapsed)});
    //std.debug.print("CUTOFFS {}", .{movgen.CUTOFFS});
    //std.debug.print("ONEMOVESKIPS {}", .{movgen.ONESKIPS});

    // tested: no dups are produced.
    // var dups: usize = 0;
    // var map = std.AutoHashMap(std.BoundedArray(scrabble.MoveLetter, 7), void).init(allocator);
    // for(gen.movelist.items) |mov|
    // {
    //     const result = try map.getOrPut(mov.letters);
    //     if (result.found_existing) dups += 1;
    // }
    // std.debug.print("dups {} total mapped {}", .{dups, map.count()});
}

