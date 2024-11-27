const std = @import("std");

const scrabble = @import("scrabble.zig");


/// For now we only use this one to read text files.\
/// For the rest we avoid unicode now.
pub fn unicode_iterator(string: []const u8) !std.unicode.Utf8Iterator
{
    const view: std.unicode.Utf8View = try std.unicode.Utf8View.init(string);
    return view.iterator();
}

pub fn nps(count: usize, elapsed_nanoseconds: u64) u64
{
    // Avoid division by zero
    if (elapsed_nanoseconds == 0)
    {
        return 0.0;
    }

    const a: f64 = @floatFromInt(count);
    const b: f64 = @floatFromInt(elapsed_nanoseconds);

    const s: f64 =  a / b * 1_000_000_000.0;

    return @intFromFloat(s);
}

pub fn get_coord_name(square: scrabble.Square) ![]const u8
{
    const x: u8 = @truncate(scrabble.square_x(square));
    const y: u8 = @truncate(scrabble.square_y(square));
    var buf: [3]u8 = undefined;
    return try std.fmt.bufPrint(&buf, "{c}{d}", .{x + 'a', y + 1}); // TODO: this is crap
}


pub fn printboard(board: *const scrabble.Board, settings: *const scrabble.Settings) void
{
    std.debug.print("\n", .{});
    //for (scrabble.Board.ALL_SQUARES) |q| std.debug.print("{}\n", .{q});
    for (scrabble.Board.ALL_SQUARES) |q|
    {
        const x = scrabble.square_x(q);
        //const y = scrabble.square_y(q);
        var char: scrabble.Char = settings.decode(board.squares[q].charcode);
        if (char == 0) char = '.';
        std.debug.print("{u} ", .{char});
        if (x == 14) std.debug.print("\n", .{});
    }

    //std.debug.print("\x1b[34mThis is blue text\x1b[0m\n", .{}); // Blue text
}

pub fn printmove(board: *const scrabble.Board, move: *const scrabble.Move, settings: *const scrabble.Settings, rack: ?scrabble.Rack) void
{
    //for (scrabble.Board.ALL_SQUARES) |q| std.debug.print("{}\n", .{q});
    std.debug.print("\n", .{});
    for (scrabble.Board.ALL_SQUARES) |q|
    {
        const x = scrabble.square_x(q);
        //const y = scrabble.square_y(q);

        if (move.find(q)) |L|
        {
            const char: scrabble.Char = settings.decode(L.charcode);
            if (L.is_blank)
                std.debug.print("\x1b[31m{u} \x1b[0m", .{char})
            else
                std.debug.print("\x1b[34m{u} \x1b[0m", .{char});
        }
        else
        {
            var char = settings.decode(board.squares[q].charcode);
            if (char == 0) char = '.';
            std.debug.print("{u} ", .{char});
        }
        if (x == 14) std.debug.print("\n", .{});
    }
    if (rack) |r| print_rack(r, settings);
    std.debug.print("move: len {} anchor {} score {}\n", .{move.letters.len, move.anchor, move.score});
    //std.debug.print("\x1b[34mThis is blue text\x1b[0m\n", .{}); // Blue text
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
    std.debug.print("\n", .{});
}

pub fn print_rack(rack: scrabble.Rack, settings: *const scrabble.Settings) void
{
    std.debug.print("rack: ", .{});
    for (rack.letters.slice()) |rackletter|
    {
        std.debug.print("{u}", .{settings.decode(rackletter)});
    }
    for (0..rack.blanks) |_|
    {
        std.debug.print("*", .{});
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
    // std.debug.print("\x1b[31mThis is red text\x1b[0m\n", .{}); // Red text
    // std.debug.print("\x1b[32mThis is green text\x1b[0m\n", .{}); // Green text
    // std.debug.print("\x1b[34mThis is blue text\x1b[0m\n", .{}); // Blue text

// pub fn get_coord_name(square: scrabble.Square) []const u8
// {
//     // const x: u8 = @truncate(scrabble.square_x(square));
//     // const y: u8 = @truncate(scrabble.square_y(square));

//     // var buffer: [3]u8 = undefined; // Fixed-size buffer
//     // //_ = square;
//     // //return &.{'h'};

//     // std.fmt.formatBuf(&buffer, "{c}{}", .{x + 'a', y}) catch unreachable;

//     // return buffer;

//     // const col = (x + 1) + 'a' - 1; // Convert x to letter (a, b, c...)
//     // const row = y + 1; // Convert y to row number (1, 2, 3...)
//     // std.debug.print("col={}", .{col});
//     // std.debug.print("row={}", .{row});
//     // return &[_]u8{col, '0', row + '0'};

//     //return std.fmt.fo

// }

// pub fn get_coord_name(square: scrabble.Square) [3]u8
// {
//     const x = scrabble.square_x(square);
//     const y = scrabble.square_y(square);
//     std.fmt.buf
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














