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
const utils = @import("utils.zig");

/// No unicode yet!
/// 8 bits, this is the real unicode char, max supported value = 255.\
/// We only support simple european languages for now.
pub const Char = u8;

/// 5 bits, this is our mapped value, max supported value = 31.
pub const CharCode = u5;

/// 11 bits, this is our square, scrabble board can have maximum 2047 squares.
pub const Square = u8;

/// 4 bits, letter value, max value = 15,
pub const Value = u4;

pub const Direction = enum
{
    Horizontal,
    Vertical,
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
    codes: [256]CharCode = std.mem.zeroes([256]CharCode), // = [_]CharCode ** 512,

    /// `0 1 2 3 4`...\
    /// `0 a b c d`...
    unicode_chars: [32]Char = std.mem.zeroes([32]Char),
    //values: [512]u8,

    pub fn init(language: Language) !Settings
    {
        // fixed for now during development...
        // if (language != .Dutch)
        // {
        //     return ScrabbleError.UnsupportedLanguage;
        // }

        const def: *const LocalDef  = switch(language)
        {
            .Dutch => &DutchDef,
            .English => &EnglishDef,
        };



        //const def: *const LocalDef = &DutchDef;
        var result = Settings {};

        var code: CharCode = 1;
        for(def.unique_letters) |ch|
        {
            const cc: Char = ch;
            result.codes[cc] = code;
            result.unicode_chars[code] = cc;
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

const MoveFlags = packed struct
    {
        is_gen: bool = false, // is engine generated
        is_gen_vertical: bool = false, // is generated from vertical logic
        is_gen_backwards: bool = false,
        is_gen_crossword: bool = false,
        is_validated: bool = false,
        is_gen_try: bool = false, // only used during engine processing: this is a try letter
        is_calculated: bool = false,
        is_logical_vertical: bool = false,
    };

const Move = struct
{


    // const
    // // move bits / engine genflags
    // bit_move_vertical     = Bit0;     // if engine generated: vertically generated
    // bit_gen_backwards     = Bit1;     // only used during engine processing: generated in backwards mode (prefix)
    // bit_move_engine       = Bit2;     // if engine generated: bit always set
    // bit_move_crossgen     = Bit3;     // if engine generated: is generated crossmove
    // bit_move_validated    = Bit4;     // if engine generated: bit always set
    // bit_gen_try           = Bit5;     // only used during engine processing: this is a try letter
    // //  bit_move_sorted       = Bit6;     // move squares already sorted: always the case when generated
    // bit_move_calculated   = Bit7;     // move score is already calculated

    // bit_move_pass             = Bit8;     // move is an exchange move. letters are taken from the bag, squares are indices to rackposition
    // bit_move_logical_vertical = Bit9;



    letters: [8]LetterSquare,
    score: u16,
    //flags: Flags,
    //
    pub fn init() Move
    {
        return Move
        {
            .letters = std.mem.zeroes(LetterSquare),
            .score = 0,
            //.flags
        };
    }
};

const LetterSquare = packed struct
{
    char: CharCode, // 5 bits
    square: Square, // 11 bits
};

pub const BoardLetter = packed struct
{
    pub const EMPTY: BoardLetter = BoardLetter {};

    char: CharCode = 0, // 5 bits
    is_blank: bool = false, // 1 bit
    is_engine_temp: bool = false, // 1 bit

    pub fn is_empty(self: BoardLetter) bool
    {
        return self.char == 0;
    }
};

/// Fixed standard 15 x 15 scrabble board.
pub const Board = struct
{
    pub const SIZE: usize = 15;
    pub const LEN: usize = 225;
    pub const STARTSQUARE = 112;

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

    squares: [LEN]BoardLetter,

    pub fn init() !Board
    {
        return Board
        {
            //.squares = try allocator.alloc(BoardLetter, 225),
        };
    }

    pub fn get_ptr(self: *Board, idx: usize) *BoardLetter
    {
        return &self.squares[idx];
    }

    pub fn get(self: *Board, idx: usize) BoardLetter
    {
        return self.squares[idx];
    }

    // square has no occupied letter to the right / bottom
    pub fn is_next_free(self: *const Board, q: Square, comptime dir: Direction) bool
    {
        return !square_has_next(q, dir) or self.squares[next_square(q, dir)].is_empty();
    }

    pub fn is_prev_free(self: *const Board, q: Square, comptime dir: Direction) bool
    {
        return !square_has_prev(q, dir) or self.squares[prev_square(q, dir)].is_empty();
    }

    pub fn is_bow(self: *const Board, q: Square, comptime dir: Direction) bool
    {
        return !self.squares[q].is_empty() and self.is_prev_free(q, dir);
    }

    pub fn is_eow(self: *const Board, q: Square, comptime dir: Direction) bool
    {
        return !self.squares[q].is_empty() and self.is_next_free(q, dir);
    }

    pub fn scan_forwards(self: *const Board, q: Square, comptime dir: Direction) Square
    {
        var result: Square = q;
        while (square_has_next(result))
        {
            const next: Square = next_square(q, dir);
            const letter = self.squares[next];
            if (letter.is_empty()) break;
            result = next;
        }
        return result;
    }

};


pub const Rack = struct
{
    //letters: [8]
};


pub fn square_x(q: Square) Square
{
    return q % 15;
}

pub fn square_y(q: Square) Square
{
    return q / 15;
}

pub fn square_has_next(q: Square, comptime direction: Direction) bool
{
    return switch (direction)
    {
        .Horizontal => square_x(q) < 14,
        .Vertical => q < 210,
    };
}

pub fn square_has_prev(q: Square, comptime direction: Direction) bool
{
    return switch (direction)
    {
        .Horizontal => square_x(q) > 0,
        .Vertical => q > 14,
    };
}

pub fn next_square(q: Square, comptime direction: Direction) Square
{
    return switch (direction)
    {
        .Horizontal => q + 1,
        .Vertical => q + 15,
    };
}

pub fn prev_square(q: Square, comptime direction: Direction) Square
{
    return switch (direction)
    {
        .Horizontal => q - 1,
        .Vertical => q - 15,
    };
}

pub const ScrabbleError = error
{
    UnsupportedLanguage,
    UnsupportedCharacter,
    GaddagBuildError,
    GaddagValidationFailed,
};


// OLD DELPHI move
// case Byte of
//       0:
//         (
//           _Letters : U64;
//           _Squares : U64;
//           _Tech    : U64;
//           _Game    : U64;
//         );
//       1:
//         (
//           Letters          : array[0..7] of TLetter;
//           Squares          : array[0..7] of TSquare;

//           CalculatedScore  : Word; // filled during calculate
//           Eval             : Word; // engine evaluation
//           Flags            : Word; // used by engine and calcscore
//           Count            : Byte; // number of played or exchanged letters
//           Anchor           : Byte; // initialized in engine and only used by engine
//           AnchorSkip       : Byte; // initialized in engine and only used by engine

//           WordStart        : TSquare; // filled during calculate and validate
//           WordEnd          : TSquare; // filled during calculate and validate
//           Reserved         : array[0..4] of byte;  // 6 bytes remaining until 32 bytes
//        );