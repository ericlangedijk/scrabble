//! Basic structs for the scrabblegame like letters, settings, board, rack, move

// TODO: put in asserts for max values etc.

/// experimental comptime struct
const Sizes = struct
{
    unique_letter_count: u8, // max 63
    rack_count: u8, // max 8
    board_width: u8, // max 21
    board_height: u8, // max 21
};

//pub var CALLS: u64 = 0;

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

//pub var NEIGHBOURCALLS: u64 = 0;

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

pub const EMPTY_CHARCODE_MASK: CharCodeMask = CharCodeMask.initEmpty();

//pub const EMPTYMASK: CharCodeMask = CharCodeMask.initEmpty();

pub const Orientation = enum
{
    Horizontal,
    Vertical,

    pub inline fn opp(comptime ori: Orientation) Orientation
    {
        return if (ori == .Horizontal) .Vertical else .Horizontal;
    }

    pub inline fn delta(comptime ori: Orientation, comptime dim: Dim) u9
    {
        return if (ori == .Horizontal) 1 else dim.width;
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

pub const Settings = struct
{
    /// Our char table will look like this:\
    /// `0 a b c d`...\
    /// `0 1 2 3 4`...
    codes: [256]CharCode = std.mem.zeroes([256]CharCode), // TODO: make hashmap if too big
    /// `0 1 2 3 4`...\
    /// `0 a b c d`...
    unicode_chars: [32]Char = std.mem.zeroes([32]Char), // TODO: make bigger if needed -> this has impact on the whole system
    values: [32]u8 = std.mem.zeroes([32]u8), // TODO: make bigger if needed -> this has impact on the whole system
    distribution: [32]u8 = std.mem.zeroes([32]u8), // TODO: index #0 is abused for the number of blanks.
    blanks: u8 = 0,

    pub fn init(language: Language) !Settings
    {
        const def: *const LocalDef  = switch(language)
        {
            .Dutch => &DutchDef,
            .English => &EnglishDef,
        };

        assert(def.unique_letters.len == def.values.len);
        assert(def.unique_letters.len == def.distribution.len);

        var result = Settings {};

        var code: CharCode = 1;
        for(def.unique_letters, def.values, def.distribution) |ch, value, amount|
        {
            const cc: Char = ch;
            result.codes[cc] = code;
            result.unicode_chars[code] = cc;
            result.values[code] = value;
            result.distribution[code] = amount;
            code += 1;
        }
        result.blanks = def.blanks;
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
        if (!is_supported_unicode_char(c))
        {
            set_last_error("invalid char encountered");
            //std.debug.print("INVALID CHAR {}", .{c});
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
    /// The amounts of each tile
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

/// Core letter
pub const Letter = packed struct
{
    const EMPTY: Letter = Letter.init(0, false);

    charcode: CharCode = 0,
    is_blank: bool = false,

    pub fn init(charcode: CharCode, comptime is_blank: bool) Letter
    {
        return Letter { .charcode = charcode, .is_blank = is_blank };
    }

    pub fn normal(charcode: CharCode) Letter
    {
        return Letter.init(charcode, false);
    }

    pub fn blank(charcode: CharCode) Letter
    {
        return Letter.init(charcode, true);
    }

    pub fn is_empty(self: Letter) bool
    {
        return self.charcode == 0;
    }

    pub fn is_filled(self: Letter) bool
    {
        return self.charcode != 0;
    }
};

/// 16 bits
pub const MoveLetter = packed struct
{
    letter: Letter,
    square: Square = 0,

    pub fn init(cc: CharCode, is_blank: bool, square: Square) MoveLetter
    {
        return MoveLetter
        {
            .letter = Letter {.charcode = cc, .is_blank = is_blank },
            .square = square,
        };
    }
};

/// TODO: asserts on max 7 including blanks.
pub const Rack = struct
{
    pub const EMPTY = Rack.init();

    letters: std.BoundedArray(CharCode, 7),
    blanks: u3,

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

    pub fn count(self: *const Rack) u8
    {
        return self.letters.len + self.blanks;
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

    pub fn add_letter(self: *Rack, letter: Letter) void
    {
        if (letter.is_blank) self.blanks += 1 else self.add(letter.charcode);
    }

    pub fn remove(self: *Rack, idx: usize) void
    {
        assert(self.letters.len > idx);
        _ = self.letters.swapRemove(idx);
    }

    /// Return new rack. used by engine
    pub fn removed(self: Rack, idx: usize) Rack
    {
        assert(self.letters.len > idx);
        var rack = self;
        _ = rack.letters.swapRemove(idx);
        return rack;
    }

    /// Return new rack. used by engine
    pub fn removed_blank(self: Rack) Rack
    {
        assert(self.blanks > 0);
        var rack = self;
        rack.blanks -= 1;
        return rack;
    }

    pub fn remove_letter(self: *Rack, moveletter: MoveLetter) void
    {
        if (moveletter.letter.is_blank)
        {
            self.blanks -= 1;
        }
        else
        {
            for (self.letters.slice(), 0..) |rackletter, idx|
            {
                if (rackletter == moveletter.letter.charcode)
                {
                    self.remove(idx);
                    break;
                }
            }
        }
    }
};

pub const Move = struct
{
    pub const EMPTY: Move = Move.init();

    pub const Flags = packed struct
    {
        is_horizontally_generated: bool = false,
        is_crossword_generated: bool = false,
    };

    letters: std.BoundedArray(MoveLetter, 7), // TODO: make 7 comptime global
    /// Even on a 21 x 21 superscrabble board this u16 should be enough for ridiculous high scores (when we have reasonable board- and lettervalues).
    score: u16 = 0,
    /// The anchor of the move is (1) an eow board letter or (2) an empty square when generated as crossword.
    anchor: Square = 0,
    /// Some info flags.
    flags: Flags = Flags {},

    pub fn init() Move
    {
        return std.mem.zeroes(Move);
    }

    pub fn init_with_anchor(anchor: Square) Move
    {
        return Move
        {
            .letters = std.mem.zeroes(std.BoundedArray(MoveLetter, 7)),
            .score = 0,
            .anchor = anchor,
            .flags = Flags {},
        };
    }

    pub fn set_flags(self: *Move, comptime ori: Orientation, comptime is_crossword_generated: bool) void
    {
        self.flags.is_horizontally_generated = ori == .Horizontal;
        self.flags.is_crossword_generated = is_crossword_generated;
    }

    pub fn count(self: Move) u8
    {
        return self.letters.len;
    }

    pub fn sort() void
    {

    }

    pub fn find(self: Move, square: Square) ?Letter
    {
        for (self.letters.slice()) |L|
        {
            if (L.square == square) return L.letter;
        }
        return null;
    }

    pub fn first(self: Move) MoveLetter
    {
        assert(self.letters.len > 0);
        return self.letters.get(0);
    }

    pub fn last(self: Move) MoveLetter
    {
        assert(self.letters.len > 0);
        return self.letters.get(self.letters.len - 1);
    }

    pub fn insert_letter(self: *Move, letter: Letter, square: Square) void
    {
        self.letters.insert(0, MoveLetter {.letter = letter, .square = square}) catch return; // why dont we have an insertAssumeCapacity?
    }

    pub fn add_letter(self: *Move, letter: Letter, square: Square) void
    {
        self.letters.appendAssumeCapacity(MoveLetter {.letter = letter, .square = square});
    }

    pub fn add(self: *Move, cc: CharCode, is_blank: bool, square: Square) void
    {
        self.letters.appendAssumeCapacity(MoveLetter.init(cc, is_blank, square));
    }

    pub fn ret_add_letter(self: Move, letter: Letter, square: Square) Move
    {
        var move: Move = self;
        move.add_letter(letter, square);
        return move;
    }

    pub fn ret_add(self: Move, charcode: CharCode, comptime is_blank: bool, square: Square) Move
    {
        var move: Move = self;
        move.add_letter(Letter.init(charcode, is_blank), square);
        return move;
    }

    /// Inserts or append a letter. If dir = backwards then insert otherwise append.\
    /// This way generated moves always are sorted.
    pub fn added(self: Move, letter: Letter, square: Square, comptime dir: Direction) Move
    {
        var move: Move = self;
        if (dir == .Backwards)
        {
            move.insert_letter(letter, square);
        }
        else
        {
            move.add_letter(letter, square);
        }
        return move;
    }


    /// Function for movegeneration (only used for first turn).
    pub fn shift_left(self: *Move, comptime orientation: Orientation) void
    {
        switch (orientation)
        {
            .Horizontal =>
            {
                for (self.letters.slice()) |*L| L.square -= 1;
            },
            .Vertical =>
            {
                for (self.letters.slice()) |*L|  L.square -= 15;
            },
        }
    }

    /// Function for movegeneration (only used for first turn).
    pub fn rotate(self: *Move) void
    {
        for (self.letters.slice()) |*L|
        {
            L.square = square_flip(L.square);
        }
    }
};

pub const Bag = struct
{
    /// We want to abuse index #0 for the blanks count.
    available: [32]u8 = std.mem.zeroes([32]u8),
    blanks: u8 = 0,

    pub fn init(settings: *const Settings) Bag
    {
        return Bag
        {
            .available = settings.distribution,
            .blanks = settings.blanks,
        };
    }

    pub fn init_empty() Bag
    {
        return Bag {};
    }

    pub fn add(self: *Bag, charcode: CharCode) void
    {
        self.available[charcode] += 1;
    }

    pub fn get_count(self: *const Bag) u32
    {
        var result: u32 = self.blanks;
        for(self.available) |a| result += a;
        return result;
    }

    pub fn to_string(self: *const Bag) std.BoundedArray(Letter, 256)
    {
        var result: std.BoundedArray(Letter, 256) = .{};
        for(self.available, 0..) |avail, idx|
        {
            if (avail == 0) continue;
            const charcode: CharCode = @intCast(idx);
            const count: u8 = avail;
            for (0..count) |_|
            {
                result.appendAssumeCapacity(Letter.init(charcode, false));
            }
        }
        for (0..self.blanks) |_|
        {
            result.appendAssumeCapacity(Letter.init(0, true));
        }
        return result;
    }

    pub fn remove_letter(self: *Bag, letter: Letter) void
    {
        if (letter.is_blank)
        {
            assert(self.blanks > 0);
            self.blanks -= 1;
        }
        else
        {
            assert(self.available[letter.charcode] > 0);
            self.available[letter.charcode] -= 1;
        }
    }

    // pub fn pick(self: *Bag, idx: usize) usize
    // {
    //     var cumulative: usize = 0;
    //     for (self.available, 0..) |count, i|
    //     {
    //         cumulative += count;
    //         if (idx < cumulative)
    //         {
    //             return i; // Found the letter corresponding to the index
    //         }
    //     }
    //     unreachable; // Should never happen if index < total count
    // }

};

pub const Dim = struct
{
    width: u9,
    height: u9,
};

/// For now we use this structure. Later on the board itself will be comptimed.
pub const DIM: Dim = Dim {.width = 15, .height = 15 };



/// Fixed standard 15 x 15 scrabble board.
pub const Board = struct
{
    pub const SIZE: usize = 15;
    pub const LEN: usize = 225;
    pub const STARTSQUARE = 112;
    pub const WIDTH: u9 = 15;

    pub const ALL_SQUARES: [225]Square = blk:
    {
        var temp: [225]Square = undefined;
        for (0..225) |i|
        {
            temp[i] = @as(Square, i);
        }
        break :blk temp;
    };

    //pub const ALL_SQUARES

    //pub const ALLSQUARES: [LEN]Square =

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
    squares: [LEN]Letter,

    pub fn init(settings: *const Settings) Board
    {
        return Board
        {
            .settings = settings,
            .squares = std.mem.zeroes([LEN]Letter),
        };
    }

    pub fn get_ptr(self: *Board, q: Square) *Letter
    {
        return &self.squares[q];
    }

    pub fn get(self: *Board, q: Square) Letter
    {
        return self.squares[q];
    }

    pub fn set(self: *Board, q: Square, char: u21) void
    {
        const charcode = self.settings.codepoint_to_charcode(char) catch return;
        self.squares[q] = Letter.normal(charcode);
    }

    pub fn set_moveletter(self: *Board, moveletter: MoveLetter) void
    {
        self.squares[moveletter.square] = moveletter.letter;
    }

    pub fn is_start_position(self: *const Board) bool
    {
        return self.is_empty(STARTSQUARE);
    }

    /// True if square has no occupied neighbour or at border.
    pub fn is_next_free(self: *const Board, q: Square, comptime orientation: Orientation, comptime direction: Direction) bool
    {
        //CALLS += 1;
        return if(next_square(q, orientation, direction)) |t| self.is_empty(t) else true;
    }

    /// TODO write function returning ?BoardLetter otherwise we fetch the letter 2 or 3 times.
    pub fn is_bow(self: *const Board, q: Square, comptime orientation: Orientation) bool
    {
        return self.is_filled(q) and self.is_next_free(q, orientation, .Backwards);
    }

    pub fn get_bow(self: *const Board, q: Square, comptime orientation: Orientation) ?Letter
    {
        const boardletter = self.squares[q];
        if (boardletter.is_filled() and self.is_next_free(q, orientation, .Backwards))
        {
            return boardletter;
        }
        return null;
    }

    pub fn is_eow(self: *const Board, q: Square, comptime orientation: Orientation) bool
    {
        return self.is_filled(q) and self.is_next_free(q, orientation, .Forwards);
    }

    pub fn has_filled_neighbour(self: *const Board, q: Square, comptime ori: Orientation, comptime dir: Direction) bool
    {
        // NEIGHBOURCALLS += 1;
        const nextsquare = next_square(q, ori, dir) orelse return false;
        return self.is_filled(nextsquare);
    }

    pub fn is_empty(self: *const Board, q: Square) bool
    {
        return self.squares[q].is_empty();
    }

    /// TODO: write get_letter which returns null if empty (for engine)
    pub fn is_filled(self: *const Board, q: Square) bool
    {
        return !self.squares[q].is_empty();
    }

    pub fn get_letter(self: *const Board, square: Square) ?Letter
    {
        const result = self.squares[square];
        return if (result.is_filled()) result else null;
    }

    pub fn set_string(self: *Board, settings: *const Settings, square: Square, str: []const u8, comptime ori: Orientation) void
    {
        const delta = ori.delta(DIM);
        var q: Square = square;
        for (str) |char|
        {
            const cc: CharCode = settings.char_to_code(char);
            const letter: Letter = Letter.init(cc, false);
            self.squares[q] = letter;
            //std.debug.print("{} {c}\n", .{q, char});
            if (!square_has_next(q, ori, .Forwards)) break;
            q += delta;
        }
    }
    //pub fn scan

    /// TODO for scanning we could also have reversed mem slices etc.
    pub fn letter_iterator(self: *const Board, square: Square, comptime ori: Orientation, comptime dir: Direction, comptime inclusive: bool) BoardLetterIterator(ori, dir, inclusive)
    {
        return BoardLetterIterator(ori, dir, inclusive).init(self, square);
    }
};

/// Scans while there are letters, using ori and dir. If inclusive the startingsquare is included in the loop.
fn BoardLetterIterator(comptime ori: Orientation, comptime dir: Direction, comptime inclusive: bool) type
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

        pub fn reset(it: *Self) void
        {
            it.square = it.startsquare;
            it.is_first = true;
        }

        pub fn next(it: *Self) ?MoveLetter
        {
            if (inclusive)
            {
                if (it.is_first)
                {
                    it.is_first = false;
                    const bl = it.board.squares[it.startsquare];
                    return if (bl.is_empty()) null else MoveLetter { .letter = bl, .square = it.startsquare };
                }
            }

            const t = get_next(it.square) orelse return null;
            //it.square = t;
            const bl = it.board.squares[t];
            if (bl.is_filled())
            {
                it.square = t;
                return MoveLetter { .letter = bl, .square = t };
            }
            else return null;
            //return if (bl.is_filled()) MoveLetter { .letter = bl.letter, .square = t } else null;
        }

        fn get_next(q: Square) ?Square
        {
            return next_square(q, ori, dir);
        }

        pub fn current_square(it: *const Self) Square
        {
            return it.square;
        }
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

fn square_from(x: Square, y: Square) Square
{
    return y * 15 + x;
}

fn square_flip(q: Square) Square
{
    return square_from(square_y(q), square_x(q));
}

/// Only for same col or row
/// todo: make an unsafe version where b >= a required.
pub fn squares_between(a: Square, b: Square, comptime ori: Orientation) u8
{
    if (ori == .Horizontal) assert(square_y(a) == square_y(b));
    if (ori == .Vertical) assert(square_x(a) == square_x(b));
    const c: u9 = @max(a, b) - @min(a, b);
    return if (ori == .Horizontal) @intCast(c) else @intCast(c / 15);
}

pub fn square_distance(a: Square, b: Square, comptime ori: Orientation) u8
{
    return squares_between(a, b, ori) + 1;
}

pub fn square_has_next(q: Square, comptime ori: Orientation, comptime dir: Direction) bool
{
    switch (ori)
    {
        .Horizontal =>
        {
            switch (dir)
            {
                .Forwards => return (square_x(q) < 14),
                .Backwards => return (square_x(q) > 0),
            }
        },
        .Vertical =>
        {
            switch (dir)
            {
                .Forwards => return (square_y(q) < 14),
                .Backwards => return (square_y(q) > 0),
            }
        },
    }
}

pub fn next_square(q: Square, comptime orientation: Orientation, comptime direction: Direction) ?Square
{
    //CALLS += 1;
    switch (orientation)
    {
        .Horizontal =>
        {
            switch (direction)
            {
                .Forwards => return if (square_x(q) < 14) q + 1 else null,
                .Backwards => return if (square_x(q) > 0) q - 1 else null,
            }
        },
        .Vertical =>
        {
            switch (direction)
            {
                .Forwards => return if (square_y(q) < 14) q + 15 else null,
                .Backwards => return if (square_y(q) > 0) q - 15 else null,
            }

        },
    }
}

/// TODO: try to rewrite it so that it does not matter if the move is alreay on the board or not.
/// Move must be sorted by square and legal.
/// TODO: check move is sorted (or do that outside)
pub fn calculate_score(settings: *const Settings, board: *const Board, move: *const Move, comptime orientation: Orientation) u16
{
    if (move.letters.len == 0) return 0;
    const opp: Orientation = orientation.opp();
    const delta: u9 = if (orientation == .Horizontal) 1 else 15;
    const my_first_square: Square = move.letters.get(0).square;
    const my_last_square: Square = move.letters.get(move.letters.len - 1).square;
    var word_mul: u32 = 1;
    var my_score: u32 = 0;
    var cross_score: u32 = 0;

    // Scan board letters "outside" move, update myscore.
    var it1 = board.letter_iterator(my_first_square, orientation, .Backwards, false);
    while (it1.next()) |B| my_score += settings.lv(B.letter);
    var it2 = board.letter_iterator(my_last_square, orientation, .Forwards, false);
    while (it2.next()) |B| my_score += settings.lv(B.letter);

    // Scan played letters + board letters "inside" move.
    var q = my_first_square;
    var idx: u8 = 0;
    while (q <= my_last_square)
    {
        const boardletter =  board.squares[q];
        if (boardletter.is_filled())
        {
            my_score += settings.lv(boardletter);
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
    return @truncate(score);
}

pub fn calculate_score_on_empty_board(settings: *const Settings, move: *const Move) u16
{
    if (move.letters.len == 0) return 0;
    var word_mul: u32 = 1;
    var my_score: u32 = 0;

    // Scan played letters.
    for(move.letters.slice()) |L|
    {
        const boardmul = Board.BWV[L.square];
        const lettermul = Board.BLV[L.square];
        word_mul *= boardmul;
        my_score += lettermul * settings.lv(L.letter);
    }

    var score = word_mul * my_score;
    if (move.letters.len == 7) score += 50;
    return @truncate(score);
}

var last_error: std.BoundedArray(u8, 256) = .{};

pub fn set_last_error(message: []const u8) void
{
    const len = @min(256, message.len);
    last_error.len = 0;
    last_error.appendSliceAssumeCapacity(message[0..len]);
}

pub fn get_last_error() []const u8
{
    return last_error.slice();
}

pub const ScrabbleError = error
{
    UnsupportedLanguage,
    UnsupportedCharacter,
    GaddagBuildError,
    GaddagValidationFailed,
    TestError,
};

