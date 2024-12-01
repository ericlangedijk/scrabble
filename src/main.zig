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

//const stdout = std.io.getStdOut();

// const Console = struct
// {
//     _out: ?std.io.File,

//     fn stdout() std.io.File
//     {
//         return if (_out) |o| o else std.io.getStdOut();
//     }
// };

fn test_brd(brd: *const scrabble.Brd) void
{
    std.debug.print("{}", .{brd});
}

pub fn main() !void
{
    var cp_out = UTF8ConsoleOutput.init();
    defer cp_out.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();


    //const xx = @sizeOf(scrabble.Board);
    // const xx = @sizeOf(std.mem.Allocator);
    //std.debug.print("size of board {}", .{xx + 225});
    // if (true) return;

    // std.debug.print("\x1b[97;100mWhite Text on Dark Gray Background\x1b[0m\n", .{});
    // std.debug.print("\x1b[97;48;5;234mWhite Text on Darker Gray Background\x1b[0m\n", .{});

    // if (true) return;

    // var settings = try Settings.init(allocator, .Dutch);
    // defer settings.deinit();

    // // var g: gaddag.Graph = try gaddag.load_graph_from_bin_file("C:\\Data\\ScrabbleData\\nl.bin", allocator, &settings);
    // // defer g.deinit();

    // var brd: scrabble.Brd(15, 15) = scrabble.Brd(15, 15).init(&settings);
    // brd.squares[112] = scrabble.Letter.init(1, false);
    // test_brd(&brd);

    // // std.debug.print("{}", .{brd});

    // if (true) return;


    // const stdout = std.io.getStdOut().writer();
    // try stdout.print("HALLO", .{});

    // //std.fmt.formatIntBuf()
    // Console.set_color(.Red);
    // Console.print_test();
    // Console.reset_colors();
    // Console.print_test();

    // if (true) return;




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
    // try test_compression(allocator, &settings, "C:\\Data\\ScrabbleData\\en.txt");
    // if (true) return;
   // var g: gaddag.Graph = try gaddag.load_graph_from_text_file("C:\\Data\\ScrabbleData\\nl.txt", allocator, &settings);
    //try gaddag.save_graph_to_bin_file(&g, "C:\\Data\\ScrabbleData\\nl.bin");
    var g: gaddag.Graph = try gaddag.load_graph_from_bin_file("C:\\Data\\ScrabbleData\\nl.bin", allocator, &settings);
    defer g.deinit();
    try g.validate();

//if (true) return;
    //std.debug.print("{}\n", .{g.word_exists("virgotočasen")});

    //try test_random_game(allocator, &settings, &g);
    try test_board(allocator, &settings, &g);
}

fn test_random_game(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    // std.debug.print("{u}\n", .{'🤮'});
   //std.debug.print("\x1b[43;30m A \x1b[0m\n", .{});
//    std.debug.print("\x1b[43;30m a \x1b[0m\n", .{});

    var game: tests.RndGame = try tests.RndGame.init(allocator, settings, graph, 1);
    defer game.deinit();
    for (0..1) |_|
    {
        const ok: bool = try game.play(true, 1);
        if (!ok) break;
    }
}

fn test_board(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    var board: scrabble.Board = try scrabble.init_default_scrabbleboard(allocator, settings);
    //var board: scrabble.Board = try scrabble.init_custom_scrabbleboard(allocator, settings, 15, 15, @constCast(&scrabble.DEFAULT_WORDFEUD_BWV), @constCast(&scrabble.DEFAULT_WORDFEUD_BLV));
    defer board.deinit();
    var rack = scrabble.Rack.init();
    var gen = try MovGen.init(allocator, settings, graph, null);
    defer gen.deinit();


    //try board.set_string(settings, 105, "zend", .Horizontal);
    //try board.set_string(settings, 111, "sta", .Horizontal);
    //try board.set_string(settings, 118, "ie", .Horizontal);
    //board.set_string(settings, 105, "zendinstallati", .Horizontal);
    //board.set_string(settings, 106, "endinstallati", .Horizontal);
    const case: i32 = 1;
    switch (case)
    {
        -1 =>
        {
            try board.set_string(settings, 112, "e", .Horizontal);
            try rack.set_string(settings, "", 7);
        },
        0 =>
        {
            try rack.set_string(settings, "mlantje", 0);
        },
        1 =>
        {
            try board.set_string(settings, 112, "zend", .Horizontal);
            try board.set_string(settings, 112, "zag", .Vertical);
            try rack.set_string(settings, "talen", 2);
        },
        2 =>
        {
            try board.set_string(settings, 112, "tonaler", .Horizontal);
            try rack.set_string(settings, "lyobeoi", 0);
        },
        3 =>
        {
            try board.set_string(settings, 112, "matjes", .Horizontal);
            try board.set_string(settings, 122, "bepraat", .Horizontal);
            try board.set_string(settings, 78, "noren", .Vertical);
            try board.set_string(settings, 55, "frutjes", .Vertical);
            try board.set_string(settings, 54, "oeh", .Vertical);
            try board.set_string(settings, 116-30, "keen", .Vertical);
            try board.set_string(settings, 117-15, "as", .Vertical);
            try board.set_string(settings, 124, "pofje", .Vertical);
            try rack.set_string(settings, "dlnaien", 0);

        },
        4 =>
        {
            try board.set_string(settings, 107, "omwerk", .Horizontal);
            try board.set_string(settings, 95, "terminal", .Vertical);
            try board.set_string(settings, 212, "koos", .Horizontal);
            try board.set_string(settings, 109+30, "hui", .Vertical);
            try rack.set_string(settings, "nadeden", 0);
        },
        else => {}
    }


    //if (true) return;
    utils.print_board_ex(&board, null, null, null);
   // utils.print_rack(rack, settings);

    var timer: std.time.Timer = try std.time.Timer.start();
    gen.gen_moves(&board, &rack);
    const elapsed = timer.lap();

    gen.sort();
    var idx: usize = 0;
    for (gen.movelist.items) |*m|
    {
        //if (m.flags.is_crossword_generated and scrabble.square_x(m.anchor) == 11 and !m.flags.is_horizontally_generated and m.letters.len == 7)// and m.letters.len == 4)// and m.flags.is_crossword_generated and m.first().square == 98)
        //if (m.letters.len >= 7)//== 7 or m.find(scrabble.square_from(0,10)) != null)
        {
            //_ = m;
            //utils.printmove_only(m, settings);
            utils.print_board_ex(&board, m, &rack, null);
            utils.printmove_only(m, settings);
            idx += 1;
        }
        if (idx > 10) break;
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

    //test if dups are produced.
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


fn test_compression(allocator: std.mem .Allocator, settings: *const Settings, filename: []const u8) !void
{

   // load text file in memory.
    const file: std.fs.File = try std.fs.openFileAbsolute(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const file_size = stat.size;

    const file_buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_buffer);

    var org_size: usize = 0;
    var dst_size: usize = 0;
    var prev: std.BoundedArray(scrabble.CharCode, 32) = .{};
    var counter: usize = 0;

    // Read line by line
    var it = std.mem.splitAny(u8, file_buffer, &.{13, 10}); // TODO: make a byte + unicode version depending on settings.
    while (it.next()) |word|
    {
        if (word.len == 0) continue; // skip empty (split any is a bit strange)
        const curr: std.BoundedArray(scrabble.CharCode, 32) = try settings.encode_word(word);
        const eql: usize = std.mem.indexOfDiff(scrabble.CharCode, prev.slice(), curr.slice()) orelse curr.len;
        //std.debug.print("[{u}] -> [{u}] sql = {}\n", .{settings.decode_word(prev.slice()).slice(), settings.decode_word(curr.slice()).slice(), eql});
        org_size += curr.len;
        dst_size += curr.len - eql + 1;
        prev = curr;
        counter += 1;
        //if (counter > 20) break;
    }

    std.debug.print("org_size {}\n", .{org_size});
    std.debug.print("dst_size {} -> {}\n", .{dst_size, (dst_size * 5) / 8});
}


// const std = @import("std");
// const print = std.debug.print;
// const builtin = @import("builtin");

const builtin = @import("builtin");

const UTF8ConsoleOutput = struct
{
    original: ?c_uint = null,

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

fn readline() !void
{
    // Wait for the user to press Enter before exiting
    const stdin = std.io.getStdIn().reader();
    //try stdout.print("Press Enter to continue...\n", .{});
    var buffer: [256]u8 = undefined; // Buffer for input
    _ = try stdin.readUntilDelimiter(&buffer, '\n'); // Read until Enter is pressed
}

