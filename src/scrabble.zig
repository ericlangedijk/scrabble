//! The basic structs for the scrabblegame: Char, CharCode, Letter, Orientation, Direction, Rack, Move, Bag, Board
//! And some language default settings.
//! Some short terms used in the code:
//! - bwv = board-word-value.
//! - blv = board-letter-value.
//! - lv = letter-value.
//! - bow = begin-of-word.
//! - eow = end-of-word.


const std = @import("std");
const assert = std.debug.assert;

const utils = @import("utils.zig");
const rnd = @import("rnd.zig");

/// Unicode supported char.
pub const Char = u21;

/// 5 bits, this is our mapped value, max supported value = 31.
pub const CharCode = u5;

/// 32 bits easy typed bitmask, we can use everywhere to have sets of letters.
pub const CharCodeMask = std.bit_set.IntegerBitSet(32);

/// 9 bits, this is our square, scrabble board can have maximum 512 squares.
pub const Square = u9;

/// 4 bits, letter value, max value = 15,
pub const Value = u8;

pub const EMPTY_CHARCODE_MASK: CharCodeMask = CharCodeMask.initEmpty();

/// A little crazy experiment for a clear `not`.
pub inline fn not(expr: bool) bool
{
    return !expr;
}

const Context = struct
{
    allocator: std.mem.Allocator,
    settings: Settings,
};

pub fn init_default_scrabbleboard(allocator: std.mem.Allocator, settings: *const Settings) !Board
{
    return Board.init(allocator, settings, 15, 15, DEFAULT_BWV[0..], DEFAULT_BLV[0..]);
}

pub fn init_custom_scrabbleboard(allocator: std.mem.Allocator, settings: *const Settings, comptime width: u9, comptime height: u9, bwv: []const Value, blv: []const Value) !Board
{
    return Board.init(allocator, settings, width, height, bwv, blv);
}

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

pub const Settings = struct
{
    allocator: std.mem.Allocator,
    /// The current language.
    language: Language,
    /// Encoding from char (u21) to our internal code (u5)
    map: std.AutoHashMap(Char, CharCode),
    /// Our Char table.
    chars: [32]Char,
    /// Our value table for each letter / tile.
    values: [32]Value,
    /// Table with the available amounts per letter in the bag.
    distribution: [32]u8,
    /// The number of blanks in the bag.
    blanks: u8 = 0,
    /// True if we encountered characters > 255.
    has_unicode: bool,

    pub fn init(allocator: std.mem.Allocator, language: Language) !Settings
    {
        const def: *const LocalDef  = switch(language)
        {
            .Dutch => &DutchDef,
            .English => &EnglishDef,
            .Slovenian => &SlovenianDef,
        };

        assert(def.unique_letters.len == def.values.len);
        assert(def.unique_letters.len == def.distribution.len);

        var result = Settings
        {
            .allocator = allocator,
            .language = language,
            .map = std.AutoHashMap(Char, CharCode).init(allocator),
            .chars = std.mem.zeroes([32]Char),
            .values = std.mem.zeroes([32]Value),
            .distribution = std.mem.zeroes([32]u8),
            .blanks = 0,
            .has_unicode = false,
        };
        errdefer result.deinit();

        // 0 is mapped to 0
        try result.map.put(0, 0);

        // Generate our codes, starting with 1
        var code: CharCode = 1;
        for(def.unique_letters, def.values, def.distribution) |char, value, amount|
        {
            try result.map.put(char, code);
            result.chars[code] = char;
            result.values[code] = value;
            result.distribution[code] = amount;
            if (char > 255) result.has_unicode = true;
            code += 1;
            if (code >= 32) return ScrabbleError.TooManyCharacters;
        }
        result.blanks = def.blanks;
        return result;
    }

    pub fn deinit(self: *Settings) void
    {
        self.map.deinit();
    }

    pub fn lv(self: *const Settings, letter: Letter) Value
    {
        return self.values[letter.charcode] * @intFromBool(not(letter.is_blank));
    }

    pub fn encode(self: *const Settings, u: Char) !CharCode
    {
        return self.map.get(u) orelse return ScrabbleError.CharacterNotFound;
    }

    pub fn decode(self: *const Settings, c: CharCode) Char
    {
        return self.chars[c];
    }

    pub fn encode_word(self: *const Settings, word: []const u8) !std.BoundedArray(CharCode, 32)
    {
        if (!self.has_unicode) return self.encode_ascii_word(word) else return try self.encode_unicode_word(word);
    }

    pub fn decode_word(self: *const Settings, encoded_word: []const CharCode) std.BoundedArray(Char, 32)
    {
        var buf = std.BoundedArray(Char, 32){};
        for (encoded_word) |charcode|
        {
            buf.appendAssumeCapacity(self.decode(charcode));
        }
        return buf;
    }

    /// private
    fn encode_ascii_word(self: *const Settings, word: []const u8) !std.BoundedArray(CharCode, 32)
    {
        var buf = try std.BoundedArray(CharCode, 32).init(0);
        for (word) |u|
        {
            const charcode = try self.encode(u);
            if (buf.len > 31) return ScrabbleError.WordTooLong;
            buf.appendAssumeCapacity(charcode);
        }
        return buf;
    }

    /// private
    fn encode_unicode_word(self: *const Settings, word: []const u8) !std.BoundedArray(CharCode, 32)
    {
        var buf: std.BoundedArray(CharCode, 32) = .{};
        const view: std.unicode.Utf8View = try std.unicode.Utf8View.init(word);
        var iter = view.iterator();
        while (iter.nextCodepoint()) |u|
        {
            const charcode = try self.encode(u);
            if (buf.len > 31) return ScrabbleError.WordTooLong;
            buf.appendAssumeCapacity(charcode);
        }
        return buf;
    }

};

/// Core letter
pub const Letter = packed struct
{
    pub const EMPTY: Letter = Letter.init(0, false);

    charcode: CharCode = 0,
    is_blank: bool = false,

    pub fn init(charcode: CharCode, comptime is_blank: bool) Letter
    {
        return Letter { .charcode = charcode, .is_blank = is_blank };
    }

    /// Creates a non-blank letter.
    pub fn normal(charcode: CharCode) Letter
    {
        return Letter.init(charcode, false);
    }

    /// Creates a blank letter.
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

    pub fn as_u6(self: Letter) u6
    {
        return @bitCast(self);
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

/// Array of charcodes + number of blanks separate.\
/// In my experience (and following the move generation algorithm) the cleanest way to represent a rack.\
/// The number of letters + blanks must be <= 7,
pub const Rack = struct
{
    pub const EMPTY: Rack = Rack {};

    letters: std.BoundedArray(CharCode, 7) = .{},
    blanks: u3 = 0,

    pub fn clear(self: *Rack) void
    {
        self.letters.len = 0;
        self.blanks = 0;
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

    /// Return new rack, with the charcode at `idx` removed.
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
            assert(self.blanks > 0);
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

    /// Convenience function.
    pub fn init_string(settings: *const Settings, string: []const u8, blanks: u3) !Rack
    {
        var rack: Rack = EMPTY;
        //const x = settings.encode_word();
        for (string) |cp|
        {
            const cc =  try settings.encode(cp);
            rack.add(cc);
        }
        rack.blanks = blanks;
        return rack;
    }

    /// Convenience function.
    pub fn set_string(self: *Rack, settings: *const Settings, string: []const u8, blanks: u3) !void
    {
        self.clear();
        for (string) |cp|
        {
            self.add(try settings.encode(cp));
        }
        self.blanks = blanks;
    }
};

pub const Move = struct
{
    pub const EMPTY: Move = Move{};

    pub const Flags = packed struct
    {
        is_horizontally_generated: bool = false,
        is_crossword_generated: bool = false,
    };

    /// The layed letters
    letters: std.BoundedArray(MoveLetter, 7) = .{},
    /// Even on a 21 x 21 superscrabble board this u16 should be enough for ridiculous high scores (when we have reasonable board- and lettervalues).
    score: u16 = 0,
    /// The anchor of the move is (1) an eow board letter or (2) an empty square when generated as crossword.
    anchor: Square = 0,
    /// Some info flags.
    flags: Flags = Flags {},

    pub fn init_with_anchor(anchor: Square) Move
    {
        return Move
        {
            .letters = .{},
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

    pub fn count(self: *const Move) u8
    {
        return self.letters.len;
    }

    pub fn sort(self: *Move) void
    {
        std.mem.sortUnstable(MoveLetter, self.letters.slice(), {}, less_than);
    }

    fn less_than(_: void, a: MoveLetter, b: MoveLetter) bool
    {
        return a.square < b.square;
    }

    pub fn to_charcode_mask(self: *const Move) CharCodeMask
    {
        var mask: CharCodeMask = {};
        for (self.letters.slice()) |moveletter|
        {
            mask.set(moveletter.letter.charcode);
        }
        return mask;
    }

    pub fn get_squares(self: *const Move) std.BoundedArray(Square, 7)
    {
        var result: std.BoundedArray(Square, 7) = .{};
        for (self.letters.slice()) |moveletter|
        {
            result.appendAssumeCapacity(moveletter.square);
        }
        return result;
    }

    pub fn contains_charcode(self: *const Move, charcode: CharCode) bool
    {
        for (self.letters.slice()) |L|
        {
            if (L.letter.charcode == charcode) return true;
        }
        return false;
    }

    pub fn contains_blank(self: *const Move) bool
    {
        for (self.letters.slice()) |L|
        {
            if (L.letter.is_blank) return true;
        }
        return false;
    }

    pub fn find(self: *const Move, square: Square) ?Letter
    {
        for (self.letters.slice()) |L|
        {
            if (L.square == square) return L.letter;
        }
        return null;
    }

    pub fn first(self: *const Move) MoveLetter
    {
        assert(self.letters.len > 0);
        return self.letters.get(0);
    }

    pub fn last(self: *const Move) MoveLetter
    {
        assert(self.letters.len > 0);
        return self.letters.get(self.letters.len - 1);
    }

    pub fn insert_letter(self: *Move, letter: Letter, square: Square) void
    {
        self.letters.insert(0, MoveLetter {.letter = letter, .square = square}) catch return; // why dont we have an insertAssumeCapacity?
    }

    pub fn append_letter(self: *Move, letter: Letter, square: Square) void
    {
        self.letters.appendAssumeCapacity(MoveLetter {.letter = letter, .square = square});
    }

    pub fn add(self: *Move, cc: CharCode, is_blank: bool, square: Square) void
    {
        self.letters.appendAssumeCapacity(MoveLetter.init(cc, is_blank, square));
    }

    // pub fn ret_add_letter(self: *const Move, letter: Letter, square: Square) Move
    // {
    //     var move: Move = self.*;
    //     move.add_letter(letter, square);
    //     return move;
    // }

    // pub fn ret_add(self: *const Move, charcode: CharCode, comptime is_blank: bool, square: Square) Move
    // {
    //     var move: Move = self.*;
    //     move.add_letter(Letter.init(charcode, is_blank), square);
    //     return move;
    // }

    /// Inserts or append a letter. If dir = backwards then insert otherwise append.\
    /// This way generated moves always are sorted.
    pub fn appended_or_inserted(self: *const Move, letter: Letter, square: Square, score_delta: u8, comptime dir: Direction) Move
    {
        var move: Move = self.*;
        move.score += score_delta;
        if (dir == .Backwards)
        {
            move.insert_letter(letter, square);
        }
        else
        {
            move.append_letter(letter, square);
        }
        return move;
    }

    pub fn incremented_score(self: *const Move, score_delta: u8) Move
    {
        var move: Move = self.*;
        move.score += score_delta;
        return move;
    }


    pub fn appended(self: *const Move, letter: Letter, square: Square) Move
    {
        var move: Move = self.*;
        move.append_letter(letter, square);
        return move;
    }

    /// For movegeneration (only used for first turn).
    pub fn shift_left(self: *Move, board: *const Board, comptime orientation: Orientation) void
    {
        switch (orientation)
        {
            .Horizontal =>
            {
                for (self.letters.slice()) |*L| L.square -= 1;
            },
            .Vertical =>
            {
                for (self.letters.slice()) |*L|  L.square -= board.width;
            },
        }
    }

    /// For movegeneration (only used for first turn).
    pub fn rotate(self: *Move, board: *const Board) void
    {
        for (self.letters.slice()) |*L|
        {
            L.square = board.square_flip(L.square);
        }
    }

    pub fn is_sorted(self: *const Move) bool
    {
        if (self.letters.len <= 1) return true;
        var q: Square = self.first().square;
        for (self.letters.slice()[1..]) |moveletter|
        {
            if (moveletter.square <= q) return false;
            q = moveletter.square;
        }
        return true;
    }
};

pub const Bag = struct
{
    /// All letters in here, including the blanks.
    str: std.BoundedArray(Letter, 256),

    pub fn init(settings: *const Settings) Bag
    {
        return Bag
        {
            .str = to_str(settings),
        };
    }

    pub fn init_empty() Bag
    {
        return Bag {};
    }

    pub fn reset(self: *Bag, settings: *const Settings) void
    {
        self.str = to_str(settings);
    }

    fn to_str(settings: *const Settings) std.BoundedArray(Letter, 256)
    {
        var result: std.BoundedArray(Letter, 256) = .{};
        for(settings.distribution, 0..) |avail, idx|
        {
            if (avail == 0) continue;
            const charcode: CharCode = @intCast(idx);
            result.appendNTimesAssumeCapacity(Letter.init(charcode, false), avail);
        }

        for (0..settings.blanks) |_|
        {
            result.appendAssumeCapacity(Letter.blank(0));
        }
        return result;
    }

    /// This uses swap removing. The order is messed up, but that does not matter: it is a bag :)
    pub fn extract_letter(self: *Bag, idx: usize) Letter
    {
        return self.str.swapRemove(idx);
    }

    /// Do not throw known blanks in here.
    pub fn append_letter(self: *Bag, letter: Letter) void
    {
        assert(letter.is_blank and letter.charcode == 0 or !letter.is_blank and letter.charcode > 0);
        self.str.appendAssumeCapacity(letter);
    }
};

pub const Board = struct
{
    allocator: std.mem.Allocator,
    /// Reference to our currently used settings.
    settings: *const Settings,
    /// Reference to some bwv table.
    bwv: []const Value,
    /// Reference to some blv table.
    blv: []const Value,
    squares: []Letter,
    width: u9,
    height: u9,
    /// Is `width` * `height`.
    length: u9,
    /// By default the middle square.
    startsquare: Square,

    fn validate_dimensions(comptime width: u9, comptime height: u9, bwv: []const Value, blv: []const Value)ScrabbleError!u9
    {
        if (width < 5 or width > 21 or height < 5 or height > 21 or width % 2 == 0 or height % 2 == 0) return ScrabbleError.InvalidBoardDimensions;
        const length: u9 = width * height;
        if (bwv.len != length or blv.len != length) return ScrabbleError.InvalidBoardScoreParameter;
        return length;
    }

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings, comptime width: u9, comptime height: u9, bwv: []const Value, blv: []const Value) !Board
    {
        const length: u9 = try Board.validate_dimensions(width, height, bwv, blv);
        const startsquare: Square = width * (height / 2) + width / 2;
        assert(startsquare == 112);
        return Board
        {
            .allocator = allocator,
            .settings = settings,
            .bwv = bwv,
            .blv = blv,
            .squares = try init_squares(allocator, length),
            .width = width,
            .length = length,
            .height = height,
            .startsquare = startsquare,
        };
    }

    pub fn deinit(self: *Board) void
    {
        self.allocator.free(self.squares);
    }

    fn init_squares(allocator: std.mem.Allocator, len: u9) ![]Letter
    {
        const result: []Letter = try allocator.alloc(Letter, len);
        @memset(result, Letter.EMPTY);
        return result;
    }

    fn init_bwv(allocator: std.mem.Allocator, len: u9, src: []const Value) ![]Value
    {
        const result: []Value = try allocator.alloc(Value, len);
        @memcpy(result, src);
        return result;
    }

    fn init_blv(allocator: std.mem.Allocator, len: u9, src: []const Value) ![]Value
    {
        const result: []Value = try allocator.alloc(Value, len);
        @memcpy(result, src);
        return result;
    }

    pub fn clear(self: *Board) void
    {
        @memset(self.squares, Letter.EMPTY);
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
        return self.is_empty(self.startsquare);
    }

    /// True if square has no occupied neighbour or at border.
    pub fn is_free(self: *const Board, q: Square, comptime orientation: Orientation, comptime direction: Direction) bool
    {
        //CALLS += 1;
        return if(self.next_square(q, orientation, direction)) |t| self.is_empty(t) else true;
    }

    pub fn is_bow(self: *const Board, q: Square, comptime ori: Orientation) bool
    {
        return self.is_filled(q) and self.is_free(q, ori, .Backwards);
    }

    pub fn is_eow(self: *const Board, q: Square, comptime orientation: Orientation) bool
    {
        return self.is_filled(q) and self.is_free(q, orientation, .Forwards);
    }

    /// A little bit engine specific, but anyway...
    pub fn is_crossword_anchor(self: *const Board, q: Square, comptime ori: Orientation) bool
    {
        const opp = ori.opp();
        if (self.is_filled(q) or self.has_filled_neighbour(q, ori, .Backwards) or self.has_filled_neighbour(q, ori, .Forwards)) return false;
        return self.has_filled_neighbour(q, opp, .Backwards) or self.has_filled_neighbour(q, opp, .Forwards);
    }

    pub fn has_filled_neighbour(self: *const Board, q: Square, comptime ori: Orientation, comptime dir: Direction) bool
    {
        // NEIGHBOURCALLS += 1;
        const nextsquare = self.next_square(q, ori, dir) orelse return false;
        return self.is_filled(nextsquare);
    }

    pub fn is_empty(self: *const Board, q: Square) bool
    {
        return self.squares[q].is_empty();
    }

    pub fn is_filled(self: *const Board, q: Square) bool
    {
        return self.squares[q].is_filled();
    }

    /// Returns null if square is empty
    pub fn get_letter(self: *const Board, square: Square) ?Letter
    {
        const result = self.squares[square];
        return if (result.is_filled()) result else null;
    }

    /// Move must be sorted and legal.
    pub fn make_move(self: *Board, move: *const Move) void
    {
        for (move.letters.slice()) |moveletter|
        {
            self.squares[moveletter.square] = moveletter.letter;
        }
    }

    /// Convenience debug function.
    pub fn set_string(self: *Board, settings: *const Settings, square: Square, str: []const u8, comptime ori: Orientation) !void
    {
        const delta: u9 = self.square_delta(ori);//.delta(self.width);
        var q: Square = square;
        for (str) |char|
        {
            const cc: CharCode = try settings.encode(char);
            const letter: Letter = Letter.init(cc, false);
            self.squares[q] = letter;
            //std.debug.print("{} {c}\n", .{q, char});
            if (not(self.square_has_next(q, ori, .Forwards))) break;
            q += delta;
        }
    }

    pub fn square_x(self: *const Board, q: Square) u9
    {
        return q % self.width;
    }

    pub fn square_y(self: *const Board, q: Square) u9
    {
        return q / self.width;
    }

    pub fn square_delta(self: *const Board, comptime ori: Orientation) u9
    {
        return if (ori == .Horizontal) 1 else self.width;
    }

    pub fn square_from(self: *const Board, x: Square, y: Square) Square
    {
        return y * self.width + x;
    }

    pub fn square_flip(self: *const Board, q: Square) Square
    {
        return self.square_from(self.square_y(q), self.square_x(q));
    }

    pub fn square_has_next(self: *const Board, q: Square, comptime ori: Orientation, comptime dir: Direction) bool
    {
        switch (ori)
        {
            .Horizontal =>
            {
                switch (dir)
                {
                    .Forwards => return (self.square_x(q) < self.width - 1),
                    .Backwards => return (self.square_x(q) > 0),
                }
            },
            .Vertical =>
            {
                switch (dir)
                {
                    .Forwards => return (self.square_y(q) < self.height - 1),
                    .Backwards => return (self.square_y(q) > 0),
                }
            },
        }
    }

    pub fn next_square(self: *const Board, q: Square, comptime orientation: Orientation, comptime direction: Direction) ?Square
    {
        switch (orientation)
        {
            .Horizontal =>
            {
                switch (direction)
                {
                    .Forwards => return if (self.square_x(q) < self.width - 1) q + 1 else null,
                    .Backwards => return if (self.square_x(q) > 0) q - 1 else null,
                }
            },
            .Vertical =>
            {
                switch (direction)
                {
                    .Forwards => return if (self.square_y(q) < self.height - 1) q + self.width else null,
                    .Backwards => return if (self.square_y(q) > 0) q - self.width else null,
                }

            },
        }
    }

    pub fn letter_iterator(self: *const Board, square: Square, comptime ori: Orientation, comptime dir: Direction, comptime inclusive: bool) BoardLetterIterator(ori, dir, inclusive)
    {
        return BoardLetterIterator(ori, dir, inclusive).init(self, square);
    }
};

/// Scans while there are letters, using ori and dir. If inclusive the startingsquare is included in the loop.
pub fn BoardLetterIterator(comptime ori: Orientation, comptime dir: Direction, comptime inclusive: bool) type
{
    return struct
    {
        const Self = @This();

        board: *const Board,
        square: Square,
        is_first: bool,

        pub fn init(board: *const Board, square: Square) Self
        {
            return Self
            {
                .board = board,
                .square = square,
                .is_first = true,
            };
        }

        /// Obviously don't do this while iterating.
        pub fn reset(iter: *Self, square: Square) void
        {
            iter.square = square;
            iter.is_first = true;
        }

        pub fn current_square(iter: *const Self) Square
        {
            return iter.square;
        }

        pub fn next(iter: *Self) ?MoveLetter
        {
            if (inclusive)
            {
                if (iter.is_first)
                {
                    iter.is_first = false;
                    const bl = iter.board.squares[iter.startsquare];
                    return if (bl.is_empty()) null else MoveLetter { .letter = bl, .square = iter.startsquare };
                }
            }

            const t = iter.board.next_square(iter.square, ori, dir) orelse return null;
            const bl = iter.board.squares[t];
            if (bl.is_filled())
            {
                iter.square = t;
                return MoveLetter { .letter = bl, .square = t };
            }
            else
            {
                return null;
            }
        }
    };
}


/// Move must be sorted by square and legal.
pub fn calculate_score(settings: *const Settings, board: *const Board, move: *const Move, comptime ori: Orientation) u16
{
    //if (move.letters.len == 0) return 0;
    assert(move.letters.len > 0);
    assert(move.is_sorted());

    const opp: Orientation = ori.opp();
    const delta: u9 = board.square_delta(ori);
    const my_first_square: Square = move.first().square;
    const my_last_square: Square = move.last().square;
    const bonus: u32 = if (move.letters.len == 7) 50 else 0;
    var word_mul: u32 = 1;
    var my_score: u32 = 0;
    var cross_score: u32 = 0;

    // Scan board letters "outside" move, update myscore.
    var it1 = board.letter_iterator(my_first_square, ori, .Backwards, false);
    while (it1.next()) |B| my_score += settings.lv(B.letter);
    var it2 = board.letter_iterator(my_last_square, ori, .Forwards, false);
    while (it2.next()) |B| my_score += settings.lv(B.letter);

    // Scan played letters + board letters "inside" move.
    var q = my_first_square;
    var idx: u8 = 0;
    while (q <= my_last_square)
    {
        if (board.get_letter(q)) |boardletter|
        {
            my_score += settings.lv(boardletter);
        }
        else
        {
            const moveletter = move.letters.get(idx);
            idx += 1;
            const boardmul: u8 = board.bwv[q];
            const lettermul: u8 = board.blv[q];
            word_mul *= boardmul;
            my_score += lettermul * settings.lv(moveletter.letter);
            var sidescore: u32 = 0;
            var it3 = board.letter_iterator(q, opp, .Backwards, false);
            while (it3.next()) |B| sidescore += settings.lv(B.letter);
            const qb = it3.current_square();
            var it4 = board.letter_iterator(q, opp, .Forwards, false);
            while (it4.next()) |B| sidescore += settings.lv(B.letter);
            const qf = it4.current_square();
            if (qb != qf)
            {
                sidescore += lettermul * settings.lv(moveletter.letter); // letter counts in both directions
                sidescore *= boardmul; // multiply counts in both directions
                cross_score += sidescore;
            }
        }
        q += delta;
    }
    return @truncate(word_mul * my_score + cross_score + bonus);
}

pub fn calculate_score_on_empty_board(settings: *const Settings, board: *const Board, move: *const Move) u16
{
    if (move.letters.len == 0) return 0;
    assert(move.is_sorted());
    var word_mul: u32 = 1;
    var my_score: u32 = 0;

    // Scan played letters.
    for(move.letters.slice()) |L|
    {
        const boardmul: u8 = board.bwv[L.square];
        const lettermul: u8 = board.blv[L.square];
        word_mul *= boardmul;
        my_score += lettermul * settings.lv(L.letter);
    }

    var score = word_mul * my_score;
    if (move.letters.len == 7) score += 50;
    return @truncate(score);
}

const gaddag = @import("gaddag.zig");
pub fn validate_board(board: *const Board, graph: *const gaddag.Graph) !bool
{
    var buf: std.BoundedArray(CharCode, 32) = .{};
    for (Board.ALL_SQUARES) |q|
    {
        buf.len = 0;
        if (board.is_bow(q, .Horizontal))
        {
            var iter = board.letter_iterator(q, .Horizontal, .Forwards, true);
            while (iter.next()) |L| buf.appendAssumeCapacity(L.letter.charcode);
            if (buf.len > 1)
            {
                //try utils.print_encoded_word(buf.slice(), board.settings);
                //std.debug.print("h ok={}\n", .{graph.encoded_word_exists(buf.slice())});
                if (not(graph.encoded_word_exists(buf.slice())))
                {
                    try utils.print_encoded_word(buf.slice(), board.settings);
                    return false;
                }
            }
        }
        buf.len = 0;
    }

    for (Board.ALL_SQUARES) |q|
    {
        buf.len = 0;
        if (board.is_bow(q, .Vertical))
        {
            var iter = board.letter_iterator(q, .Vertical, .Forwards, true);
            while (iter.next()) |L| buf.appendAssumeCapacity(L.letter.charcode);
            if (buf.len > 1)
            {
            //try utils.print_encoded_word(buf.slice(), board.settings);
            //std.debug.print("v ok={}\n", .{graph.encoded_word_exists(buf.slice())});
                if (not(graph.encoded_word_exists(buf.slice())))
                {
                    try utils.print_encoded_word(buf.slice(), board.settings);
                    return false;
                }
            }
        }
    }
    return true;
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
    InvalidBoardDimensions,
    InvalidBoardScoreParameter,
    TooManyCharacters,
    CharacterNotFound,
    WordTooLong,
    GaddagBuildError,
    GaddagValidationFailed,
};

/// Supported languages
pub const Language = enum
{
    Dutch,
    English,
    Slovenian,
    // quite a few here...
};

const LocalDef = struct
{
    unique_letters: []const u21,
    values: []const Value,
    distribution: []const u8,
    blanks: u8,
};

const DutchDef = LocalDef
{
    .unique_letters = &.{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z' },
    .values         = &.{  1,   3,   5,   2,   1,   4,   3,   4,   1,   4,   3,   3,   3,   1,   1,   3,   10,  2,   2,   2,   4,   4,   5,   8,   8,   4 },
    .distribution   = &.{  6,   2,   2,   5,   18,  2,   3,   2,   4,   2,   3,   3,   3,   10,  6,   2,   1,   5,   5,   5,   3,   2,   2,   1,   1,   2 },
    .blanks = 2,
};

const EnglishDef = LocalDef
{
    .unique_letters = &.{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z' },
    .values         = &.{  1,   3,   3,   2,   1,   4,   2,   4,   1,   8,   5,   1,   3,   1,   1,   3,   10,  1,   1,   1,   1,   4,   4,   8,   4,   10 },
    .distribution   = &.{  9,   2,   2,   4,   12,  2,   3,   2,   9,   1,   1,   4,   2,   6,   8,   2,   1,   6,   4,   6,   4,   2,   2,   1,   2,   1 },
    .blanks = 2,
};

const SlovenianDef = LocalDef
{
    .unique_letters = &.{ 'a', 'b', 'c', 'č', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'r', 's', 'š', 't', 'u', 'v', 'z', 'ž' },
    .values         = &.{  1,   4,   8,   5,   2,   1,   10,  4,   5,   1,   1,   3,   1,   3,   1,   1,   3,   1,   1,   6,   1,   3,   2,   4,   10 },
    .distribution   = &.{  10,  2,   1,   1,   4,   11,  1,   2,   1,   9,   4,   3,   4,   2,   7,   8,   2,   6,   6,   1,   4,   2,   4,   2,   1 },
    .blanks = 2,
};


/// Board word values for default 15 x 15 scrabble board.
pub const DEFAULT_BWV: [225]Value =
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

/// Board letter values for default 15 x 15 scrabble board.
pub const DEFAULT_BLV: [225]Value =
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

pub const DEFAULT_WORDFEUD_BWV: [225]Value =
.{
    1,1,1,1,3,1,1,1,1,1,3,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,2,1,1,1,1,1,1,1,1,1,2,1,1,
    1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,
    3,1,1,1,2,1,1,1,1,1,2,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,2,1,1,1,1,1,1,1,2,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    3,1,1,1,2,1,1,1,1,1,2,1,1,1,3,
    1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,
    1,1,2,1,1,1,1,1,1,1,1,1,2,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,3,1,1,1,1,1,3,1,1,1,1,
};

pub const DEFAULT_WORDFEUD_BLV: [225]Value =
.{
    3,1,1,1,1,1,1,2,1,1,1,1,1,1,3,
    1,2,1,1,1,3,1,1,1,3,1,1,1,2,1,
    1,1,1,1,1,1,2,1,2,1,1,1,1,1,1,
    1,1,1,3,1,1,1,1,1,1,1,3,1,1,1,
    1,1,1,1,1,1,2,1,2,1,1,1,1,1,1,
    1,3,1,1,1,3,1,1,1,3,1,1,1,3,1,
    1,1,2,1,1,1,1,1,1,1,1,1,2,1,1,
    2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,
    1,1,2,1,1,1,1,1,1,1,1,1,2,1,1,
    1,3,1,1,1,3,1,1,1,3,1,1,1,3,1,
    1,1,1,1,1,1,2,1,2,1,1,1,1,1,1,
    1,1,1,3,1,1,1,1,1,1,1,3,1,1,1,
    1,1,1,1,1,1,2,1,2,1,1,1,1,1,1,
    1,2,1,1,1,3,1,1,1,3,1,1,1,2,1,
    3,1,1,1,1,1,1,2,1,1,1,1,1,1,3,
};
