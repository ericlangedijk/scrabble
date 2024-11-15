// basic structs for the game: settings, board, rack, move
// all characters are in BMP = Basic Multilingual Plane (BMP) : 0 to 0xffff

const std = @import("std");

const allocator = std.heap.page_allocator; // temp constant during testing.

/// 9 bits, this is the real unicode char, max supported value = 511.
pub const Char = u9;

/// 5 bits, this is our mapped value, max supported value = 31.
pub const CharCode = u5;

/// 11 bits, this is our square, scrabble board can have maximum 2047 squares.
pub const Square = u11;

/// 4 bits, letter value, max value = 15,
pub const Value = u4;

/// Supported languages
const Language = enum
{
    Dutch,
    // quite a few here...
};

pub const Settings = struct
{
    tiles: []Tile,
    values: [512]u8,

    pub fn init(language: Language) !Settings
    {
        // fixed for now during tests...
        if (language != .Dutch)
        {
            return ScrabbleError.UnsupportedLanguage;
        }
        const def: *LocalDef = &DutchDef;

        const view = std.unicode.Utf8View.init(def.unique_letters);
        var it = view.iterator();// std.unicode.Utf8Iterator(&view);

        while (it.next()) |c|
        {
            std.debug.print("Code point: {x} Char: {c}\n", .{c, c});
        }
        else
        {
            // Handle errors or invalid UTF-8
            if (it.invalid)
            {
                std.debug.print("Invalid UTF-8 sequence detected.\n", .{});
            }
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

pub const DutchDef: LocalDef = LocalDef
{
    .unique_letters = "abcdefghijklmnopqrstuvwxyz",
    .values       = &.{1,  3,  5,  2,  1,  4,  3,  4,  1,  4,  3,  3,  3,  1,  1,  3, 10,  2,  2,  2,  4,  4,  5,  8,  8,  4},
    .distribution = &.{6,  2,  2,  5, 18,  2,  3,  2,  4,  2,  3,  3,  3, 10,  6,  2,  1,  5,  5,  5,  3,  2,  2,  1,  1,  2},
    .blanks = 2,
};

const Tile = struct
{
    character: Char,
    code: CharCode,
    value: Value,
};

const Move = struct
{
    letters: [8]LetterSquare,
    score: u16,
};

const LetterSquare = packed struct
{
    char: CharCode, // 5 bits
    square: Square, // 11 bits
};

const MoveFlags = packed struct
{

};

pub const BoardLetter = packed struct
{
    pub const EMPTY: BoardLetter = BoardLetter {};

    char: CharCode = 0, // 5 bits
    is_blank: bool = false, // 1 bit

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
};

pub const ScrabbleError = error
{
    UnsupportedLanguage,
    UnsupportedCharacter,
};



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