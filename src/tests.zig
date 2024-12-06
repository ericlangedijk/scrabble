const std = @import("std");

const utils = @import("utils.zig");
const rnd = @import("rnd.zig");
const Random = rnd.Random;

const scrabble = @import("scrabble.zig");
const Settings = scrabble.Settings;
const Letter = scrabble.Letter;
const Bag = scrabble.Bag;
const Board = scrabble.Board;
const Rack = scrabble.Rack;
const Move = scrabble.Move;


const gaddag = @import("gaddag.zig");
const Graph = gaddag.Graph;
const Node = gaddag.Node;

const movgen = @import("movgen.zig");
const MovGen = movgen.MovGen;

const MoveHashMap = std.AutoHashMap(std.BoundedArray(scrabble.MoveLetter, 7), void);


pub fn test_some_board(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    //var board: scrabble.Board = try scrabble.init_default_scrabbleboard(allocator, settings);
    var board: scrabble.Board = try scrabble.init_custom_scrabbleboard(allocator, settings, 15, 15, @constCast(&scrabble.DEFAULT_WORDFEUD_BWV), @constCast(&scrabble.DEFAULT_WORDFEUD_BLV));
    defer board.deinit();

    var rack = scrabble.Rack.EMPTY;

    var gen = try MovGen.init(allocator, settings, graph, null);
    defer gen.deinit();

    // setup some board and rack with a fair amount of possibile moves (almost 100.000)
    try board.set_string(settings, 112, "vase", .Horizontal);
    try board.set_string(settings, 112, "vowel", .Vertical);
    try board.set_string(settings, 115 - 30, "one", .Vertical);
    try rack.set_string(settings, "eseat", 2); // 2 blanks

    utils.print_board_ex(&board, null, null, null);

    var timer: std.time.Timer = try std.time.Timer.start();
    gen.gen_moves(&board, &rack);
    const elapsed = timer.lap();

    gen.sort_moves();

    // print the 20 higest scoring moves.
    var idx: usize = 0;
    for (gen.movelist.items) |*m|
    {
        utils.print_board_ex(&board, m, &rack, null);
        idx += 1;
        if (idx > 20) break;
    }

    var total: u32 = 0;
    for(gen.movelist.items) |move|
    {
        total += move.score;
    }

    std.debug.print("\n\ngenerate {} moves time ms {} {} nanos sum-score {}\n", .{ gen.movelist.items.len, elapsed / 1000000, elapsed, total });
    std.debug.print("moves per second {}\n", .{utils.nps(gen.movelist.items.len, elapsed)});
}

var bestmove: Move = Move.EMPTY; // global var for now, because I do not know how to program a context function in zig.

pub const RndGame = struct
{
    allocator: std.mem.Allocator,
    settings: *const Settings,
    graph: *const Graph,
    rnd: Random,
    gen: MovGen,
    bag: Bag,
    board: Board,
    rack: Rack,
    hash: MoveHashMap,

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings, graph: *const Graph, seed: ?u64) !RndGame
    {
        return RndGame
        {
            .allocator = allocator,
            .settings = settings,
            .graph = graph,
            .rnd = if (seed) |s| Random.init(s) else Random.init_randomized(),
            .gen = try MovGen.init(allocator, settings, graph, move_event),
            .bag = Bag.init(settings),
            .board = try scrabble.init_default_scrabbleboard(allocator, settings),
            .rack = Rack.EMPTY,
            .hash = MoveHashMap.init(allocator),
        };
    }

    pub fn deinit(self: *RndGame) void
    {
        self.board.deinit();
        self.gen.deinit();
        self.hash.deinit();
    }

    pub fn move_event(move: *const Move) void
    {
        if (move.score > bestmove.score)
        {
            bestmove = move.*;
        }
    }

    /// Play a random game, taking the highest scoring move each time.
    pub fn play(self: *RndGame, comptime display: bool, new_seed: ?u64) !void
    {
        if (new_seed) |s| self.rnd.reset_seed(s);
        std.debug.print("seed: {}", .{self.rnd.seed});
        self.board.clear();
        self.bag.reset(self.settings);
        self.rack.clear();
        var total_moves: usize = 0;
        var total_time: u64 = 0;
        var gen_time: u64 = 0;
        var total_score: u32 = 0;
        var moves_played: u32 = 0;
        while (true)
        {
            bestmove = Move.EMPTY;
            const picked: bool = self.pick_random();
            if (!picked) break;
            const oldrack: Rack = self.rack;
            var timer: std.time.Timer = try std.time.Timer.start();
            self.gen.gen_moves(&self.board, &self.rack);
            gen_time += timer.read();
            const has_moves = self.gen.movelist.items.len > 0;
            if (!has_moves) break;
            if (bestmove.letters.len == 0) break;
            total_moves += self.gen.movelist.items.len;
            self.make_move(bestmove);
            total_time += timer.read();
            moves_played += 1;
            total_score += bestmove.score;
            if (display) utils.print_board_ex(&self.board, &bestmove, &oldrack, &self.bag);
        }
        std.debug.print("moves played: {}\n", .{ moves_played });
        std.debug.print("duration without printing: {} milliseconds, total moves generated {}, totalscore {}\n", .{ total_time / 1000000, total_moves, total_score });
        std.debug.print("avg moves per second: {}\n", .{ utils.nps(total_moves, gen_time) });
        std.debug.print("\n", .{});
    }

    fn pick_random(self: *RndGame) bool
    {
        const pick_count: u9 = 7 - self.rack.count();
        if (pick_count == 0) return false;
        for (0..pick_count) |_|
        {
            if (self.bag.str.len == 0) break;
            const idx: u64 = self.rnd.next_u64_max(self.bag.str.len);
            const letter = self.bag.extract_letter(idx);
            self.rack.add_letter(letter);
        }
        return true;
    }

    fn make_move(self: *RndGame, move: Move) void
    {
        for (move.letters.slice()) |moveletter|
        {
            self.board.set_moveletter(moveletter);
            self.rack.remove_letter(moveletter);
        }
    }

    /// Debug
    fn has_duplicate_moves(self: *RndGame) !bool
    {
        self.hash.clearRetainingCapacity();
        for(self.gen.movelist.items) |mov|
        {
            const result = try self.hash.getOrPut(mov.letters);
            if (result.found_existing) return true;
        }
        return false;
    }
};

