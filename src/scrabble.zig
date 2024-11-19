// basic structs for the game: settings, board, rack, move


// Dutch (26): ABCDEFGHIJKLMNOPQRSTUVWXYZ
// English (26): ABCDEFGHIJKLMNOPQRSTUVWXYZ
// Italian (26): ABCDEFGHIJKLMNOPQRSTUVWXYZ
// French (27): ABCDEFGHIJKLMNOPQRSTUVWXYZÉ
// Spanish (27): ABCDEFGHIJKLMNÑOPQRSTUVWXYZ
// Greek (24): ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ
// Portuguese (27): ABCDEFGHIJKLMNOPQRSTUVWXYZÇ
// Danish (29): ABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅ
// Swedish (29): ABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖ
// Norwegian (29): ABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅ
// German (30): ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜß

const std = @import("std");
const assert = std.debug.assert;

const utils = @import("utils.zig");

/// No unicode yet!
/// 8 bits, this is the real unicode char, max supported value = 255.\
/// We only support simple european languages for now.
pub const Char = u8;

/// 5 bits, this is our mapped value, max supported value = 31.
pub const CharCode = u5;

/// 32 bits easy typed bitmask, we can use everywhere to have sets of letters.
pub const CharCodeMask = std.bit_set.IntegerBitSet(32);

/// 9 bits, this is our square, scrabble board can have maximum 512 squares.
pub const Square = u9;

/// 4 bits, letter value, max value = 15,
pub const Value = u4;

//pub const EMPTYMASK: CharCodeMask = CharCodeMask.initEmpty();

pub const Orientation = enum
{
    Horizontal,
    Vertical,

    pub inline fn opp(comptime ori: Orientation) Orientation
    {
        return if (ori == .Horizontal) .Vertical else .Horizontal;
    }
};

pub const Direction = enum
{
    Forwards,
    Backwards,

    pub inline fn opp(comptime dir: Direction) Direction
    {
        return if (dir == .Forwards) .Backwards else .Forwards;
    }
};

/// Supported languages
pub const Language = enum
{
    Dutch,
    English,
    // quite a few here...
};


// comptime / monomorphization
pub const Consts = struct
{
    // max number of letters on rack
    // board width
    // board height
    // BWV en BLV?
};

pub const Settings = struct
{
    /// Our char table will look like this:\
    /// `0 a b c d`...\
    /// `0 1 2 3 4`...
    codes: [256]CharCode = std.mem.zeroes([256]CharCode), // = [_]CharCode ** 512,

    /// `0 1 2 3 4`...\
    /// `0 a b c d`...
    unicode_chars: [32]Char = std.mem.zeroes([32]Char),

    values: [32]u8 = std.mem.zeroes([32]u8),

    pub fn init(language: Language) !Settings
    {
        const def: *const LocalDef  = switch(language)
        {
            .Dutch => &DutchDef,
            .English => &EnglishDef,
        };

        assert(def.unique_letters.len == def.values.len);
        assert(def.unique_letters.len == def.distribution.len);

        //const def: *const LocalDef = &DutchDef;
        var result = Settings {};

        var code: CharCode = 1;
        for(def.unique_letters, def.values, def.distribution) |ch, value, amount|
        {
            const cc: Char = ch;
            result.codes[cc] = code;
            result.unicode_chars[code] = cc;
            result.values[code] = value;
            _ = amount;
            code += 1;
        }
        //std.debug.print("{any}\n", .{result});
        return result;
    }

    pub fn codepoint_to_charcode(self: *const Settings, u: u21) !CharCode
    {
        try check_unicode_char_supported(u);
        const c: Char = @truncate(u);
        return self.codes[c];
    }

    pub fn codepoint_to_charcode_unsafe(self: *const Settings, u: u21) CharCode
    {
        return self.codes[u];
    }

    pub fn codepoint_to_char(u: u21) !Char
    {
        try check_unicode_char_supported(u);
        return @truncate(u);
    }

    pub fn char_to_code(self: *const Settings, u: Char) CharCode
    {
        return self.codes[u];
    }

    pub fn code_to_char(self: *const Settings, c: CharCode) Char
    {
        return self.unicode_chars[c];
    }

    pub fn is_supported_unicode_char(c: u21) bool
    {
        return c <= 255;//511;
    }

    pub fn check_unicode_char_supported(c: u21) !void
    {
        //if (std.unicode.)
        if (!is_supported_unicode_char(c))
        {
            std.debug.print("INVALID CHAR {}", .{c});
            return ScrabbleError.UnsupportedCharacter;
        }
    }

    pub fn lv(self: *const Settings, letter: Letter) u8
    {
        return if (!letter.is_blank) self.values[letter.charcode] else 0;
    }
};

const LocalDef = struct
{
    /// The array of unique letters as a unicode string
    unique_letters: []const u8,
    /// The value of each tile
    values: []const u8,
    /// The amount of each tile
    distribution: []const u8,
    /// The number of blanks
    blanks: u8,
};

const DutchDef: LocalDef = LocalDef
{
    .unique_letters = "abcdefghijklmnopqrstuvwxyz",
    .values       = &.{1,  3,  5,  2,  1,  4,  3,  4,  1,  4,  3,  3,  3,  1,  1,  3, 10,  2,  2,  2,  4,  4,  5,  8,  8,  4},
    .distribution = &.{6,  2,  2,  5, 18,  2,  3,  2,  4,  2,  3,  3,  3, 10,  6,  2,  1,  5,  5,  5,  3,  2,  2,  1,  1,  2},
    .blanks = 2,
};

const EnglishDef: LocalDef = LocalDef
{
    .unique_letters = "abcdefghijklmnopqrstuvwxyz",
    .values       = &.{1,  3,  3,  2,  1,  4,  2,  4,  1,  8,  5,  1,  3,  1,  1,  3, 10,  1,  1,  1,  1,  4,  4,  8,  4, 10},
    .distribution = &.{9,  2,  2,  4, 12,  2,  3,  2,  9,  1,  1,  4,  2,  6,  8,  2,  1,  6,  4,  6,  4,  2,  2,  1,  2,  1},
    .blanks = 2,
};

const Tile = struct
{
    character: Char,
    code: CharCode,
    value: Value,
};

/// For Board and Move
pub const Letter = packed struct
{
    charcode: CharCode,
    is_blank: bool,
};

pub const Rack = struct
{
    pub const EMPTY = Rack.init();

    letters: std.BoundedArray(CharCode, 7),
    blanks: u3, // max blanks = 7

    pub fn init() Rack
    {
        return std.mem.zeroes(Rack);
    }

    /// Convenience function.
    pub fn init_string(settings: *const Settings, string: []const u8) !Rack
    {
        var rack: Rack = EMPTY;
        for (string) |cp|
        {
            const cc =  try settings.codepoint_to_charcode(cp);
            rack.add(cc);
        }
        return rack;
    }

    pub fn add(self: *Rack, cc: CharCode) void
    {
        self.letters.appendAssumeCapacity(cc);
    }

    /// Add a normal charcode
    pub fn add_charcode(self: *Rack, cc: CharCode) void
    {
        self.letters.appendAssumeCapacity(cc);
    }

    /// return new rack
    pub fn ret_remove(self: Rack, idx: usize) Rack
    {
        var rack = self;
        _ = rack.letters.swapRemove(idx);
        return rack;
    }

    /// return new rack
    pub fn ret_remove_blank(self: Rack) Rack
    {
        assert(self.blanks > 0);
        var rack = self;
        rack.blanks -= 1;
        return rack;
    }
};

pub const Move = struct
{
    pub const EMPTY: Move = Move.init();

    letters: std.BoundedArray(MoveLetter, 7), // TODO: make 7 comptime global
    score: u32,
    //flags: MoveFlags,
    //count: u8, // the number of letters played. must match letters.
    anchor: Square, // initialized in engine and only used by engine
    anchor_skip: u8, // initialized in engine and only used by engine

    pub fn init() Move
    {
        return std.mem.zeroes(Move);
    }

    pub fn count(self: *Move) u8
    {
        return self.letters.count();
    }

    pub fn sort() void
    {

    }

    pub fn add(self: *Move, cc: CharCode, is_blank: bool, square: Square) void
    {
        self.letters.appendAssumeCapacity(MoveLetter.init(cc, is_blank, square));
    }

    pub fn ret_add(self: Move, cc: CharCode, is_blank: bool, square: Square) Move
    {
        var move: Move = self;
        move.add(cc, is_blank, square);
        return move;
    }

    pub fn init_with_anchor(anchor: Square) Move
    {
        return Move
        {
            .letters = std.mem.zeroes(MoveLetter),
            .score = 0,
            .anchor = anchor,
            //.flags
        };
    }

};

/// 16 bits
pub const MoveLetter = packed struct
{
    letter: Letter,
    square: Square = 0, // 9 bits

    pub fn init(cc: CharCode, is_blank: bool, square: Square) MoveLetter
    {
        return MoveLetter
        {
            .letter = Letter {.charcode = cc, .is_blank = is_blank },
            .square = square,
        };
    }
};

pub const BoardLetter = packed struct
{
    pub const EMPTY: BoardLetter = BoardLetter {};

    letter: Letter,
    //charcode: CharCode = 0, // 5 bits
    //is_blank: bool = false, // 1 bit
    is_engine_temp: bool = false, // 1 bit

    pub fn init(charcode: CharCode) BoardLetter
    {
        return BoardLetter
        {
            .letter = Letter {.charcode = charcode, .is_blank = false }
            //.is_blank = false,
            //.is_engine_temp = false,
        };
    }

    pub fn is_empty(self: BoardLetter) bool
    {
        return self.letter.charcode == 0;
    }

    pub fn is_filled(self: BoardLetter) bool
    {
        return self.letter.charcode != 0;
    }
};

/// Fixed standard 15 x 15 scrabble board.
pub const Board = struct
{
    pub const SIZE: usize = 15;
    pub const LEN: usize = 225;
    pub const STARTSQUARE = 112;

    //pub const ALL_SQUARES

    /// Board word values.
    pub const BWV: [LEN]u8 =
    .{
        3,1,1,1,1,1,1,3,1,1,1,1,1,1,3,
        1,2,1,1,1,1,1,1,1,1,1,1,1,2,1,
        1,1,2,1,1,1,1,1,1,1,1,1,2,1,1,
        1,1,1,2,1,1,1,1,1,1,1,2,1,1,1,
        1,1,1,1,2,1,1,1,1,1,2,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        3,1,1,1,1,1,1,2,1,1,1,1,1,1,3,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,2,1,1,1,1,1,2,1,1,1,1,
        1,1,1,2,1,1,1,1,1,1,1,2,1,1,1,
        1,1,2,1,1,1,1,1,1,1,1,1,2,1,1,
        1,2,1,1,1,1,1,1,1,1,1,1,1,2,1,
        3,1,1,1,1,1,1,3,1,1,1,1,1,1,3
    };

    /// Board letter values.
    pub const BLV: [LEN]u8 =
    .{
        1,1,1,2,1,1,1,1,1,1,1,2,1,1,1,
        1,1,1,1,1,3,1,1,1,3,1,1,1,1,1,
        1,1,1,1,1,1,2,1,2,1,1,1,1,1,1,
        2,1,1,1,1,1,1,2,1,1,1,1,1,1,2,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,3,1,1,1,3,1,1,1,3,1,1,1,3,1,
        1,1,2,1,1,1,2,1,2,1,1,1,2,1,1,
        1,1,1,2,1,1,1,1,1,1,1,2,1,1,1,
        1,1,2,1,1,1,2,1,2,1,1,1,2,1,1,
        1,3,1,1,1,3,1,1,1,3,1,1,1,3,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        2,1,1,1,1,1,1,2,1,1,1,1,1,1,2,
        1,1,1,1,1,1,2,1,2,1,1,1,1,1,1,
        1,1,1,1,1,3,1,1,1,3,1,1,1,1,1,
        1,1,1,2,1,1,1,1,1,1,1,2,1,1,1
    };

    settings: *const Settings,
    squares: [LEN]BoardLetter,

    pub fn init(settings: *const Settings) Board
    {
        return Board
        {
            .settings = settings,
            .squares = std.mem.zeroes([LEN]BoardLetter),
            //.squares = try allocator.alloc(BoardLetter, 225),
        };
    }

    pub fn get_ptr(self: *Board, q: Square) *BoardLetter
    {
        return &self.squares[q];
    }

    pub fn get(self: *Board, q: Square) BoardLetter
    {
        return self.squares[q];
    }

    pub fn set(self: *Board, q: Square, char: u21) void
    {
        const charcode = self.settings.codepoint_to_charcode(char) catch return;
        self.squares[q] = BoardLetter.init(charcode);
    }

    pub fn is_start_position(self: *const Board) bool
    {
        return self.is_empty(STARTSQUARE);
    }

    // square has no occupied letter to the right / bottom
    pub fn is_next_free(self: *const Board, q: Square, comptime orientation: Orientation, comptime direction: Direction) bool
    {
        return if(next_square(q, orientation, direction)) |t| self.is_empty(t) else true;
    }

    // pub fn is_prev_free(self: *const Board, q: Square, comptime dir: Direction) bool
    // {
    //     _ = self; _ = q; _ = dir;
    //     return false; //return !square_has_prev(q, dir) or self.squares[prev_square(q, dir)].is_empty();
    // }

    pub fn is_bow(self: *const Board, q: Square, comptime orientation: Orientation) bool
    {
        return self.is_filled(q) and self.is_next_free(q, orientation, .Backwards);
    }

    pub fn is_eow(self: *const Board, q: Square, comptime orientation: Orientation) bool
    {
        return self.is_filled(q) and self.is_next_free(q, orientation, .Forwards);
    }

    fn is_empty(self: *const Board, q: Square) bool
    {
        return self.squares[q].is_empty();
    }

    fn is_filled(self: *const Board, q: Square) bool
    {
        return !self.squares[q].is_empty();
    }

    /// TODO for scanning we could also have reversed mem slices etc.
    pub fn letter_iterator(self: *const Board, square: Square, comptime orientation: Orientation, comptime direction: Direction, comptime inclusive: bool) BoardLetterIterator(orientation, direction, inclusive)
    {
        return BoardLetterIterator(orientation, direction, inclusive).init(self, square);
    }
};

fn BoardLetterIterator(comptime orientation: Orientation, comptime direction: Direction, comptime inclusive: bool) type
{
    return struct
    {
        const Self = @This();

        board: *const Board,
        startsquare: Square,
        square: Square,
        is_first: bool,

        pub fn init(board: *const Board, square: Square) Self
        {
            return Self
            {
                .board = board,
                .startsquare = square,
                .square = square,
                .is_first = true,
            };
        }

        pub fn next(it: *Self) ?MoveLetter
        {
            if (inclusive)
            {
                if (it.is_first)
                {
                    it.is_first = false;
                    const bl = it.board.squares[it.startsquare];
                    return if (bl.is_empty()) null else MoveLetter { .letter = bl.letter, .square = it.startsquare };
                }
            }

            const t = get_next(it.square) orelse return null;
            it.square = t;
            //std.debug.print("scan {},", .{t});
            const bl = it.board.squares[t];
            return if (bl.is_filled()) MoveLetter { .letter = bl.letter, .square = t } else null;
        }

        pub fn reset(it: *Self) void
        {
            it.square = it.startsquare;
            it.is_first = true;
        }

        pub fn current_square(it: *Self) Square
        {
            return it.square;
        }

        pub fn peek_end() ?MoveLetter
        {
            return null;
        }

        // pub fn peek_end(it: *Self) ?MoveLetter
        // {
        //     var q = it.startsquare;
        //     if (it.board.squares[q].is_empty()) return null;

        //     while (get_next(q)) |r|
        //     {
        //         const bl = it.board.squares[r];
        //         //if (bl.is_empty()) return null;
        //         q = get_next(q) orelse return MoveLetter { .charcode = bl.charcode, .is_blank = bl.is_blank, .square = q };
        //         //if (!bl.is_empty()) return MoveLetter { .charcode = bl.charcode, .is_blank = bl.is_blank, .square = t };
        //     }
        // }

        fn get_next(q: Square) ?Square
        {
            return next_square(q, orientation, direction);
        }

        //fn next
    };
}

pub fn square_x(q: Square) u9
{
    return q % 15;
}

pub fn square_y(q: Square) u9
{
    return q / 15;
}

// pub fn square_has_next(q: Square, comptime orientation: Orientation, comptime direction: Direction) bool
// {
//     return switch (orientation)
//     {
//         .Horizontal =>
//         {
//             if (direction == .Forwards) square_x(q) < 14,
//         },
//         .Vertical =>
//         {
//             q < 210,
//         }
//     };
// }

// pub fn square_has_next(q: Square,  comptime direction: Direction) bool
// {
//     return switch (direction)
//     {
//         .Horizontal => square_x(q) < 14,
//         .Vertical => q < 210,
//     };
// }

// pub fn square_has_prev(q: Square, comptime direction: Direction) bool
// {
//     return switch (direction)
//     {
//         .Horizontal => square_x(q) > 0,
//         .Vertical => q > 14,
//     };
// }

pub fn square_has_next(q: Square, comptime orientation: Orientation, comptime direction: Direction) bool
{
    return next_square(q, orientation, direction) != null;
}

pub fn next_square(q: Square, comptime orientation: Orientation, comptime direction: Direction) ?Square
{
    switch (orientation)
    {
        .Horizontal =>
        {
            switch (direction)
            {
                .Forwards =>
                {
                    return if (square_x(q) < 14) q + 1 else null;
                },
                .Backwards =>
                {
                   // std.debug.print("backwards?? {} squarex {}\n", .{q, square_x(q)});
                    return if (square_x(q) > 0) q - 1 else null;
                },
            }
        },
        .Vertical =>
        {
            switch (direction)
            {
                .Forwards =>
                {
                    return if (square_y(q) < 14) q + 15 else null;
                },
                .Backwards =>
                {
                    return if (square_y(q) > 0) q - 15 else null;
                },
            }

        },
    }
    //return if (square_has_next(q, orientation, direction)) q + 1 else null;
}

// const FieldFlag = packed struct
// {
//     has_left_neight: bool,
//     has_right: bool,
//     has_upper: bool,
//     has_lower: bool,
// };

// const fieldflags



pub const ScrabbleError = error
{
    UnsupportedLanguage,
    UnsupportedCharacter,
    GaddagBuildError,
    GaddagValidationFailed,
};

/// Move must be sorted by square and legal.
/// TODO: add comptime is_first_move so that we do not have to check boardletters in that case.
///       check move is sorted (or do that outside)
pub fn calculate_score(settings: *const Settings, board: *const Board, move: Move, comptime orientation: Orientation) u32
{
    if (move.letters.len == 0) return 0;
    const opp: Orientation = orientation.opp();
    const delta: u9 = if (orientation == .Horizontal) 1 else 15;
    const my_first_square: Square = move.letters.get(0).square;
    const my_last_square: Square = move.letters.get(move.letters.len - 1).square;
    var word_mul: u32 = 1;
    var my_score: u32 = 0;
    var cross_score: u32 = 0;
    //var word_start: Square = move.letters.get(0).square;
    //var word_end: Square = word_start;

    // scan board letters "outside" move. update myscore + wordstart + wordend
    var it1 = board.letter_iterator(my_first_square, orientation, .Backwards, false);
    while (it1.next()) |B|
    {
        my_score += settings.lv(B.letter);
        //word_start = B.square;
    }
    var it2 = board.letter_iterator(my_last_square, orientation, .Forwards, false);
    while (it2.next()) |B|
    {
        my_score += settings.lv(B.letter);
        // = B.square;
    }

    // played letters + board letters "inside" move
    var q = my_first_square;
    var idx: u8 = 0;
    while (q <= my_last_square)
    {
        const boardletter =  board.squares[q];
        if (boardletter.is_filled())
        {
            my_score += settings.lv(boardletter.letter);
        }
        else
        {
            const moveletter = move.letters.get(idx);
            idx += 1;
            const boardmul = Board.BWV[q];
            const lettermul = Board.BLV[q];
            word_mul *= boardmul;
            my_score += lettermul * settings.lv(moveletter.letter);
            var sidescore: u32 = 0;
            var it3 = board.letter_iterator(q, opp, .Backwards, false);
            while (it3.next()) |B| sidescore += settings.lv(B.letter);
            var it4 = board.letter_iterator(q, opp, .Backwards, false);
            while (it4.next()) |B| sidescore += settings.lv(B.letter);
            if (sidescore > 0)
            {
                sidescore += lettermul * settings.lv(moveletter.letter);
                sidescore *= boardmul;
                cross_score += sidescore;
            }
        }
        q += delta;
    }

    var score = word_mul * my_score + cross_score;
    if (move.letters.len == 7) score += 50;
    return score;
}
