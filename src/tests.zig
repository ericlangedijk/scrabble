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

var bestmove: Move = Move.EMPTY; // global nonsense now

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

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings, graph: *const Graph) !RndGame
    {
        return RndGame
        {
            .allocator = allocator,
            .settings = settings,
            .graph = graph,
            .rnd = Random.init(7), //init_randomized(),
            .gen = try MovGen.init(allocator, settings, graph, move_event),
            .bag = Bag.init(settings),
            .board = Board.init(settings),
            .rack = Rack.EMPTY,
        };
    }

    pub fn deinit(self: *RndGame) void
    {
        self.gen.deinit();
    }

    pub fn move_event(move: *const Move) void
    {
        if (move.score > bestmove.score)
        {
            bestmove = move.*;
            //std.debug.print("new best {}\n", .{bestmove.score});
        }
    }

    pub fn play(self: *RndGame) !void
    {
        var total_moves: usize = 0;
        var total_time: u64 = 0;
        var total_score: u32 = 0;
        while (true)
        {
            bestmove = Move.EMPTY;
            const picked: bool = self.pick_random();
            if (!picked) break;
            const oldrack: Rack = self.rack;
            var timer: std.time.Timer = try std.time.Timer.start();
            self.gen.generate_moves(&self.board, &self.rack);
            const has_moves = self.gen.movelist.items.len > 0;
            if (!has_moves) break;
            if (bestmove.letters.len == 0) break;
            total_moves += self.gen.movelist.items.len;
            self.make_move(bestmove);
            const elapsed = timer.lap();
            total_time += elapsed;
            total_score += bestmove.score;
            utils.printmove(&self.board, &bestmove, self.settings, oldrack);
            std.debug.print("bag: {} left\n", .{self.bag.get_count()});
        }
        std.debug.print("duration without printing: {} milliseconds, total moves generated {}, totalscore {}\n", .{ total_time / 1000000, total_moves, total_score });
    }

    fn pick_random(self: *RndGame) bool
    {
        var pick_count: u9 = 7 - self.rack.count();
        if (pick_count == 0) return false;
        var str = self.bag.to_string();
        if (str.len == 0) return false;
        if (pick_count > str.len) pick_count = str.len;

        for (0..pick_count) |_|
        {
            if (str.len == 0) break;
            const idx: u64 = self.rnd.next_u64_range(0, str.len);
            const letter = str.swapRemove(idx);
            self.rack.add_letter(letter);
            self.bag.remove_letter(letter);
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
};

