
// TODO: get rid of std.debug.print.

const std = @import("std");

const scrabble = @import("scrabble.zig");

pub fn nps(count: usize, elapsed_nanoseconds: u64) u64
{
    // Avoid division by zero
    if (elapsed_nanoseconds == 0)
    {
        return 0;
    }

    const a: f64 = @floatFromInt(count);
    const b: f64 = @floatFromInt(elapsed_nanoseconds);

    //const s: f64 =  (a / b) * 1_000_000_000.0;

     const s: f64 =  (a * 1_000_000_000.0) / b;

    return @intFromFloat(s);
}

pub fn get_coord_name(square: scrabble.Square, board: *const scrabble.Board) [3]u8 // TODO: hm....
{
    const x: u8 = @intCast(board.square_x(square));
    const y: u8 = @intCast(board.square_y(square));
    var coord_buf: [3]u8 = .{'a' + x, 0, 0};
    //var buf: [3]u8 = undefined;
    //coord_buf[0] = 'a' + x;
    _ = std.fmt.formatIntBuf(coord_buf[1..], y + 1, 10, .lower, .{});
    return coord_buf;
}

/// quick and dirty debug test reader
pub fn fill_board_from_txt_file(board: *scrabble.Board, filename: []const u8) !void
{
    const allocator = std.heap.page_allocator;

    const file: std.fs.File = try std.fs.openFileAbsolute(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const file_size = stat.size;

    const file_buffer = try file.readToEndAlloc(std.heap.page_allocator, file_size);
    defer allocator.free(file_buffer);

    var square: scrabble.Square = 0;
    for (file_buffer)|u|
    {
        if (u <= 32) continue;
        if (u == '.') board.squares[square] = scrabble.Letter.EMPTY
        else if (u >= 'a' and u <= 'z') board.squares[square] = scrabble.Letter.init(try board.settings.encode(u), false);
        square += 1;
    }
}

pub fn printmove_only(move: *const scrabble.Move, settings: *const scrabble.Settings) void
{
    for (move.letters.slice()) |moveletter|
    {
        std.debug.print("", .{});
        const char: scrabble.Char = settings.decode(moveletter.letter.charcode);
        if (moveletter.letter.is_blank)
            std.debug.print("{u}* {}/ ", .{char, moveletter.square})
        else
            std.debug.print("{u} {}/ ", .{char, moveletter.square});
    }
    std.debug.print(" {} is_crossgen {} is_horzgen {}\n", .{move.anchor, move.flags.is_crossword_generated, move.flags.is_horizontally_generated});
}

pub fn print_rack(rack: *const scrabble.Rack, settings: *const scrabble.Settings) void
{
    std.debug.print("rack: ", .{});
    for (rack.letters.slice()) |rackletter|
    {
        std.debug.print("{u}", .{settings.decode(rackletter)});
    }
    for (0..rack.blanks) |_|
    {
        std.debug.print("?", .{});
    }
    std.debug.print("\n", .{});
}

pub fn print_bag(bag: *const scrabble.Bag, settings: *const scrabble.Settings) void
{
    for (bag.str.slice()) |B|
    {
        if (B.is_blank)
        std.debug.print("*", .{})
        else std.debug.print("{u}", .{settings.decode(B.charcode)});
    }
    std.debug.print("\n", .{});

}

pub fn print_encoded_word(encoded_word: []const scrabble.CharCode, settings: *const scrabble.Settings) !void
{
    for (encoded_word) |cc|
    {
        std.debug.print("{u}", .{settings.decode(cc)});
    }
    std.debug.print("\n", .{});
}

pub fn print_board_ex(board: *const scrabble.Board, move: ?*const scrabble.Move, rack: ?*const scrabble.Rack, bag: ?*const scrabble.Bag) void
{
    const reset = ConsoleColor.reset;
    const gray: ConsoleColor = .dark_gray;

    std.debug.print("\n{s}a b c d e f g h i j k l m n o{s}\n", .{gray.fg(), reset});
    for(0..board.length) |i|
    {
        const q: scrabble.Square = @intCast(i);
        const x = board.square_x(q);
        const y = board.square_y(q);

        const boardletter: scrabble.Letter = board.squares[q];
        const char = board.settings.decode(boardletter.charcode);
        // no letter on board
        if (char == 0)
        {
            var filled: bool = false;
            if (move) |m|
            {
                if (m.find(q)) |moveletter|
                {
                    const ch = board.settings.decode(moveletter.charcode);
                    if (moveletter.is_blank)
                        std.debug.print("{s}{u} {s}", .{ ConsoleColor.red.fg(), ch, reset })
                    else
                        std.debug.print("{s}{u} {s}", .{ ConsoleColor.yellow.fg(), ch, reset });
                    filled = true;
                }
            }
            if (!filled)
            {
                std.debug.print("{s}. {s}", .{ConsoleColor.dark_gray.fg(), reset});
            }
        }
        // letter on board
        else
        {
            var filled: bool = false;
            if (move) |m|
            {
                if (m.find(q)) |moveletter|
                {
                    if (moveletter.is_blank)
                        std.debug.print("{s}{u} {s}", .{ ConsoleColor.red.fg(), char, reset })
                    else
                        std.debug.print("{s}{u} {s}", .{ ConsoleColor.yellow.fg(), char, reset });
                    filled = true;
                }
            }
            if (!filled)
            {
                if (boardletter.is_blank) std.debug.print("{s}{u} {s}", .{ConsoleColor.light_green.fg(),  char, reset})
                else std.debug.print("{s}{u} {s}", .{ ConsoleColor.light_blue.fg(), char, reset });
            }

        }
        if (x == 14) std.debug.print(" {s}{}{s}\n", .{gray.fg(), y + 1, reset});
    }
    if (rack) |r| print_rack(r, board.settings);
    if (move) |m|
    {
        const cc = get_coord_name(m.anchor, board) ;
        std.debug.print("move: lay {}, anchor {s}, score {} (hgen={} cgen={})\n", .{m.letters.len, cc, m.score, m.flags.is_horizontally_generated,  m.flags.is_crossword_generated});
    }
    if (bag) |b| std.debug.print("bag: {}\n", .{b.str.len});
}


pub const ConsoleColor = enum
{
    black,
    dark_gray,
    light_blue,
    dark_blue,
    light_pink,
    red,
    white,
    yellow,
    light_green,

    const reset = "\x1b[0m";

    pub fn fg(self: ConsoleColor) []const u8
    {
        return switch (self)
        {
            .black => "\x1b[30m",
            .dark_gray => "\x1b[90m",
            .light_blue => "\x1b[94m",
            .dark_blue => "\x1b[34m",
            .light_pink => "\x1b[95m",
            .red => "\x1b[31m",
            .white => "\x1b[97m",
            .yellow => "\x1b[93m",
            .light_green => "\x1b[92m",
        };
    }

    pub fn bg(self: ConsoleColor) []const u8
    {
        return switch (self)
        {
            .black => "\x1b[40m",
            .dark_gray => "\x1b[100m",
            .light_blue => "\x1b[104m",
            .dark_blue => "\x1b[44m",
            .light_pink => "\x1b[105m",
            .red => "\x1b[41m",
            .white => "\x1b[107m",
            .yellow => "\x1b[103m",
            .light_green => return "\x1b[42m",
        };
    }
};



// pub fn printmove(board: *const scrabble.Board, move: *const scrabble.Move, rack: ?scrabble.Rack) void
// {
//     //for (scrabble.Board.ALL_SQUARES) |q| std.debug.print("{}\n", .{q});
//     std.debug.print("\n", .{});
//     //for (scrabble.Board.ALL_SQUARES) |q|
//     for(0..board.length) |i|
//     {
//         const q: scrabble.Square = @intCast(i);
//         const x = board.square_x(q);
//         //const y = scrabble.square_y(q);

//         if (move.find(q)) |L|
//         {
//             const char: scrabble.Char = board.settings.decode(L.charcode);
//             if (L.is_blank)
//                 std.debug.print("\x1b[31m{u} \x1b[0m", .{char})
//             else
//                 std.debug.print("\x1b[34m{u} \x1b[0m", .{char});
//         }
//         else
//         {
//             var char = board.settings.decode(board.squares[q].charcode);
//             if (char == 0) char = '.';
//             std.debug.print("{u} ", .{char});
//         }
//         if (x == 14) std.debug.print("\n", .{});
//     }
//     if (rack) |r| print_rack(r, board.settings);
//     std.debug.print("move: len {} anchor {} score {}\n", .{move.letters.len, move.anchor, move.score});
//     //std.debug.print("\x1b[34mThis is blue text\x1b[0m\n", .{}); // Blue text
// }




// const std = @import("std");
// const print = std.debug.print;
// const builtin = @import("builtin");

// const UTF8ConsoleOutput = struct {
//     original: c_uint = undefined,
//     fn init() UTF8ConsoleOutput {
//         var self = UTF8ConsoleOutput{};
//         if (builtin.os.tag == .windows) {
//             const kernel32 = std.os.windows.kernel32;
//             self.original = kernel32.GetConsoleOutputCP();
//             _ = kernel32.SetConsoleOutputCP(65001);
//         }
//         return self;
//     }
//     fn deinit(self: *UTF8ConsoleOutput) void {
//         if (self.original != undefined) {
//             _ = std.os.windows.kernel32.SetConsoleOutputCP(self.original);
//         }
//     }
// };

// pub fn main() !void {
//     var cp_out = UTF8ConsoleOutput.init();
//     defer cp_out.deinit();

//     print("\u{00a9}", .{});
// }














// /// For now we only use this one to read text files.\
// /// For the rest we avoid unicode now.
// pub fn unicode_iterator(string: []const u8) !std.unicode.Utf8Iterator
// {
//     const view: std.unicode.Utf8View = try std.unicode.Utf8View.init(string);
//     return view.iterator();
// }



// pub fn printboard(board: *const scrabble.Board) void
// {
//     std.debug.print("\n", .{});
//     //for (scrabble.Board.ALL_SQUARES) |q| std.debug.print("{}\n", .{q});
//     //for (scrabble.Board.ALL_SQUARES) |q|
//     for(0..board.length) |i|
//     {
//         const q: scrabble.Square = @intCast(i);
//         const x = board.square_x(q);
//         //const y = scrabble.square_y(q);
//         var char: scrabble.Char = board.settings.decode(board.squares[q].charcode);
//         if (char == 0) char = '.';
//         std.debug.print("{u} ", .{char});
//         if (x == 14) std.debug.print("\n", .{});
//     }

//     //std.debug.print("\x1b[34mThis is blue text\x1b[0m\n", .{}); // Blue text
// }