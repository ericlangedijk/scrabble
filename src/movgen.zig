//! The move generator
const std = @import("std");

const scrabble = @import("scrabble.zig");
const gaddag = @import("gaddag.zig");

const Gaddag = gaddag.Gaddag;
const Node = gaddag.Node;

const Direction = scrabble.Direction;
const Board = scrabble.Board;
const Square = scrabble.Square;
const MoveFlags = scrabble.MoveFlags;
const Move = scrabble.Move;

const MovGen = struct
{

    graph: *const Gaddag,
    board: Board,
    square_cache: [Board.LEN]SquareInfo,
    horizontal_anchors: std.BoundedArray(*SquareInfo, Board.LEN),
    vertical_anchors: std.BoundedArray(*SquareInfo, Board.LEN),
    generated_moves: std.ArrayList(Move),

    pub fn init(graph: *const Gaddag) MovGen
    {
        //const cache = [Board.LEN]SquareInfo;
        return MovGen
        {
            .graph = graph,
            .board = Board.init(), // copy or not?
            //.square cache =  std.mem.zeroes(SquareInfo),
            .horizontal_anchors = std.BoundedArray(*SquareInfo).init(Board.LEN),
            .vertical_anchors = std.BoundedArray(*SquareInfo).init(Board.LEN),
            .generated_moves = std.ArrayList(Move).initCapacity(128),
        };
    }

    fn preprocess(self: *MovGen) void
    {
        // TODO: clear anchors
        for (self.square_cache) |*info|
        {
            const is_anchor: bool = self.preprocess_square(info);
            if (is_anchor)
            {
                if (info.horz.flags.is_bow) self.horizontal_anchors.appendAssumeCapacity(info);
                if (info.vert.flags.is_bow) self.vertical_anchors.appendAssumeCapacity(info);
            }
        }
    }

    // fill square info + returns false if not usable as anchor horz or vert
    fn preprocess_square(self: *MovGen, curr: *SquareInfo) bool
    {
        const q: Square = curr.square;
        const h: Direction = .Horizontal;
        const v: Direction = .Horizontal;

        curr.offsetnode = null;
        curr.horz.excluded_chars = 1;
        curr.vert.excluded_chars = 1;
        curr.horz.included_chars = 0;
        curr.vert.included_chars = 0;
        curr.horz.offsetnode = &self.graph.root;
        curr.vert.offsetnode = &self.graph.root;
        curr.horz.anchorskip = 1;
        curr.vert.anchorskip = 1;
        curr.horz.flags.is_next_free = self.board.is_next_free(q, h);
        curr.vert.flags.is_next_free = self.board.is_next_free(q, v);
        curr.horz.flags.is_prev_free = self.board.is_prev_free(q, h);
        curr.vert.flags.is_prev_free = self.board.is_prev_free(q, v);
        curr.horz.flags.has_next_square = scrabble.square_has_next(q, h);
        curr.vert.flags.has_next_square = scrabble.square_has_next(q, v);
        curr.horz.flags.has_prev_square = scrabble.square_has_prev(q, h);
        curr.vert.flags.has_prev_square = scrabble.square_has_prev(q, v);
        curr.horz.flags.is_bow = self.board.is_bow(q, h);
        curr.vert.flags.is_bow = self.board.is_bow(q, v);
        curr.horz.flags.is_eow = self.board.is_eow(q, h);
        curr.vert.flags.is_eow = self.board.is_eow(q, v);

        // no offsetnode: return false
        if (!curr.horz.flags.is_bow and !curr.vert.flags.is_bow) return false;

        // horizontal
        const inf: *DirInfo = curr.get_info(h);
        const r = self.board.scan_forwards(q, h);
        if (r > q)
        {
            inf.anchorskip = r - q + 1;
        }
    }

    fn gen_moves(self: *MovGen) void
    {
        for(self.horizontal_anchors) |*squareinfo|
        {
            //const q: Square = squareinfo.square;
            const move: Move = Move.init();
            const flags: MoveFlags = MoveFlags {};
            self.gen(0, squareinfo.offsetnode, move, flags); // todo: add rack
            //Gen(0, SquareInfo^.HorzInfo.OffsetNode, EngineRack, Mov, horz_flags);
            //SquareInfo^.HorzInfo.Handled := True;
        }
    }

    //Dist: Integer; Node: PNode; const Rack: TEngineRack; const Mov: TMove; GenFlags: Word): Integer;
    fn gen(self: *MovGen, dist: u8, node: *Node, move: Move, flags: MoveFlags) void
    {
        _ = dist;
        _ = node;
        _ = move;
        _ = self;
        _ = flags;
    }

    fn go_on() void
    {

    }

    fn try_this() void
    {

    }

    fn gen_crossword() void
    {

    }

    fn record_move(self: *MovGen, move: *Move, flags: MoveFlags) void
    {
//        _ = move;
        _ = flags;
        try self.generated_moves.append(move.*) catch {};
    }

};

/// This cached thingy is to fly very fast over the board.
const DirInfo = struct
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

    offsetnode: ?*Node = null, // node to start with at first call
    excluded_chars: u32 = 0, // letters which are flagged as impossible during crosscheck. By default bit 0 is set.
    included_chars: u32 = 0, // letters which are flagged as ok during crosscheck.
    anchorskip: u8 = 0, // distance from anchor to the next empty square (default = 1)
    flags: Flags,

};

const SquareInfo = packed struct
{
    square: Square,
    horz: DirInfo,
    vert: DirInfo,

    fn get_info(self: *SquareInfo, comptime dir: Direction) *DirInfo
    {
        return switch(dir)
        {
            .Horizontal => &self.horz,
            .Vertical => &self.vert,
        };
    }
};

//const SquareCache = [Board.LEN]SquareInfo;