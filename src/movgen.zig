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

const MoveStoredEvent = fn(move: *const Move) void; // TODO: we need context.

/// A fast movegenerator. 3.2 million moves per second measured.\
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

    /// Process each anchor square.
    fn process_anchors(self: *MovGen, board: *const Board, rack: *const Rack) void
    {
        const root: *const Node = self.graph.get_rootnode();

        // horz
        for (Board.ALL_SQUARES) |square|
        {
            if (!board.is_eow(square, .Horizontal)) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), 0, .Horizontal, .Backwards);
            inf.mark_as_processed(.Horizontal);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }

        // vert
        for (Board.ALL_SQUARES) |square|
        {
            if (!board.is_eow(square, .Vertical)) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), 0, .Vertical, .Backwards);
            inf.mark_as_processed(.Vertical);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }

        // horz crosswords
        for (Board.ALL_SQUARES) |square|
        {
            if (!board.is_crossword_anchor(square, .Horizontal)) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), IS_CROSSGEN, .Horizontal, .Backwards);
            inf.mark_as_processed_by_crossword(.Horizontal);
            inf.mark_as_processed(.Horizontal);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }

        // vert crosswords
        for (Board.ALL_SQUARES) |square|
        {
            if (!board.is_crossword_anchor(square, .Vertical)) continue;
            const inf: *SquareInfo = &self.squareinfo[square];
            self.gen(board, square, root, rack, &Move.init_with_anchor(square), IS_CROSSGEN, .Vertical, .Backwards);
            inf.mark_as_processed_by_crossword(.Vertical);
            inf.mark_as_processed(.Vertical);
            if (self.movelist.items.len >= MAX_MOVES) return;
        }
    }

    /// The key method: with board letters just go on, otherwise try letters from the rack and *then* go on.
    fn gen(self: *MovGen, board: *const Board, square: Square, inputnode: *const Node, rack: *const Rack, move: *const Move, comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction) void
    {
        const inf = &self.squareinfo[square];
        if (inf.is_processed(ori)) return;
        if (flags & IS_CROSSGEN != 0 and inf.is_processed_by_crossword(ori)) return;

        if (board.get_letter(square)) |boardletter|
        {
            const node: ?*const Node = self.graph.find_node(inputnode, boardletter.charcode);
            self.go_on(board, square, boardletter, node, rack, move, flags & NOT_IS_TRY, ori, dir);
        }
        else
        {
            // Try rack letters. Maintain a trymask, preventing trying the same letter on the same square more than once.
            // "Fake initialize" the trymask with already disabled charcodes.
            if (rack.letters.len > 0)
            {
                var trymask: CharCodeMask = inf.get_excluded_mask(ori); // required filter! (see crosscheck)
                for (rack.letters.slice(), 0..) |rackletter, idx|
                {
                    if (trymask.isSet(rackletter)) continue;
                    trymask.set(rackletter);
                    const trynode: *const Node = self.graph.find_node(inputnode, rackletter) orelse continue;
                    const tryletter: Letter = Letter.normal(rackletter);
                    const tryrack: Rack = rack.removed(idx);
                    const trymove: Move = move.added(tryletter, square, dir);
                    self.go_on(board, square, tryletter, trynode, &tryrack, &trymove, flags | IS_TRY, ori, dir);
                }
            }
            // Try blanks.
            if (rack.blanks > 0)
            {
                const excluded_mask: CharCodeMask = inf.get_excluded_mask(ori); // required filter! (see crosscheck)
                const children = self.graph.get_children(inputnode);
                for (children) |*child|
                {
                    if (child.data.code == 0) continue; // important: skip bow nodes
                    if (excluded_mask.isSet(child.data.code)) continue;
                    const tryletter: Letter = Letter.blank(child.data.code);
                    const tryrack: Rack = rack.removed_blank();
                    const trymove: Move = move.added(tryletter, square, dir);
                    self.go_on(board, square, tryletter, child, &tryrack, &trymove, flags | IS_TRY, ori, dir);
                }
            }
        }
    }

    /// Depending on orientation and direction go to the next square. Note that `go_on` always has to be called from `gen`, even if `inputnode` is null.\
    /// We can have a pending move that has to be stored.
    fn go_on(self: *MovGen, board: *const Board, square: Square, letter: Letter, inputnode: ?*const Node, rack: *const Rack, move: *const Move, comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction) void
    {
        assert(letter.is_filled());
        assert(!self.squareinfo[square].is_processed(ori)); // this should never happen. tracked and confirmed.

        // Check dead end or check store pending move.
        if (!self.try_this(board, square, letter, inputnode, move, flags, ori, dir)) return;

        const node: *const Node = inputnode orelse return;

        if (scrabble.next_square(square, ori, dir)) |nextsquare|
        {
            self.gen(board, nextsquare, node, rack, move, flags, ori, dir);
        }

        // Magic recursive turnaround: we go back to the anchor square (eow) (or the special crossword anchor). and check we can put a letter after that. Switch to bow!
        if (dir == .Backwards)
        {
            if (board.is_next_free(square, ori, dir) and board.is_next_free(move.anchor, ori, .Forwards))
            {
                const after_anchor: Square = scrabble.next_square(move.anchor, ori, .Forwards) orelse return; // we can be at the board border.
                const anchornode: *const Node = self.graph.get_bow(node) orelse return;
                self.gen(board, after_anchor, anchornode, rack, move, flags, ori, .Forwards);
            }
        }
    }

    /// If we have a dead end (crossword error) the result is false. Otherwise check store pending move.
    fn try_this(self: *MovGen, board: *const Board, square: Square, tryletter: Letter, inputnode: ?*const Node, move: *const Move, comptime flags: GenFlags, comptime ori: Orientation, comptime dir: Direction) bool
    {
        if (move.letters.len == 0) return true;
        const node: *const Node = inputnode orelse return true; // TODO: still wondering if i am missing pending moves.
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

    /// Cross check using (and filling) cached info. The caching of excluded and included letters saves a *lot* of processing.
    /// Note that the excluded letters are already pre-checked during triesin `gen`.
    fn cross_check(self: *MovGen, board: *const Board, square: Square, trycharcode: CharCode, comptime ori: Orientation) bool
    {
        const inf: *SquareInfo = &self.squareinfo[square];
        assert(!inf.is_charcode_excluded(trycharcode, ori)); // this should never happen. tracked and confirmed.
        if (inf.is_charcode_included(trycharcode, ori)) return true;
        const ok: bool = self.do_crosscheck(board, square, trycharcode, ori);
        if (ok) inf.mark_charcode_included(trycharcode, ori) else inf.mark_charcode_excluded(trycharcode, ori);
        return ok;
    }

    /// Checks valid crossword for the *opposite* orientation of `ori`.
    pub fn do_crosscheck(self: *MovGen, board: *const Board, q: Square, trycharcode: CharCode,  comptime ori: Orientation) bool
    {
        // example: ". . i n s t _ n c e . ." (only "a" will succeed).
        const opp: Orientation = ori.opp();
        const check_backwards: bool = board.has_filled_neighbour(q, opp, .Backwards);
        const check_forwards: bool = board.has_filled_neighbour(q, opp, .Forwards);

        // Nothing to do.
        if (!check_backwards and !check_forwards) return true;

        // Find root node of the letter (on the "_" square).
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

        if (flags & IS_CROSSGEN != 0 and move.letters.len == 1) return;

        var storedmove: Move = move.*;

        if (!is_first_move)
        {
            // Unfortunately we have to do a little filtering here to prevent duplicate one-letter moves. These are quite rare.
            if (move.letters.len == 1)
            {
                const first = move.first();
                const inf = &self.squareinfo[first.square];
                if (inf.is_one_mask_set(first.letter)) return;
                inf.mark_one_mask_set(first.letter);
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
    fn gen_rack_moves(self: *MovGen, board: *const Board, depth: u8, q: Square, inputnode: ?*const Node, rack: *const Rack, move: Move) void
    {
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
                    const passnode: ?*const Node = if (depth > 0) childnode else graph.get_bow(childnode);
                    self.gen_rack_moves(board, depth + 1, q + 1, passnode, &rack.removed(i), newmove);
                }
            }
        }

        // Try blanks.
        if (rack.blanks > 0)
        {
            const children = graph.get_children(node);
            for(children) |*childnode|
            {
                const charcode = childnode.data.code;
                if (charcode == 0) continue;
                const newmove: Move = move.ret_add(charcode, true, q);
                if (childnode.data.is_eow) self.store_rack_moves(board, newmove);
                const passnode: ?*const Node = if (depth > 0) childnode else graph.get_bow(childnode);
                self.gen_rack_moves(board, depth + 1, q + 1, passnode, &rack.removed_blank(), newmove);
            }
        }
    }

    /// Dedicated routine for rack generated moves, shifting and rotating.
    fn store_rack_moves(self: *MovGen, board: *const Board, move: Move) void
    {
        // TODO: validate board
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


/// During processing this struct is updated for speedups, preventing duplicate moves. The functions are just easy-to-read additions.
pub const SquareInfo = struct
{
    const EMPTY: SquareInfo = SquareInfo.init_empty();

    const EMPTY_ONEMASK = std.bit_set.IntegerBitSet(64).initEmpty();

    pub const OrientedInfo = struct
    {
        /// Cache for invalid letters during croschecks.
        excluded_charcodes: CharCodeMask = CharCodeMask.initEmpty(),
        /// Cache for valid letters during croschecks.
        included_charcodes: CharCodeMask = CharCodeMask.initEmpty(),
        /// Flag when anchor is processed.
        is_processed: bool = false,
        /// Flag when crossword anchor is processed.
        is_processed_by_crossword: bool = false,
    };

    // Horizontal info
    horz: OrientedInfo,
    // Vertical info
    vert: OrientedInfo,
    /// Cache for one-letter moves, preventing duplicates. Note that it is including the blank, so 64 bits needed.
    one_mask: std.bit_set.IntegerBitSet(64) = EMPTY_ONEMASK,

    fn init_empty() SquareInfo
    {
        return SquareInfo { .horz = OrientedInfo {}, .vert = OrientedInfo {}, .one_mask = EMPTY_ONEMASK };
    }

    fn is_processed(self: *const SquareInfo, comptime ori: Orientation) bool
    {
        return switch (ori)
        {
            .Horizontal => self.horz.is_processed,
            .Vertical => self.vert.is_processed,
        };
    }

    fn mark_as_processed(self: *SquareInfo, comptime ori: Orientation) void
    {
        switch (ori)
        {
            .Horizontal => self.horz.is_processed = true,
            .Vertical => self.vert.is_processed = true,
        }
    }
    fn is_processed_by_crossword(self: *const SquareInfo, comptime ori: Orientation) bool
    {
        return switch (ori)
        {
            .Horizontal => self.horz.is_processed_by_crossword,
            .Vertical => self.vert.is_processed_by_crossword,
        };
    }

    fn mark_as_processed_by_crossword(self: *SquareInfo, comptime ori: Orientation) void
    {
        return switch (ori)
        {
            .Horizontal => self.horz.is_processed_by_crossword = true,
            .Vertical => self.vert.is_processed_by_crossword = true,
        };
    }

    fn is_one_mask_set(self: *const SquareInfo, letter: Letter) bool
    {
        return self.one_mask.isSet(letter.as_u6());
    }

    fn mark_one_mask_set(self: *SquareInfo, letter: Letter) void
    {
        self.one_mask.set(letter.as_u6());
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
};

/// I think it is easier to work with a direct bit mask for the flags in the move generator than some std bitmask class.
const GenFlags = u2;

const IS_TRY: GenFlags = 1 << 0;
const IS_CROSSGEN: GenFlags = 1 << 1;

const NOT_IS_TRY: GenFlags = ~IS_TRY;
const NOT_IS_CROSSGEN: GenFlags = ~IS_CROSSGEN;

