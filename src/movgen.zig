//! The move generator

const std = @import("std");
const assert = std.debug.assert;

const utils = @import("utils.zig");

const scrabble = @import("scrabble.zig");
const not = scrabble.not;
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

const MoveStoredEvent = fn (move: *const Move) void;

/// A fast movegenerator. 4.6 million moves per second measured.\
/// As far as I know it generates all possible moves for any situation. And produces no duplicates.
pub const MovGen = struct
{
    const MAX_MOVES: u32 = 262144;

    allocator: std.mem.Allocator,
    settings: *const Settings,
    graph: *const Graph,
    squareinfo: [448]SquareInfo, // TODO: maybe dynamic because of stack.
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

    fn create_squareinfo_cache() [448]SquareInfo
    {
        var result: [448]SquareInfo = undefined;
        for (&result) |*s| s.* = SquareInfo.EMPTY;
        return result;
    }

    pub fn deinit(self: *MovGen) void
    {
        self.movelist.deinit();
    }

    pub fn sort_moves(self: *MovGen) void
    {
        std.mem.sortUnstable(Move, self.movelist.items, {}, less_than);
    }

    fn less_than(_: void, a: Move, b: Move) bool
    {
        return a.score > b.score;
    }

    pub fn gen_moves(self: *MovGen, board: *const Board, rack: *const Rack) void
    {
        //var timer = std.time.Timer.start() catch return;
        self.prepare(board);
        //const e = timer.lap();
        //std.debug.print("prepare {}", .{e});

        if (rack.count() == 0) return;

        if (board.is_start_position())
        {
            self.gen_rack_moves(board, 0, board.startsquare, self.graph.get_rootnode(), rack, Move.init_with_anchor(board.startsquare));
        }
        else
        {
            self.process_anchors(board, rack);
        }
    }

    /// Prepare square info. We have to sacrificle 0.01 milliseconds here.
    fn prepare(self: *MovGen, board: *const Board) void
    {
        self.movelist.items.len = 0;

        var iter_left = board.letter_iterator(0, .Horizontal, .Backwards, false);
        var iter_right = board.letter_iterator(0, .Horizontal, .Forwards, false);
        var iter_up = board.letter_iterator(0, .Vertical, .Backwards, false);
        var iter_down = board.letter_iterator(0, .Vertical, .Forwards, false);

        for (self.squareinfo[0..board.length], 0..) |*inf, i|
        {
            const square: Square = @intCast(i);
            inf.* = SquareInfo.EMPTY;
            inf.boardinfo.bwv = board.bwv[square];
            inf.boardinfo.blv = board.blv[square];
            inf.boardinfo.lv = self.settings.lv(board.squares[square]);

            // Cache sidescores. We only calculate sidescores for empty squares.
            if (board.is_empty(square))
            {
                iter_left.reset(square);
                while (iter_left.next()) |B| inf.vert.sidescore += self.settings.lv(B.letter);

                iter_right.reset(square);
                while (iter_right.next()) |B| inf.vert.sidescore += self.settings.lv(B.letter);

                if (iter_left.current_square() != iter_right.current_square())
                {
                    inf.vert.flags.has_cross_letters = true;
                }
                else
                {
                    inf.vert.flags.can_ignore_crosscheck = true;
                }

                iter_up.reset(square);
                while (iter_up.next()) |B| inf.horz.sidescore += self.settings.lv(B.letter);

                iter_down.reset(square);
                while (iter_down.next()) |B| inf.horz.sidescore += self.settings.lv(B.letter);

                if (iter_up.current_square() != iter_down.current_square())
                {
                    inf.horz.flags.has_cross_letters = true;
                }
                else
                {
                    inf.horz.flags.can_ignore_crosscheck = true;
                }
            }
        }
    }

    /// Process each anchor square.
    fn process_anchors(self: *MovGen, board: *const Board, rack: *const Rack) void
     {
        const root: *const Node = self.graph.get_rootnode();
        const wordmul: u16 = 1;
        const sidescores: u16 = 0;

        // horz
        for (0..board.length) |i|
        {
            const square: scrabble.Square = @intCast(i);
            if (not(board.is_eow(square, .Horizontal))) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), wordmul, sidescores, NO_FLAGS, .Horizontal, .Backwards);
            inf.mark_as_processed(.Horizontal);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }

        // vert
        for (0..board.length) |i|
        {
            const square: scrabble.Square = @intCast(i);
            if (not(board.is_eow(square, .Vertical))) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), wordmul, sidescores, NO_FLAGS, .Vertical, .Backwards);
            inf.mark_as_processed(.Vertical);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }

        // horz crosswords
        for (0..board.length) |i|
        {
            const square: scrabble.Square = @intCast(i);
            if (not(board.is_crossword_anchor(square, .Horizontal))) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), wordmul, sidescores, IS_CROSSGEN, .Horizontal, .Backwards);
            inf.mark_as_processed_by_crossword(.Horizontal);
            inf.mark_as_processed(.Horizontal);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }

        // vert crosswords
        for (0..board.length) |i|
        {
            const square: scrabble.Square = @intCast(i);
            if (not(board.is_crossword_anchor(square, .Vertical))) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), wordmul, sidescores, IS_CROSSGEN, .Vertical, .Backwards);
            inf.mark_as_processed_by_crossword(.Vertical);
            inf.mark_as_processed(.Vertical);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }
    }

    /// The key method: with board letters just go on, otherwise try letters from the rack and *then* go on.\
    /// We update the move's (own) score on the fly and keep track of all sidescores. This is faster than calulcating each move separately.
    /// During the loop:
    /// - the move score is updated with boardletters and tryletters * blv, so this is the basescore.
    /// - `wordmul` is the base word multiplication.
    /// - `sidescores` is the sum of all sidescores and incremented after a succesful cross check.
    fn gen
    (
        self: *MovGen, board: *const Board,
        square: Square, node: *const Node, rack: *const Rack, move: *const Move, wordmul: u16, sidescores: u16,
        comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction
    ) void
    {
        const inf = &self.squareinfo[square];
        if (inf.is_processed(ori)) return;
        if (flags & IS_CROSSGEN != 0 and inf.is_processed_by_crossword(ori)) return;

        if (board.get_letter(square)) |boardletter|
        {
            const boardnode: *const Node = self.graph.find_node(node, boardletter.charcode) orelse return;
            const go_on_move: Move = move.incremented_score(inf.boardinfo.lv); // increment base score of move.
            self.go_on(board, square, boardnode, rack, &go_on_move, wordmul, sidescores, boardletter, flags & NOT_IS_TRY, ori, dir);
        }
        else
        {
            if (rack.count() == 0) return;
            @prefetch(self.graph.get_children_ptr(node), .{});
            // Try rack letters.
            if (rack.letters.len > 0)
            {
                var trymask: CharCodeMask = inf.get_excluded_mask(ori); // required filter! (see crosscheck)
                for (rack.letters.slice(), 0..) |rackletter, idx|
                {
                    if (trymask.isSet(rackletter)) continue; // prevent trying the same letter on the same square more than once
                    trymask.set(rackletter);
                    const trynode: *const Node = self.graph.find_node(node, rackletter) orelse continue;
                    const tryletter: Letter = Letter.normal(rackletter);
                    const tryrack: Rack = rack.removed(idx);
                    const lv: u8 = self.settings.lv(tryletter) * inf.boardinfo.blv;
                    const trymove: Move = move.appended_or_inserted(tryletter, square, lv, dir);
                    self.go_on(board, square, trynode, &tryrack, &trymove, wordmul * inf.boardinfo.bwv, sidescores, tryletter, flags | IS_TRY, ori, dir);
                }
            }
            // Try blanks.
            if (rack.blanks > 0)
            {
                const excluded_mask: CharCodeMask = inf.get_excluded_mask(ori); // required filter! (see `cross_check`)
                const children = self.graph.get_children(node);
                for (children) |*child|
                {
                    if (excluded_mask.isSet(child.data.code)) continue; // The excluded_mask is initialized with bit 0 set, so we always skip bow nodes (with code = 0).
                    assert(child.data.code != 0);
                    const tryletter: Letter = Letter.blank(child.data.code);
                    const tryrack: Rack = rack.removed_blank();
                    const trymove: Move = move.appended_or_inserted(tryletter, square, 0, dir);
                    self.go_on(board, square, child, &tryrack, &trymove, wordmul * inf.boardinfo.bwv, sidescores, tryletter, flags | IS_TRY, ori, dir);
                }
            }
        }
    }

    /// Depending on orientation and direction go to the next square.
    fn go_on
    (
        self: *MovGen, board: *const Board,
        square: Square, node: *const Node, rack: *const Rack, move: *const Move, wordmul: u16, sidescores: u16, letter: Letter,
        comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction
    ) void
    {
        assert(letter.is_filled());
        assert(not(self.squareinfo[square].is_processed(ori))); // this should never happen.

        const inf: *SquareInfo = &self.squareinfo[square];
        var this_sidescore: u16 = 0;

        // Check dead end or increment sidescores.
        if (flags & IS_TRY != 0)
        {
            if (not(self.crosscheck(board, square, letter.charcode, ori))) return;
            if (inf.has_cross_letters(ori))
            {
                this_sidescore = inf.get_sidescore(ori);
                this_sidescore += self.settings.lv(letter) * inf.boardinfo.blv; // include the tryletter in the sidescore
                this_sidescore *= inf.boardinfo.bwv; // and include the bwv
            }
        }

        self.check_store(board, square, node, move, wordmul, sidescores + this_sidescore, flags, ori, dir);

        if (board.next_square(square, ori, dir)) |nextsquare|
        {
            self.gen(board, nextsquare, node, rack, move, wordmul, sidescores + this_sidescore, flags, ori, dir);
        }

        // Magic recursive turnaround: we go back to the anchor square (eow) (or the crossword anchor). and check we can put a letter after that. Switch to bow!
        // It is important *not* to process any squares we already scanned during backwards processing.
        if (dir == .Backwards)
        {
            if (board.is_free(square, ori, dir) and board.is_free(move.anchor, ori, .Forwards))
            {
                const after_anchor: Square = board.next_square(move.anchor, ori, .Forwards) orelse return; // we can be at the board border.
                const anchornode: *const Node = self.graph.get_bow(node) orelse return;
                self.gen(board, after_anchor, anchornode, rack, move, wordmul, sidescores + this_sidescore, flags, ori, .Forwards);
            }
        }
    }

    /// Cross check using (and filling) cached info. The caching of excluded and included letters saves a *lot* of processing.
    /// Note that the excluded letters are (and must) already pre-checked during triesin `gen`.\
    fn crosscheck(self: *MovGen, board: *const Board, square: Square, trycharcode: CharCode, comptime ori: Orientation) bool
    {
        const inf: *SquareInfo = &self.squareinfo[square];
        assert(not(inf.is_charcode_excluded(trycharcode, ori))); // this should never happen. tries must be pre-checked.
        if (inf.can_ignore_crosscheck(ori)) return true;
        if (inf.is_charcode_included(trycharcode, ori)) return true;
        const ok: bool = self.do_crosscheck(board, square, trycharcode, ori);
        if (ok) inf.mark_charcode_included(trycharcode, ori) else inf.mark_charcode_excluded(trycharcode, ori);
        return ok;
    }

    /// Checks valid crossword for the *opposite* orientation of `ori`.
    fn do_crosscheck(self: *MovGen, board: *const Board, q: Square, trycharcode: CharCode, comptime ori: Orientation) bool
    {
        // example: ". . i n s t _ n c e . ." (only "a" will succeed).
        const opp: Orientation = ori.opp();

        const check_backwards: bool = board.has_filled_neighbour(q, opp, .Backwards); // TODO: maybe a flag could speed up a little bit
        const check_forwards: bool = board.has_filled_neighbour(q, opp, .Forwards); // TODO: maybe a flag could speed up a little bit

        // Find root node of the tryletter (on the "_" square).
        var node: *const Node = self.graph.find_node_from_root(trycharcode) orelse return false;

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
        if (not(check_forwards))
        {
            return node.data.is_bow and node.data.is_whole_word;
        }

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

    /// Check if we can store a pending move (if the square is free and we have a whole word).
    fn check_store(self: *MovGen, board: *const Board, square: Square, node: *const Node, move: *const Move, wordmul: u16, sidescores: u16, comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction) void
     {
        switch (dir)
        {
            .Forwards =>
            {
                if (node.data.is_eow and board.is_free(square, ori, dir))
                {
                    self.store_move(board, move, wordmul, sidescores, ori, flags, false);
                }
            },
            .Backwards =>
            {
                if (node.data.is_bow and node.data.is_whole_word and board.is_free(square, ori, dir))
                {
                    self.store_move(board, move, wordmul, sidescores, ori, flags, false);
                }
            },
        }
    }

    fn store_move(self: *MovGen, board: *const Board, move: *const Move, wordmul: u16, sidescore: u16, comptime ori: Orientation, comptime flags: GenFlags, comptime is_first_move: bool) void
    {
        if (move.letters.len == 0) return;
        const is_cross_gen: bool = flags & IS_CROSSGEN != 0;

        // We do not store these, because they will already be handled by normal anchors.
        if (is_cross_gen and move.letters.len == 1) return;

        var storedmove: Move = move.*;

        if (not(is_first_move))
        {
            // Unfortunately we have to do a little filtering here to prevent duplicate one-letter moves. These are quite rare.
            if (storedmove.letters.len == 1)
            {
                const first = storedmove.first();
                const inf = &self.squareinfo[first.square];
                if (inf.is_one_mask_set(first.letter)) return;
                inf.mark_one_mask_set(first.letter);
            }
            storedmove.score *= wordmul;
            storedmove.score += sidescore;
            if (storedmove.letters.len == 7) storedmove.score += 50;
        }
        else
        {
            storedmove.score = scrabble.calculate_score_on_empty_board(self.settings, board, &storedmove);
        }

        storedmove.set_flags(ori, is_cross_gen);
        self.movelist.append(storedmove) catch return;
        if (self.event) |ev| ev(&storedmove);
    }

    fn gen_pass_moves() void
    {

    }

    /// If the board is empty, all possible horizontal moves are generated from the graph.\
    /// At depth zero `inputnode` must be the graph rootnode, and `q` the startingsquare of the board.\
    /// in `store_rack_moves` we make clones of each generate move (rotated and shifted) connected to the startsquare.
    fn gen_rack_moves(self: *MovGen, board: *const Board, depth: u8, q: Square, inputnode: ?*const Node, rack: *const Rack, move: Move) void
    {
        if (self.movelist.items.len >= MAX_MOVES) return;
        const node = inputnode orelse return;
        if (node.count == 0) return;
        const graph = self.graph;

        // Try letters.
        if (rack.letters.len > 0) {
            var tried_mask: CharCodeMask = CharCodeMask.initEmpty();
            for (rack.letters.slice(), 0..) |rackletter, i|
            {
                if (tried_mask.isSet(rackletter)) continue;
                tried_mask.set(rackletter);
                if (graph.find_node(node, rackletter)) |childnode|
                {
                    const letter: Letter = Letter.init(rackletter, false);
                    const newmove: Move = move.appended(letter, q);
                    if (childnode.data.is_eow) self.store_rack_moves(board, newmove);
                    const passnode: ?*const Node = if (depth > 0) childnode else graph.get_bow(childnode);
                    self.gen_rack_moves(board, depth + 1, q + 1, passnode, &rack.removed(i), newmove);
                }
            }
        }

        // Try blanks.
        if (rack.blanks > 0) {
            const children = graph.get_children(node);
            for (children) |*childnode|
            {
                const charcode = childnode.data.code;
                if (charcode == 0) continue; // skip bow node
                const letter: Letter = Letter.init(charcode, true);
                const newmove: Move = move.appended(letter, q);
                if (childnode.data.is_eow) self.store_rack_moves(board, newmove);
                const passnode: ?*const Node = if (depth > 0) childnode else graph.get_bow(childnode);
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
            _ = self.store_move(board, &shifted_move, 0, 0, .Horizontal, NO_FLAGS, true);
            shifted_move.shift_left(board, .Horizontal);
        }

        var rotated_move: Move = move;
        rotated_move.rotate(board);
        shifted_move.set_flags(.Vertical, false);
        for (0..count) |_|
        {
            _ = self.store_move(board, &rotated_move, 0, 0, .Vertical, NO_FLAGS, true);
            rotated_move.shift_left(board, .Vertical);
        }
    }
};

/// During processing this struct is updated for shortcuts, speedups and preventing duplicate moves. The functions are just easy-to-read additions.
pub const SquareInfo = struct
{
    const EMPTY: SquareInfo = SquareInfo {};

    /// The charcode bits which are excluded. code 0 (bit 0) must be disabled by default.
    const INITIAL_EXCLUDED_MASK: CharCodeMask = @bitCast(@as(u32, 1));
    /// This mask is caching letters including the blank bit.
    const EMPTY_LETTER_MASK = std.bit_set.IntegerBitSet(64).initEmpty();

    pub const BoardInfo = struct
    {
        bwv: u8 = 0,
        blv: u8 = 0,
        lv: u8 = 0,
    };

    pub const OrientedInfo = struct
    {
        const Flags = packed struct
        {
            /// Flag when anchor is processed.
            is_processed: bool = false,
            /// Flag when crossword anchor is processed.
            is_processed_by_crossword: bool = false,
            /// Flag when we know there is no cross-check needed at all.
            can_ignore_crosscheck: bool = false,
            /// Extra flag. Can be used for shortcuts but is needed for sidescores as well: the sidescore can be zero because there are only blanks. We still have to multiply.
            has_cross_letters: bool = false,
        };

        /// Cache for invalid letters during croschecks.
        excluded_charcodes: CharCodeMask = INITIAL_EXCLUDED_MASK,
        /// Cache for valid letters during croschecks.
        included_charcodes: CharCodeMask = scrabble.EMPTY_CHARCODE_MASK,
        /// Our cached side score (empty squares only).
        sidescore: u16 = 0,
        /// Our processing flags.
        flags: Flags = Flags {},
    };

    /// On board
    boardinfo:  BoardInfo = BoardInfo {},
    /// Horizontal info
    horz: OrientedInfo = OrientedInfo {},
    /// Vertical info
    vert: OrientedInfo = OrientedInfo {},
    /// Cache for one-letter moves, preventing 1-letter move duplicates. Note that it is including the blank, so 64 bits needed.
    one_letter_used_mask: std.bit_set.IntegerBitSet(64) = EMPTY_LETTER_MASK,

    fn is_processed(self: *const SquareInfo, comptime ori: Orientation) bool
    {
        return switch (ori)
        {
            .Horizontal => self.horz.flags.is_processed,
            .Vertical => self.vert.flags.is_processed,
        };
    }

    fn mark_as_processed(self: *SquareInfo, comptime ori: Orientation) void
    {
        switch (ori)
        {
            .Horizontal => self.horz.flags.is_processed = true,
            .Vertical => self.vert.flags.is_processed = true,
        }
    }

    fn is_processed_by_crossword(self: *const SquareInfo, comptime ori: Orientation) bool
     {
        return switch (ori)
        {
            .Horizontal => self.horz.flags.is_processed_by_crossword,
            .Vertical => self.vert.flags.is_processed_by_crossword,
        };
    }

    fn mark_as_processed_by_crossword(self: *SquareInfo, comptime ori: Orientation) void
    {
        return switch (ori)
        {
            .Horizontal => self.horz.flags.is_processed_by_crossword = true,
            .Vertical => self.vert.flags.is_processed_by_crossword = true,
        };
    }

    fn can_ignore_crosscheck(self: *const SquareInfo, comptime ori: Orientation) bool
     {
        return switch (ori)
        {
            .Horizontal => self.horz.flags.can_ignore_crosscheck,
            .Vertical => self.vert.flags.can_ignore_crosscheck,
        };
    }

    fn mark_can_ignore_crosscheck(self: *SquareInfo, comptime ori: Orientation) void
    {
        return switch (ori)
        {
            .Horizontal => self.horz.flags.can_ignore_crosscheck = true,
            .Vertical => self.vert.flags.can_ignore_crosscheck = true,
        };
    }

    fn is_one_mask_set(self: *const SquareInfo, letter: Letter) bool
    {
        return self.one_letter_used_mask.isSet(letter.as_u6());
    }

    fn mark_one_mask_set(self: *SquareInfo, letter: Letter) void
    {
        self.one_letter_used_mask.set(letter.as_u6());
    }

    pub fn get_excluded_mask(self: *const SquareInfo, comptime ori: Orientation) CharCodeMask
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

    fn has_cross_letters(self: *const SquareInfo, comptime ori: Orientation) bool
    {
        return switch (ori)
        {
            .Horizontal => self.horz.flags.has_cross_letters,
            .Vertical => self.vert.flags.has_cross_letters,
        };
    }

    fn get_sidescore(self: *const SquareInfo, comptime ori: Orientation) u16
    {
        return switch (ori)
        {
            .Horizontal => self.horz.sidescore,
            .Vertical => self.vert.sidescore,
        };
    }
};

/// I think it is easier to work with a direct bit mask for the flags in the move generator than some std bitmask class.
const GenFlags = u2;

const NO_FLAGS: GenFlags = 0;

const IS_TRY: GenFlags = 1 << 0;
const IS_CROSSGEN: GenFlags = 1 << 1;

const NOT_IS_TRY: GenFlags = ~IS_TRY;
const NOT_IS_CROSSGEN: GenFlags = ~IS_CROSSGEN;
