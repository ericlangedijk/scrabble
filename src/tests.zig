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

    pub fn play(self: *RndGame, comptime display: bool, new_seed: ?u64) !bool
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
            //if (display) std.debug.print("bag: {} left\n", .{self.bag.str.len});
            // todo: check duplicates.
        }
        //if (display)
        std.debug.print("moves played: {}\n", .{ moves_played });
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

pub fn test_some_boards(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !void
{
    var board: scrabble.Board = try scrabble.init_default_scrabbleboard(allocator, settings);
    //var board: scrabble.Board = try scrabble.init_custom_scrabbleboard(allocator, settings, 15, 15, @constCast(&scrabble.DEFAULT_WORDFEUD_BWV), @constCast(&scrabble.DEFAULT_WORDFEUD_BLV));
    defer board.deinit();
    var rack = scrabble.Rack.EMPTY;// scrabble.Rack.init();
    var gen = try MovGen.init(allocator, settings, graph, null);
    defer gen.deinit();
    //try board.set_string(settings, 105, "zend", .Horizontal);
    //try board.set_string(settings, 111, "sta", .Horizontal);
    //try board.set_string(settings, 118, "ie", .Horizontal);
    //board.set_string(settings, 105, "zendinstallati", .Horizontal);
    //board.set_string(settings, 106, "endinstallati", .Horizontal);
    // Yep, should have been -Doptimize=ReleaseFast. But that’s the zig build version of the flag and it’s using zig build-obj. Good catch
    const case: i32 = -4;
    switch (case)
    {
        -4 =>
        {
            //try utils.fill_board_from_txt_file(&board, "C:\\Users\\Eric\\Desktop\\wordfeud.txt"); // testing sidescore
            try board.set_string(settings, 112, "z", .Vertical);
            try rack.set_string(settings, "talen", 2);
        },
        -3 => // ir
        {
            try utils.fill_board_from_txt_file(&board, "C:\\Users\\Eric\\Desktop\\iris.txt");
            try rack.set_string(settings, "zelakje", 0);
        },
        -2 => // el
        {
            try utils.fill_board_from_txt_file(&board, "C:\\Users\\Eric\\Desktop\\wordfeud.txt");
            board.set_string(settings, 112, "zag", .Vertical);
            try rack.set_string(settings, "geuren", 1);
        },
        -1 =>
        {
            try board.set_string(settings, 112, "azen", .Horizontal);
            try rack.set_string(settings, "re", 0);
        },
        0 =>
        {
            try rack.set_string(settings, "mlantje", 0);
        },
        1 =>
        {
            // our raw speed test
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

    gen.sort_moves();
    var idx: usize = 0;
    for (gen.movelist.items) |*m|
    {
        //if (m.flags.is_crossword_generated and scrabble.square_x(m.anchor) == 11 and !m.flags.is_horizontally_generated and m.letters.len == 7)// and m.letters.len == 4)// and m.flags.is_crossword_generated and m.first().square == 98)
        //if (m.letters.len >= 7)//== 7 or m.find(scrabble.square_from(0,10)) != null)
        //if (m.find(47) != null)
        //if (m.contains_charcode(26) and !m.contains_blank())
        if (m.letters.len >= 7)//5 and m.flags.is_horizontally_generated)
        {
            //_ = m;
            //utils.printmove_only(m, settings);
            utils.print_board_ex(&board, m, &rack, null);
            //utils.printmove_only(m, settings);
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










