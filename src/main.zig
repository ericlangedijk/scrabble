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
    var cp_out = UTF8ConsoleOutput.init();
    defer cp_out.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    // var hash = std.StringHashMap(void).init(allocator);
    // defer hash.deinit();
    // try hash.put("hallo", {});
    // try hash.put("goedemorgen", {});

    // std.debug.print("{}\n", .{hash.contains("hallo")});
    // std.debug.print("{}\n", .{hash.contains("goedemorgen")});
    // std.debug.print("{}\n", .{hash.contains("goedemorge")});


    run(allocator) catch |err|
    {
        std.debug.print("\x1b[31mError: {}, Message: {s}\x1b[0m\n", .{err, scrabble.get_last_error()});
    };

    std.debug.print("Program ready. press enter to quit\n", .{});
    try readline();
}

fn run(allocator: std.mem.Allocator)!void
{

    var settings = try Settings.init(allocator, .Dutch);
    defer settings.deinit();
    //var g: gaddag.Graph = try gaddag.load_graph_from_text_file("C:\\Data\\ScrabbleData\\slo.txt", allocator, &settings);
    // try gaddag.save_graph_to_bin_file(&g, "C:\\Data\\ScrabbleData\\nl.bin");
    var g: gaddag.Graph = try gaddag.load_graph_from_bin_file("C:\\Data\\ScrabbleData\\nl.bin", allocator, &settings);
    defer g.deinit();
    try g.validate();

    //std.debug.print("{}\n", .{g.word_exists("virgotočasen")});

    //try test_random_game(allocator, &settings, &g);
    try test_board(allocator, &settings, &g);
}

fn test_random_game(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    var game: tests.RndGame = try tests.RndGame.init(allocator, settings, graph);
    defer game.deinit();
    for (0..100) |_|
    {
        const ok: bool = try game.play(false);
        if (!ok) break;
    }
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
    // const xx: u21 = 'č';
    // std.debug.print("{u}\n\n", .{xx});

    var board: scrabble.Board = scrabble.Board.init(settings);

    // the combi for our default test 45255 moves
    // board.set_string(settings, 112, "zend", .Horizontal);
    // board.set_string(settings, 112, "zag", .Vertical);
    // var rack = try scrabble.Rack.init_string(settings, "talen"); // this
    // rack.blanks = 2;

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
    try board.set_string(settings, 112, "zend", .Horizontal);
    try board.set_string(settings, 112, "zag", .Vertical);

    //try board.set_string(settings, 105, "zend", .Horizontal);
    //try board.set_string(settings, 111, "sta", .Horizontal);
    //try board.set_string(settings, 118, "ie", .Horizontal);
            //zendinstallatie

    //aanbiddelijkste

    utils.printboard(&board);

    var gen = try MovGen.init(allocator, settings, graph, null);
    defer gen.deinit();

    //const ok = gen.do_crosscheck(&board, 116, settings.char_to_code('t'), .Horizontal);
    //std.debug.print("crosscheck {}\n", .{ok});

    //if (true) return;

    //var total: u64 = 0;
    var rack = try scrabble.Rack.init_string(settings, "talen"); // this
    rack.blanks = 2;

    // gen.monolithic_gen(&board, &rack, .Horizontal);
    // if (true) return;

    var timer: std.time.Timer = try std.time.Timer.start();
    //gen.gen_rack_moves(&board, 0, 112, graph.get_rootnode(), rack, scrabble.Move.EMPTY);
    gen.generate_moves(&board, &rack);


    const elapsed = timer.lap();
    //gen.sort();


    var idx: usize = 0;
    for (gen.movelist.items) |*m|
    {
        //if (m.flags.is_crossword_generated and scrabble.square_x(m.anchor) == 11 and !m.flags.is_horizontally_generated and m.letters.len == 7)// and m.letters.len == 4)// and m.flags.is_crossword_generated and m.first().square == 98)
        if (m.letters.len == 1)
        {
            //_ = m;
            //utils.printmove_only(m, settings);
            utils.printmove(&board, m, null);
            idx += 1;
        }
        //if (idx > 20) break;
    }

    var total: u32 = 0;
    for(gen.movelist.items) |move|
    {
        total += move.score;

    }

    std.debug.print("\n\ngenerate {} moves time ms {} {} nanos sum-score {}\n", .{ gen.movelist.items.len, elapsed / 1000000, elapsed, total });
    //std.debug.print("score calc time {} nanos\n", .{movgen.CALC});
    std.debug.print("moves per second {}\n", .{utils.nps(gen.movelist.items.len, elapsed)});
    //std.debug.print("ONEKIPS {}", .{movgen.ONESKIPS});

    //test: dups are produced.
    var dups: usize = 0;
    var map = std.AutoHashMap(std.BoundedArray(scrabble.MoveLetter, 7), void).init(allocator);
    defer map.deinit();
    for(gen.movelist.items) |mov|
    {
        const result = try map.getOrPut(mov.letters);
        if (result.found_existing)
        {
            //utils.printmove(&board, &mov, settings, null);
            utils.printmove_only(&mov, settings);
            //std.debug.print("{}", .{mov.flags.is_crossword_generated});
            dups += 1;
        }
    }
    std.debug.print("dups {} total mapped {}\n", .{dups, map.count()});
}


fn test_slo(allocator: std.mem.Allocator, settings: *const Settings) !void
{

    const xx: u21 = 'č';
    std.debug.print("{}", .{@TypeOf(xx)});

    _ = settings;
    // load text file in memory.
    const file: std.fs.File = try std.fs.openFileAbsolute("C:\\Data\\ScrabbleData\\slotest.txt", .{});
    defer file.close();

    const stat = try file.stat();
    const file_size = stat.size;

    const file_buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_buffer);

    // Read file line by line
    var it = std.mem.splitAny(u8, file_buffer, &.{13, 10});
    while (it.next()) |word|
    {
        if (word.len == 0) continue;
        const view: std.unicode.Utf8View = try std.unicode.Utf8View.init(word);
        var uni = view.iterator();
        while (uni.nextCodepoint()) |u|
        {
            std.debug.print("[{u}]={} / ", .{u ,u});
        }
        std.debug.print("\n", .{});
    }

}

// const std = @import("std");
// const print = std.debug.print;
// const builtin = @import("builtin");

const builtin = @import("builtin");

const UTF8ConsoleOutput = struct
{
    original: ?c_uint = null, // cowboy

    fn init() UTF8ConsoleOutput
    {
        var self = UTF8ConsoleOutput{};
        if (builtin.os.tag == .windows)
        {
            const kernel32 = std.os.windows.kernel32;
            self.original = kernel32.GetConsoleOutputCP();
            _ = kernel32.SetConsoleOutputCP(65001);
        }
        return self;
    }

    fn deinit(self: *UTF8ConsoleOutput) void
    {
        if (self.original) |org|
        {
            _ = std.os.windows.kernel32.SetConsoleOutputCP(org);
        }
    }
};

pub fn krak() !void {
    var cp_out = UTF8ConsoleOutput.init();
    defer cp_out.deinit();

    //print("\u{00a9}", .{});
}

