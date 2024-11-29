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

var bestmove: Move = Move.EMPTY;

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
            .board = Board.init(settings),
            .rack = Rack.EMPTY,
            .hash = MoveHashMap.init(allocator),
        };
    }

    pub fn deinit(self: *RndGame) void
    {
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

    pub fn play(self: *RndGame, comptime display: bool, new_seed: ?u64) !bool
    {
        //if (display) std.debug.print("RND: {}", .{self.rnd.seed});
        if (new_seed) |s| self.rnd.reset_seed(s);
        self.board.clear();
        self.bag.reset(self.settings);
        self.rack.clear();
        var total_moves: usize = 0;
        var total_time: u64 = 0;
        var gen_time: u64 = 0;
        var total_score: u32 = 0;
        while (true)
        {
            bestmove = Move.EMPTY;
            const picked: bool = self.pick_random();
            if (!picked) break;
            const oldrack: Rack = self.rack;
            var timer: std.time.Timer = try std.time.Timer.start();
            self.gen.generate_moves(&self.board, &self.rack);
            gen_time += timer.read();
            const has_moves = self.gen.movelist.items.len > 0;
            if (!has_moves) break;
            if (bestmove.letters.len == 0) break;
            total_moves += self.gen.movelist.items.len;
            self.make_move(bestmove);
            total_time += timer.read();
            total_score += bestmove.score;
            if (display) utils.printmove(&self.board, &bestmove, oldrack);
            if (display) std.debug.print("bag: {} left\n", .{self.bag.str.len});
            // todo: check duplicates.
        }
        //if (display)
        std.debug.print("duration without printing: {} milliseconds, total moves generated {}, totalscore {}\n", .{ total_time / 1000000, total_moves, total_score });
        //if (display)
        std.debug.print("avg moves per second: {}\n", .{ utils.nps(total_moves, gen_time) });
        std.debug.print("\n", .{});

        // const ok = try scrabble.validate_board(&self.board, self.graph);
        // if (!ok)
        // {
        //     utils.printboard(&self.board);
        // }
        // else std.debug.print("words ok   {}\n", .{self.rnd.seed});
        // const dups = try self.has_duplicate_moves();
        // if (!dups)
        // std.debug.print("no dups {}\n", .{self.rnd.seed});
        //self.gen.stats.print();

        // generated 12552, totalscore 842 with randseed = 1

        return true;
    }

    fn pick_random(self: *RndGame) bool
    {
        const pick_count: u9 = 7 - self.rack.count();
        if (pick_count == 0) return false;
        for (0..pick_count) |_|
        {
            if (self.bag.str.len == 0) break;
            const idx: u64 = self.rnd.next_u64_range(0, self.bag.str.len);
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





// SOME KNOWN OUTPUTS with NL.txt

// ---------------------------------------------------------------------------
//     genmoves
//     try board.set_string(settings, 112, "zend", .Horizontal);
//     try board.set_string(settings, 112, "zag", .Vertical);
//     var rack = try scrabble.Rack.init_string(settings, "talen");
//     rack.blanks = 2;
//     generates 61952 moves, sum-score 948611
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
//     rndgame (seed 1) take best move all the time
//     total moves generated 14910, totalscore 1032
// ---------------------------------------------------------------------------



