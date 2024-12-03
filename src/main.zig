// https://github.com/dwyl/english-words
// https://raw.githubusercontent.com/andrazjelenc/Slovenian-wordlist/refs/heads/master/wordlist.txt
// https://github.com/raun/Scrabble/blob/master/words.txt


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
    var cp_out = UTF8ConsoleOutput.init(); // temp solution.
    defer cp_out.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    var settings = try Settings.init(allocator, .Dutch);
    defer settings.deinit();

    // if (true) return;
    // var g: gaddag.Graph = try gaddag.load_graph_from_text_file("C:\\Data\\ScrabbleData\\nl.txt", allocator, &settings);
    // try gaddag.save_graph_to_bin_file(&g, "C:\\Data\\ScrabbleData\\nl.bin");
    var g: gaddag.Graph = try gaddag.load_graph_from_bin_file("C:\\Data\\ScrabbleData\\nl.bin", allocator, &settings);
    defer g.deinit();
    try g.validate();

    //try test_random_game(allocator, &settings, &g);
    try tests.test_some_boards(allocator, &settings, &g);

    std.debug.print("Program ready. press enter to quit\n", .{});
    try readline();
}

fn test_random_games(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    var game: tests.RndGame = try tests.RndGame.init(allocator, settings, graph, 1);
    defer game.deinit();
    for (0..1) |_|
    {
        const ok: bool = try game.play(true, 1);
        if (!ok) break;
    }
}

const UTF8ConsoleOutput = struct
{
    const builtin = @import("builtin");

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

fn readline() !void
{
    const stdin = std.io.getStdIn().reader();
    var buffer: [256]u8 = undefined;
    _ = try stdin.readUntilDelimiter(&buffer, '\n');
}

