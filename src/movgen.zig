//! The move generator
const std = @import("std");

const scrabble = @import("scrabble.zig");
const gaddag = @import("gaddag.zig");

const Settings = scrabble.Settings;
const Graph = gaddag.Graph;
const Node = gaddag.Node;
const CharCode = scrabble.CharCode;

const Orientation = scrabble.Orientation;
const Direction = scrabble.Direction;
const Board = scrabble.Board;
const BoardLetter = scrabble.BoardLetter;
const Rack = scrabble.Rack;
const Square = scrabble.Square;
const Move = scrabble.Move;
const Letter = scrabble.Letter;
const CharCodeMask = scrabble.CharCodeMask;

const GenFlags = u4;

const GF_IS_TRY: u4 = 1 << 0;
const GF_IS_CROSSWORD: u4 = 1 << 1;
const GF_BACKWARDS: u4 = 1 << 2;

pub const MovGen = struct
{
    allocator: std.mem.Allocator,
    settings: *const Settings,
    graph: *Graph,
    generated_moves: std.ArrayList(Move),
    square_cache: [Board.LEN]SquareInfo,
    horizontal_anchors: std.ArrayList(*SquareInfo),
    vertical_anchors: std.ArrayList(*SquareInfo),

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings, graph: *Graph) !MovGen
    {
        return MovGen
        {
            .allocator = allocator,
            .settings = settings,
            .graph = graph,
            .generated_moves = try std.ArrayList(Move).initCapacity(allocator, 128),
            .square_cache = create_square_cache(),
            .horizontal_anchors = try std.ArrayList(*SquareInfo).initCapacity(allocator, Board.LEN),
            .vertical_anchors = try std.ArrayList(*SquareInfo).initCapacity(allocator, Board.LEN),
        };
    }

    pub fn deinit(self: *MovGen) void
    {
        self.generated_moves.deinit();
        self.horizontal_anchors.deinit();
        self.vertical_anchors.deinit();
    }

    pub fn create_square_cache() [Board.LEN]SquareInfo
    {
        var cache: [Board.LEN]SquareInfo = std.mem.zeroes([Board.LEN]SquareInfo);
        for(0..cache.len) |i|
        {
            cache[i].square = @intCast(i);
        }
        return cache;
    }

    pub fn generate_moves(self: *MovGen, board: *Board, rack: Rack) void
    {
        self.reset();

        if (board.is_start_position())
        {
            self.gen_rack_moves(0, Board.STARTSQUARE, self.graph.get_rootnode_ptr(), rack, Move.EMPTY);
        }
        else
        {
            self.preprocess(board);
            self.gen_moves(board, rack);
        }
    }

    fn reset(self: *MovGen) void
    {
        self.generated_moves.resize(0);
        self.horizontal_anchors.resize(0);
        self.vertical_anchors.resize(0);
    }

    /// Generate an anchorlist.
    pub fn preprocess(self: *MovGen, board: *Board) void
    {
        for (&self.square_cache) |*info|
        {
            const is_anchor: bool = self.preprocess_square(board, info);
            if (is_anchor)
            {
                if (info.horz.flags.is_bow) self.horizontal_anchors.appendAssumeCapacity(info);
                if (info.vert.flags.is_bow) self.vertical_anchors.appendAssumeCapacity(info);
            }
        }
    }

    /// Fill square info + returns false if not usable as anchor horz or vert.\
    /// Non-anchors are still processed to set some useful flags for each square.
    fn preprocess_square(self: *MovGen, board: *Board, curr: *SquareInfo) bool
    {
        const q: Square = curr.square;

        curr.horz.offsetnode = self.graph.get_rootnode();
        curr.vert.offsetnode = self.graph.get_rootnode();
        curr.horz.excluded_chars.mask = 1;
        curr.vert.excluded_chars.mask = 1;
        curr.horz.included_chars.mask = 0;
        curr.vert.included_chars.mask = 0;
        curr.horz.anchorskip = 1;
        curr.vert.anchorskip = 1;
        curr.horz.flags.is_next_free = board.is_next_free(q, .Horizontal, .Forwards);
        curr.vert.flags.is_next_free = board.is_next_free(q, .Vertical, .Forwards);
        curr.horz.flags.is_prev_free = board.is_next_free(q, .Horizontal, .Backwards);
        curr.vert.flags.is_prev_free = board.is_next_free(q, .Vertical, .Backwards);
        curr.horz.flags.has_next_square = scrabble.square_has_next(q, .Horizontal, .Forwards);
        curr.vert.flags.has_next_square = scrabble.square_has_next(q, .Vertical, .Forwards);
        curr.horz.flags.has_prev_square = scrabble.square_has_next(q, .Horizontal, .Backwards);
        curr.vert.flags.has_prev_square = scrabble.square_has_next(q, .Vertical, .Backwards);
        curr.horz.flags.is_bow = board.is_bow(q, .Horizontal);
        curr.vert.flags.is_bow = board.is_bow(q, .Vertical);
        curr.horz.flags.is_eow = board.is_eow(q, .Horizontal);
        curr.vert.flags.is_eow = board.is_eow(q, .Vertical);

        // no offsetnode: return false
        if (!curr.horz.flags.is_bow and !curr.vert.flags.is_bow) return false;

        // // horizontal
        //const horz: *OrientedInfo = curr.get(.Horizontal);
        // const r = self.board.scan_forwards(q, h);
        // if (r > q)
        // {
        //     inf.anchorskip = r - q + 1;
        // }
        return false;
    }

    /// Loop through all candidate anchors and process these.
    fn gen_moves(self: *MovGen, board: *Board, rack: Rack) void
    {
        //const horizontal_anchors = std.ArrayList(*SquareInfo).initCapacity(self.allocator, Board.LEN);
        //const vertical_anchors = std.ArrayList(*SquareInfo).initCapacity(self.allocator, Board.LEN);
        for(self.horizontal_anchors) |*squareinfo|
        {
            self.gen(board, 0, squareinfo.horz.offsetnode, squareinfo, rack, Move.EMPTY, 0, .Horizontal);
            squareinfo.horz.flags.is_handled = true;
        }
        for(self.vertical_anchors) |*squareinfo|
        {
            self.gen(board, 0, squareinfo.horz.offsetnode, squareinfo, rack, Move.EMPTY, 0, .Vertical);
            squareinfo.vert.flags.is_handled = true;
        }
    }

    // if the board is empty, we generate all horz moves starting from the centersquare h8, by creating all possible words.
    // at depth = 0 Node must be the Tree.Root and Q the centersquare of the board.
    // in AddRootMoves we make clones of the generated moves (rotated and shifted) with all possible squares which connect to the center square.
    pub fn gen_rack_moves(self: *MovGen, board: *Board, depth: u8, q: Square, inputnode: ?Node, rack: Rack, move: Move) void
    {
        const node = inputnode orelse return;
        if (node.count == 0) return;
        const graph = self.graph;

        // Try letters.
        var tried_mask: CharCodeMask = CharCodeMask.initEmpty();
        for (rack.letters.slice(), 0..) |rackletter, i|
        {
           if (tried_mask.isSet(rackletter)) continue;
           tried_mask.set(rackletter);
           if (graph.find_node(node, rackletter)) |childnode|
           {
               const newmove = move.ret_add(rackletter, false, q);
               if (childnode.data.is_eow) self.store_rack_move(board, newmove);
               const passnode = if (depth > 0) childnode else graph.get_bow(childnode);
               self.gen_rack_moves(board, depth + 1, q + 1, passnode, rack.ret_remove(i), newmove);
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
                const newmove = move.ret_add(charcode, true, q);
                if (childnode.data.is_eow) self.store_rack_move(board, newmove);
                const passnode = if (depth > 0) childnode else graph.get_bow(childnode);
                self.gen_rack_moves(board, depth + 1, q + 1, passnode, rack.ret_remove_blank(), newmove);
            }
        }
    }

    fn gen(self: *MovGen, board: *Board, dist: i8, node: Node, squareinfo: *SquareInfo, rack: Rack, move: Move, comptime flags: GenFlags, comptime orientation: Orientation) u32
    {
        const di = squareinfo.get(orientation);
        if (di.flags.is_handled) return 0;
        const q: Square = squareinfo.anchor + dist;
        const boardletter: BoardLetter = board.squares[q];

        var result: u32 = 0;

        // Follow the board. Even if there is no node, call go_on, because there can be a pending move.
        if (boardletter.is_filled())
        {
            const newnode = self.graph.find_node_ptr(node, boardletter.letter.charcode);
            return self.go_on(dist, squareinfo, boardletter.letter, rack, newnode, move, flags, orientation);
        }

        //const node: *Node = st.node orelse return result;
        if (node.count == 0) return result;

        // Try letters. Keep a mask (do not try duplicate letters).
        var try_mask = std.bit_set.IntegerBitSet(32).initEmpty();
        for (rack.letters) |rackletter|
        {
            const tryletter: Letter = Letter {.charcode = rackletter, .is_blank = false};// CharCode = rackletter;
            // Also cutoff excluded chars.
            if (try_mask.isSet(tryletter.charcode) or di.excluded_chars.isSet(tryletter.charcode)) continue;
            try_mask.set(tryletter);
            if (self.graph.find_node(node)) |newnode|
            {
                result += self.go_on(dist, squareinfo, tryletter, rack, newnode, move, flags | GF_IS_TRY, orientation);
            }
            // TODO: Generate crosswords at first try (when connected) and *only* if not already generating crosswords
        }

        // Try blanks.
        if (rack.blanks > 0)
        {
            const children = self.graph.get_children(node);
            for(children) |newnode|
            {
                const tryletter = Letter {.charcode = newnode.data.code, .is_blank = true };
                // skip bow-node, cutoff excluded chars (trycode 0 (bownode) is excluded by default)
                if (di.excluded_chars.isSet(tryletter.charcode)) continue;
                result += self.go_on(dist, squareinfo, tryletter, rack, newnode, move, flags | GF_IS_TRY, orientation);
                // TODO: Generate crosswords at first try (when connected) and *only* if not already generating crosswords
            }
        }
        return result;
    }

    // function TEngine.GoOn(SquareInfo: PSquareInfo; Dist: Integer; L: TLetter; const Rack: TEngineRack; NewNode: PNode; const Mov: TMove; GenFlags: Word): Integer;
    fn go_on(self: *MovGen, dist: i8, squareinfo: *SquareInfo, letter: Letter, rack: Rack, newnode: ?Node, move: Move, comptime flags: GenFlags, comptime orientation: Orientation) u32 // self: *MovGen, squareinfo: *SquareInfo, dist: u8, charcode: CharCode, rack: EngineRack, newnode: *Node, move: Move, flags: Move.Flags) u32
    {
        _ = self;
        _ = dist;
        _ = letter;
        _ = rack;
        _ = newnode;
        _ = move;
        _ = flags;

        const di = squareinfo.get(orientation);
        if (di.handled) return 0;

        //const newmove = move;
        //if (!self.try_this(st)) return 0;

        // result += recorded.

//        const newnode: *Node = st.node orelse return 0;

        // continue backwards
        // after that try switch direction: go forwards after anchor-end if this is a begin-of-word and if there is an empty square after the anchor-end


        //if (st.dist ==)
        // const dir: Direction = if (flags.is_gen_vertical) .Vertical else .Horizontal;
        // const di: *SquareInfo = squareinfo.get_info(dir);
        // if (di.flags.is_handled) return;
        // //var newmove = move; // we need a copy

        return 0;
    }

    // function TEngine.TryThis(SquareInfo: PSquareInfo; out Recorded: Integer; var Mov: TMove; NewNode: PNode; L: TLetter; GenFlags: Word): Boolean;
    fn try_this(self: *MovGen, board: *Board, squareinfo: *SquareInfo, recorded: *u32, move: Move, newnode: Node, letter: Letter, flags: GenFlags, comptime orientation: Orientation) bool //squareinfo: *SquareInfo, recorded: *u32, move: *Move, newnode: *Node, charcode: CharCode, flags: Move.Flags) bool
    {
        const is_try = flags & GF_IS_TRY != 0;
        recorded = 0;
        if (is_try and !self.cross_check(board, squareinfo, letter.charcode, orientation))
        {
            return false;
        }
        //const di = squareinfo.get(orientation);
        //const q: Square = squareinfo.square;

        //_ = recorded;
        //_ = squareinfo;
        //_ = self;
        //_ = dist;
        //_ = letter;
        //_ = rack;
        _ = newnode;
        _ = move;
        //_ = flags;
        //_ = self;

        //_ = orientation;
        // _ = charcode;
        // _ = recorded;
        // _ = move;
        // _ = newnode;
        // const dir: Direction = if (flags.is_gen_vertical) .Vertical else .Horizontal;
        // const di: *SquareInfo = squareinfo.get_info(dir);
        // const is_try: bool = flags.is_gen_try;
        // _ = di;
        // if (is_try)
        // {

        // }
        return false;
    }

    fn gen_opp() void
    {

    }

    fn cross_check(self: *MovGen, board: *Board, squareinfo: *SquareInfo, trycharcode: CharCode, comptime orientation: Orientation) bool
    {
        const inf: *OrientedInfo = squareinfo.get(orientation);
        // try cache (already processed somewhere)
        if (inf.included_chars.contains(trycharcode)) return true;
        if (inf.excluded_chars.contains(trycharcode)) return false;
        // otherwise check board / graph
        const ok: bool = self.do_crosscheck(board, squareinfo, trycharcode, orientation);
        if (ok == false) inf.excluded_chars.set(trycharcode) else inf.included_chars.set(trycharcode);
        return ok;
    }

    /// Checks valid crossword in the opposite orientation of `orientation`. The trycode is on the dot:\
    /// `_ _ I N S T . N C E _ _ `\
    ///  1. take the root child for `trycharcode`
    ///  2. backtrack board backwards (prefix) -> TSNI
    ///  3. check node is bow (at I)
    ///  4. forward to the right (suffix) -> NCE
    ///  5. check node is eow (at E)
    pub fn do_crosscheck(self: *MovGen, board: *Board, squareinfo: *SquareInfo, trycharcode: CharCode, comptime orientation: Orientation) bool
    {
        // TODO: the algorithm can maybe be simplified with slices.
        const q: Square = squareinfo.square;
        const opp: Orientation = orientation.opp();
        const inf: *OrientedInfo = squareinfo.get(opp);
        const check_forwards: bool = !inf.flags.is_next_free;
        const check_backwards: bool = !inf.flags.is_prev_free;
        if (!check_backwards and !check_forwards) return true;

        // find root char
        var node: Node = self.graph.find_node(self.graph.get_rootnode(), trycharcode) orelse return false;

        // scan prefix backwards
        if (check_backwards)
        {
            var it = board.letter_iterator(q, opp, .Backwards, false);
            while (it.next()) |boardletter| node = self.graph.find_node(node, boardletter.letter.charcode) orelse return false;
        }

        // If done, we reached the beginning of the word. Check is_bow and is_whole_word
        if (!check_forwards) return node.data.is_bow and node.data.is_whole_word;

        // Check bow and switch to suffix.
        node = self.graph.get_bow(node) orelse return false;

        // Scan suffix.
        if (check_forwards)
        {
            var it = board.letter_iterator(q, opp, .Forwards, false);
            while (it.next()) |boardletter| node = self.graph.find_node(node, boardletter.letter.charcode) orelse return false;
        }

        // Check eow
        return node.data.is_eow;
    }

    fn store_move(self: *MovGen) void
    {
        _ = self;


        //_ = st;
        //try self.generated_moves.append(move.*) catch {};
    }

    /// Dedicated routine for rack generated moves.
    fn store_rack_move(self: *MovGen, board: *Board, move: Move) void
    {


        std.debug.print("store move ", .{});
        for(move.letters.slice()) |let|
        {
            const char = self.settings.code_to_char(let.letter.charcode);
            if(let.letter.is_blank)
                std.debug.print("-{c} ", .{char})
                else std.debug.print("{c} ", .{char});
        }
        std.debug.print("---\n", .{});

        var new_move: Move = move;
        var timer: std.time.Timer = std.time.Timer.start() catch return;
        //for (0..100)|_|
        new_move.score = scrabble.calculate_score(self.settings, board, new_move, .Horizontal);
        const elapsed = timer.lap();

        std.debug.print("store move SCORE {} {} nanos\n", .{new_move.score, elapsed});

//        _ = self;
        //_ = move;
    }

};

/// This cached thingy is to fly very fast over the board.
const OrientedInfo = struct
{
    const Flags = packed struct
    {
        is_next_free: bool = false, // free or at border
        is_prev_free: bool = false, // free or at border
        is_bow: bool = false, // is this begin of a word?
        is_eow: bool = false, // is this end of a word?
        has_next_square: bool = false, // is there a next square?
        has_prev_square: bool = false, // is there a previous square?
        is_handled: bool = false, // square is handled: do not process again
        is_handled_by_one: bool = false, // square is handled for 1 letter move (only used horz)

        // free in both directions
        fn is_both_free(self: Flags) bool
        {
            return self.is_next_free and self.is_prev_free;
        }
    };

    /// Intitial node when processing the anchor.
    offsetnode: Node = Node.EMPTYNODE,
     // Mask for letters which are flagged as impossible during crosscheck. By default bit 0 is set.
    excluded_chars: CharCodeMask,
    /// Mask for letters which are flagged as ok during crosscheck.
    included_chars: CharCodeMask,
    /// Distance from anchor to the next empty square (default = 1)
    anchorskip: u8 = 0,
    flags: Flags,
};

const SquareInfo = struct
{
    square: Square,
    horz: OrientedInfo,
    vert: OrientedInfo,

    fn get(self: *SquareInfo, comptime orientation: Orientation) *OrientedInfo
    {
        return if (orientation == .Horizontal) &self.horz else &self.vert;
    }
};
