//! The move generator

const std = @import("std");
const assert = std.debug.assert;

const scrabble = @import("scrabble.zig");
const Settings = scrabble.Settings;
const CharCode = scrabble.CharCode;
const Letter = scrabble.Letter;
const CharCodeMask = scrabble.CharCodeMask;
const Orientation = scrabble.Orientation;
const Direction = scrabble.Direction;
const Square = scrabble.Square;
const Board = scrabble.Board;
const Rack = scrabble.Rack;
const Move = scrabble.Move;

const gaddag = @import("gaddag.zig");
const Graph = gaddag.Graph;
const Node = gaddag.Node;

const MoveStoredEvent = fn(move: *const Move) void;

// TODO: the extra parameters *SquareInfo shows a slight slowdown.

/// A fast movegenerator. 2.8 million moves per second measured.\
/// As far as I know it generates all possible moves for any situation. And produces no duplicates.
pub const MovGen = struct
{
    const MAX_MOVES: u32 = 262144;

    allocator: std.mem.Allocator,
    settings: *const Settings,
    graph: *const Graph,
    squareinfo: [Board.LEN]SquareInfo,
    movelist: std.ArrayList(Move),
    event: ?*const MoveStoredEvent,

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings, graph: *const Graph, event: ?*const MoveStoredEvent) !MovGen
    {
        return MovGen
        {
            .allocator = allocator,
            .settings = settings,
            .graph = graph,
            .squareinfo = create_squareinfo_cache(),
            .movelist = try std.ArrayList(Move).initCapacity(allocator, 1024),
            .event = event,
        };
    }

    fn create_squareinfo_cache() [Board.LEN]SquareInfo
    {
        var result: [Board.LEN]SquareInfo = undefined;
        for (&result) |*s|
        {
            s.* = SquareInfo.init_empty();
        }
        return result;
    }

    pub fn deinit(self: *MovGen) void
    {
        self.movelist.deinit();
    }

    pub fn generate_moves(self: *MovGen, board: *const Board, rack: *const Rack) void
    {
        assert(rack.letters.len + rack.blanks <= 7);

        // Always clear history.
        self.reset();

        if (rack.letters.len == 0) return;

        if (board.is_start_position())
        {
            self.gen_rack_moves(board, 0, Board.STARTSQUARE, self.graph.get_rootnode(), rack, Move.init_with_anchor(Board.STARTSQUARE));
        }
        else
        {
            self.process_anchors(board, rack);
        }
    }

    pub fn sort(self: *MovGen) void
    {
        std.mem.sortUnstable(Move, self.movelist.items, {}, less_than);
    }

    fn less_than(_: void, a: Move, b: Move) bool
    {
        return a.score > b.score;
    }

    fn reset(self: *MovGen) void
    {
        // When progressing a game, we should *not* clear this...
        for (&self.squareinfo) |*s|
        {
            s.* = SquareInfo.init_empty();
        }
        self.movelist.items.len = 0;
    }

    /// Process each anchor (eow) square.
    fn process_anchors(self: *MovGen, board: *const Board, rack: *const Rack) void
    {
        const root = self.graph.get_rootnode();

        for (Board.ALL_SQUARES) |square|
        {
            if (board.is_eow(square, .Horizontal))
            {
                const inf: *SquareInfo = &self.squareinfo[square];
                self.gen(board, square, root, rack, &Move.init_with_anchor(square), 0, .Horizontal, .Backwards);
                inf.mark_as_processed(.Horizontal);
                if (self.movelist.items.len >= MAX_MOVES) return;
            }
        }

        for (Board.ALL_SQUARES) |square|
        {
            if (board.is_eow(square, .Vertical))
            {
                const inf: *SquareInfo = &self.squareinfo[square];
                self.gen(board, square, root, rack, &Move.init_with_anchor(square), 0, .Vertical, .Backwards);
                inf.mark_as_processed(.Vertical);
                if (self.movelist.items.len >= MAX_MOVES) return;
            }
        }
    }

    /// The key method: with board letters just go on, otherwise try letters from the rack and *then* go on.
    fn gen(self: *MovGen, board: *const Board, square: Square, inputnode: Node, rack: *const Rack, move: *const Move, comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction) void
    {
        const inf = &self.squareinfo[square];
        if (inf.is_processed(ori)) return;

        if (board.get_letter(square)) |boardletter|
        {
            const node: ?Node = self.graph.find_node(inputnode, boardletter.charcode);
            self.go_on(board, square, boardletter, node, rack, move, flags & NOT_IS_TRY, ori, dir);
        }
        else
        {
            // Try rack letters. Maintain a trymask, preventing trying the same letter on the same square more than once.
            // "Fake initialize" the trymask with already disabled charcodes.
            if (rack.letters.len > 0)
            {
                var trymask: CharCodeMask = inf.get_excluded_mask(ori);
                for (rack.letters.slice(), 0..) |rackletter, idx|
                {
                    if (trymask.isSet(rackletter)) continue;
                    trymask.set(rackletter);
                    const trynode: Node = self.graph.find_node(inputnode, rackletter) orelse continue;
                    const tryletter: Letter = Letter.normal(rackletter);
                    const tryrack: Rack = rack.removed(idx);
                    const trymove: Move = move.added(tryletter, square, dir);
                    self.go_on(board, square, tryletter, trynode, &tryrack, &trymove, flags | IS_TRY, ori, dir);
                    // Only try crosswords generation at first attempt.
                    if (flags & IS_CROSSGEN == 0 and rack.letters.len > 1 and move.letters.len == 0)
                    {
                        self.gen_opp(board, square, tryletter, &tryrack, ori);
                    }
                }
            }
            // Try blanks.
            if (rack.blanks > 0)
            {
                const excluded_mask: CharCodeMask = inf.get_excluded_mask(ori);
                const children = self.graph.get_children(inputnode);
                for (children) |child|
                {
                    if (child.data.code == 0) continue; // skip bow nodes
                    if (excluded_mask.isSet(child.data.code)) continue;
                    const tryletter: Letter = Letter.blank(child.data.code);
                    const tryrack: Rack = rack.removed_blank();
                    const trymove: Move = move.added(tryletter, square, dir);
                    self.go_on(board, square, tryletter, child, &tryrack, &trymove, flags | IS_TRY, ori, dir);
                    // Only try crosswords generation at first attempt.
                    if (flags & IS_CROSSGEN == 0 and rack.letters.len > 1 and move.letters.len == 0)
                    {
                        self.gen_opp(board, square, tryletter, &tryrack, ori);
                    }
                }
            }
        }
    }

    /// Special move generation for non-anchors: we generate moves in the opposite direction during tries.
    fn gen_opp(self: *MovGen, board: *const Board, square: Square, tryletter: Letter, rack: *const Rack, comptime ori: Orientation) void
    {
        const opp = ori.opp();
        const inf = &self.squareinfo[square];
        if (inf.is_processed(opp)) return;
        const node = self.graph.find_node_from_root(tryletter.charcode) orelse return;
        // These 2 cases will always be handled by default.
        if (!board.is_next_free(square, opp, .Forwards) or !board.is_next_free(square, opp, .Backwards)) return;
        // Check if we have a legel situation in the *original* direction (yes we have to use opp). This is also done in go_on but this is a shortcut.
        if (!self.cross_check(board, square, tryletter.charcode, opp)) return;
        // Create a new move.
        var move: Move = Move.init_with_anchor(square);
        move.add_letter(tryletter, square);
        // Go to the next square from here.
        self.go_on(board, square, tryletter, node, rack, &move, IS_CROSSGEN | IS_TRY, opp, .Backwards);
        inf.mark_as_processed(opp);
    }

    /// Depending on orientation and direction go to the next square. Note that `go_on` always has to be called from `gen`, even if `inputnode` is null.\
    /// We can have a pending move that has to be stored.
    fn go_on(self: *MovGen, board: *const Board, square: Square, letter: Letter, inputnode: ?Node, rack: *const Rack, move: *const Move, comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction) void
    {
        assert(letter.is_filled());

        const inf = &self.squareinfo[square];
        if (inf.is_processed(ori)) return;

        // Check dead end or check store pending move.
        if (!self.try_this(board, square, letter, inputnode, move, flags, ori, dir)) return;

        const node: Node = inputnode orelse return;
        switch (dir)
        {
            .Forwards =>
            {
                if (scrabble.next_square(square, ori, dir)) |nextsquare|
                {
                    self.gen(board, nextsquare, node, rack, move, flags, ori, dir);
                }
            },
            .Backwards =>
            {
                if (scrabble.next_square(square, ori, dir)) |nextsquare|
                {
                    self.gen(board, nextsquare, node, rack, move, flags, ori, dir);
                }

                // Magic recursive turnaround: we go back to the anchor square (eow) (or the special crossword anchor). and check we can put a letter after that. Switch to bow!
                if (board.is_next_free(square, ori, dir) and board.is_next_free(move.anchor, ori, .Forwards)) // TODO: maybe check there is something after the anchor here.
                {
                    const anchornode: ?Node = self.graph.get_bow(node);
                    if (anchornode) |n|
                    {
                        const after_anchor: Square = scrabble.next_square(move.anchor, ori, .Forwards) orelse return;
                        self.gen(board, after_anchor, n, rack, move, flags, ori, .Forwards);
                    }
                }
            }
        }
    }

    /// If we have a dead end (crossword error) the result is false. Otherwise check store pending move.
    fn try_this(self: *MovGen, board: *const Board, square: Square, tryletter: Letter, inputnode: ?Node, move: *const Move, comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction) bool
    {
        if (move.letters.len == 0) return true;
        const node: Node = (inputnode) orelse return true;
        const is_try = flags & IS_TRY != 0;

        // Check dead end.
        if (is_try and !self.cross_check(board, square, tryletter.charcode, ori)) return false;

        // Check store pending move.
        switch (dir)
        {
            .Forwards => if (node.data.is_eow and board.is_next_free(square, ori, dir)) self.store_move(board, move, ori, flags, false),
            .Backwards => if (node.data.is_bow and node.data.is_whole_word and board.is_next_free(square, ori, dir)) self.store_move(board, move, ori, flags, false),
        }
        return true;
    }

    /// Cross check using (and filling) cached info. The caching of included + excluded letters saves a *lot* of processing.
    fn cross_check(self: *MovGen, board: *const Board, square: Square, trycharcode: CharCode, comptime ori: Orientation) bool
    {
        const inf: *SquareInfo = &self.squareinfo[square];
        if (inf.is_charcode_excluded(trycharcode, ori)) return false;
        if (inf.is_charcode_included(trycharcode, ori)) return true;
        const ok: bool = self.do_crosscheck(board, square, trycharcode, ori);
        if (ok) inf.mark_charcode_included(trycharcode, ori) else inf.mark_charcode_excluded(trycharcode, ori);
        return ok;
    }

    /// Checks valid crossword for the *opposite* orientation of `ori`.
    pub fn do_crosscheck(self: *MovGen, board: *const Board, q: Square, trycharcode: CharCode, comptime ori: Orientation) bool
    {
        // example: ". . i n s t _ n c e . ." (only "a" will succeed).
        const opp: Orientation = ori.opp();
        const check_backwards: bool = board.has_filled_neighbour(q, opp, .Backwards);
        const check_forwards: bool = board.has_filled_neighbour(q, opp, .Forwards);

        // Nothing to do.
        if (!check_backwards and !check_forwards) return true;

        // Find root node of the letter (on the "_" square).
        var node: Node = self.graph.find_node_from_root(trycharcode) orelse return false;

        // Scan backwards prefix ("tsni")
        if (check_backwards)
        {
            var iter = board.letter_iterator(q, opp, .Backwards, false);
            while (iter.next()) |boardletter|
            {
                node = self.graph.find_node(node, boardletter.letter.charcode) orelse return false;
            }
        }

        // If done (no forward neighbour), we reached the beginning of the word ("i"), so check is_bow and is_whole_word
        if (!check_forwards) return node.data.is_bow and node.data.is_whole_word;

        // Check bow and switch to suffix. I keep having difficulty visualizing it: in the tree is "_tsni + nces".
        node = self.graph.get_bow(node) orelse return false;

        // Scan forward suffix ("nce").
        if (check_forwards)
        {
            var iter = board.letter_iterator(q, opp, .Forwards, false);
            while (iter.next()) |boardletter|
            {
                node = self.graph.find_node(node, boardletter.letter.charcode) orelse return false;
            }
        }

        // Finally check is_eow ("e").
        return node.data.is_eow;
    }

    fn store_move(self: *MovGen, board: *const Board, move: *const Move, comptime ori: Orientation, comptime flags: GenFlags, comptime is_first_move: bool) void
    {
        assert(move.letters.len > 0);

        var storedmove: Move = move.*;

        if (!is_first_move)
        {
            // We have to do a little filtering here on duplicate one-letter moves. These are quite rare.
            if (move.letters.len == 1)
            {
                if (ori == .Horizontal)
                {
                    self.squareinfo[move.first().square].is_used_for_one = true; // mark this and store
                }
                else
                {
                    if (self.squareinfo[move.first().square].is_used_for_one) return; // do not store
                }
            }
            storedmove.score = scrabble.calculate_score(self.settings, board, move, ori);
        }
        else
        {
            storedmove.score = scrabble.calculate_score_on_empty_board(self.settings, move);
        }

        storedmove.set_flags(ori, flags & IS_CROSSGEN != 0);
        self.movelist.append(storedmove) catch return;
        if (self.event) |ev| ev(&storedmove);
    }

    /// If the board is empty, all possible horizontal moves are generated from the graph.\
    /// At depth zero `inputnode` must be the graph rootnode, and `q` the startingsquare of the board.\
    /// in `store_rack_moves` we make clones of each generate move (rotated and shifted) connected to the startsquare.
    fn gen_rack_moves(self: *MovGen, board: *const Board, depth: u8, q: Square, inputnode: ?Node, rack: *const Rack, move: Move) void
    {
        // TODO: not tested if all this is correct.
        const node = inputnode orelse return;
        if (node.count == 0) return;
        const graph = self.graph;

        // Try letters.
        if (rack.letters.len > 0)
        {
            var tried_mask: CharCodeMask = CharCodeMask.initEmpty();
            for (rack.letters.slice(), 0..) |rackletter, i|
            {
                if (tried_mask.isSet(rackletter)) continue;
                tried_mask.set(rackletter);
                if (graph.find_node(node, rackletter)) |childnode|
                {
                    const newmove: Move = move.ret_add(rackletter, false, q);
                    if (childnode.data.is_eow) self.store_rack_moves(board, newmove);
                    const passnode: ?Node = if (depth > 0) childnode else graph.get_bow(childnode);
                    self.gen_rack_moves(board, depth + 1, q + 1, passnode, &rack.removed(i), newmove);
                }
            }
        }

        // Try blanks.
        if (rack.blanks > 0)
        {
            const children = graph.get_children(node);
            for(children) |childnode|
            {
                const charcode = childnode.data.code;
                if (charcode == 0) continue;
                const newmove: Move = move.ret_add(charcode, true, q);
                if (childnode.data.is_eow) self.store_rack_moves(board, newmove);
                const passnode: ?Node = if (depth > 0) childnode else graph.get_bow(childnode);
                self.gen_rack_moves(board, depth + 1, q + 1, passnode, &rack.removed_blank(), newmove);
            }
        }
    }

    /// Dedicated routine for rack generated moves, shifting and rotating.
    fn store_rack_moves(self: *MovGen, board: *const Board, move: Move) void
    {
        const count = move.count();
        var shifted_move: Move = move;
        shifted_move.set_flags(.Horizontal, false);
        for (0..count) |_|
        {
            _ = self.store_move(board, &shifted_move, .Horizontal, 0, true);
            shifted_move.shift_left(.Horizontal);
        }

        var rotated_move: Move = move;
        rotated_move.rotate();
        shifted_move.set_flags(.Vertical, false);
        for (0..count) |_|
        {
            _ = self.store_move(board, &rotated_move, .Vertical, 0, true);
            rotated_move.shift_left(.Vertical);
        }
    }
};


/// During processing this struct is updated for little speedups.
pub const SquareInfo = struct
{
    //const EMPTY: SquareInfo = SquareInfo {. excluded_charcodes = 0, .included_charcodes = 0 };

    pub const OrientedInfo = struct
    {
        excluded_charcodes: CharCodeMask = CharCodeMask.initEmpty(),
        included_charcodes: CharCodeMask = CharCodeMask.initEmpty(),
        is_processed: bool = false,
    };

    const Flags = packed struct
    {
        /// Set when anchor is processed and also when crossword anchor is processed from here.
        is_processed: bool
    };


    horz: OrientedInfo,
    vert: OrientedInfo,
    // TODO: maybe put square in here to save one parameter in all the calls. initialize once.
    is_used_for_one: bool = false, // if we need more then make packed struct

    fn init_empty() SquareInfo
    {
        return SquareInfo
        {
            .horz = OrientedInfo {},
            .vert = OrientedInfo {},
            .is_used_for_one = false,
        };
    }

    fn get_excluded_mask(self: *const SquareInfo, comptime ori: Orientation) CharCodeMask
    {
        return switch (ori)
        {
            .Horizontal => self.horz.excluded_charcodes,
            .Vertical => self.vert.excluded_charcodes,
        };
    }

    fn get_included_mask(self: *const SquareInfo, comptime ori: Orientation) CharCodeMask
    {
        return switch (ori)
        {
            .Horizontal => self.horz.included_charcodes,
            .Vertical => self.vert.included_charcodes,
        };
    }

    fn is_charcode_excluded(self: *const SquareInfo, charcode: CharCode, comptime ori: Orientation) bool
    {
        return switch (ori)
        {
            .Horizontal => self.horz.excluded_charcodes.isSet(charcode),
            .Vertical => self.vert.excluded_charcodes.isSet(charcode),
        };
    }

    fn mark_charcode_excluded(self: *SquareInfo, charcode: CharCode, comptime ori: Orientation) void
    {
        switch (ori)
        {
            .Horizontal => self.horz.excluded_charcodes.set(charcode),
            .Vertical => self.vert.excluded_charcodes.set(charcode),
        }
    }

    fn is_charcode_included(self: *const SquareInfo, charcode: CharCode, comptime ori: Orientation) bool
    {
        return switch (ori)
        {
            .Horizontal => self.horz.included_charcodes.isSet(charcode),
            .Vertical => self.vert.included_charcodes.isSet(charcode),
        };
    }

    fn mark_charcode_included(self: *SquareInfo, charcode: CharCode, comptime ori: Orientation) void
    {
        switch (ori)
        {
            .Horizontal => self.horz.included_charcodes.set(charcode),
            .Vertical => self.vert.included_charcodes.set(charcode),
        }
    }

    fn mark_as_processed(self: *SquareInfo, comptime ori: Orientation) void
    {
        switch (ori)
        {
            .Horizontal => self.horz.is_processed = true,
            .Vertical => self.vert.is_processed = true,
        }
    }

    fn is_processed(self: *const SquareInfo, comptime ori: Orientation) bool
    {
        return switch (ori)
        {
            .Horizontal => self.horz.is_processed,
            .Vertical => self.vert.is_processed,
        };
    }
};

/// I think it is easier to work with a direct bit mask for the flags in the move generator than some std bitmask class.
const GenFlags = u2;

const IS_TRY: GenFlags = 1 << 0;
const IS_CROSSGEN: GenFlags = 1 << 1;

const NOT_IS_TRY: GenFlags = ~IS_TRY;
const NOT_IS_CROSSGEN: GenFlags = ~IS_CROSSGEN;



// pub const State = struct
// {
//     squareinfo: SquareInfo,
//     letter: Letter,
//     node: ?Node,
//     rack: Rack,
//     move: Move,

//     inline fn init() !State
//     {
//         return State { .letter = Letter.EMPTY, .node = null, .rack = Rack.EMPTY, .move = Move.EMPTY };
//     }

//     fn try_child(self: *State, graph: *Graph, charcode: CharCode) bool
//     {
//         if (self.node) |n| self.node = graph.find_node(n, charcode);
//         return self.node != null;
//     }

//     fn set_for_try(self: *State, letter: Letter, square: Square, rack_idx: usize) void
//     {
//         self.letter = letter;
//         self.rack.remove(rack_idx);
//         self.move.add_letter(letter, square);
//         self.path.appendAssumeCapacity(letter.charcode);
//     }
// };


    // pub fn printchilden(self: *MovGen, node: Node) void
    // {
    //     const children = self.graph.get_children(node);
    //     std.debug.print("(children){c}:", .{self.settings.code_to_char(node.data.code)});
    //     for(children)|child|
    //     {
    //         const c = self.settings.code_to_char(child.data.code);
    //         std.debug.print("{c}/", .{c});
    //     }
    //     std.debug.print("\n", .{});
    // }
