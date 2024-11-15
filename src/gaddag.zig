const std = @import("std");
const utils =  @import("utils.zig");
const scrabble =  @import("scrabble.zig");

const ScrabbleError = scrabble.ScrabbleError;
const Char = scrabble.Char;
const CharCode = scrabble.CharCode;


const allocator = std.heap.page_allocator;
const assert = std.debug.assert;

const NodeData = packed struct
{
    /// The 5 bits character code
    char: CharCode,
    /// Is this node the beginning of a word?
    is_bow: bool = false,
    /// Is this node the end of a word?
    is_eow: bool = false,
    /// Is this node a whole word?
    is_whole: bool = false,

    fn init(char: u5) NodeData
    {
        return NodeData
        {
            .char = char,
        };
    }
};

const AddResult = struct
{
    node: *Node,
    is_new: bool,
};

/// This structure is used to initially build the tree.
pub const Node = struct
{
    /// The character data for this node.
    data: NodeData,
    /// Dynamically growing sorted children array.
    children: []Node,

    // TODO: we could think of bitflags here for identifying the children in one step, but the memory would grow quite some bit

    pub fn init(char: CharCode) !Node
    {
        return Node
        {
            .data = NodeData.init(char),
            .children = try allocator.alloc(Node, 0)
        };
    }

    pub fn deinit(self: *Node) void
    {
        //const oldvalue = self.data.char;
        for(self.children) |*child|
        {
            child.deinit();
        }
        allocator.free(self.children);
        //std.debug.print("[free initialnode ({})]", .{ oldvalue });
    }

    pub fn has_children(self: *const Node) bool
    {
        return self.children.len > 0;
    }

    // pub fn find(self: *const Node, char: CharCode) ?*const Node
    // {
    //     for(self.children) |*child|
    //     {
    //         if (child.char == char)
    //         {
    //             return child;
    //         }
    //     }
    //     return null;
    // }

    fn find(self: *Node, char: CharCode) ?*Node
    {
        for(self.children) |*node|
        {
            if (node.data.char == char)
            {
                return node;
            }
        }
        return null;
    }

    fn add_or_get(self: *Node, char: CharCode) !(AddResult)
    {
        assert(self.children.len < 32);
        if (self.find(char)) |nodeptr|
        {
            return AddResult { .node = nodeptr, .is_new = false };
        }
        const new_node: *Node = try self.add(char);
        return AddResult { . node = new_node, .is_new = true };
    }

    fn add(self: *Node, char: CharCode) !*Node
    {
        assert(self.children.len < 32);
        const idx = self.find_insertion_index(char);
        try self.grow();
        //std.debug.print("new index for {} = {}\n", .{ char, idx });
        if (idx == self.children.len)
        {
            self.children[self.children.len - 1] = try Node.init(char);
        }
        else
        {
            self.shift(idx);
            self.children[idx] = try Node.init(char);
        }
        return &self.children[idx];
    }

    fn shift(self: *Node, idx: usize) void
    {
        const shift_len: usize = self.children.len - idx - 1;
        std.mem.copyBackwards(Node, self.children[idx + 1..idx + 1 + shift_len], self.children[idx..idx + shift_len]);
    }

    fn grow(self: *Node) !void
    {
        const new_len: usize = self.children.len + 1;
        self.children = try allocator.realloc(self.children, new_len);
    }

    fn find_insertion_index(self: *const Node, new_char: u5) usize
    {
        // This is the first.
        if (self.children.len == 0) return 0;
        // Take shortcut by comparing the last.
        if (self.last_char() < new_char) return self.children.len;
        // Find place.
        for(self.children, 0..) |child, idx|
        {
            assert(new_char != child.data.char);
            if (child.data.char > new_char) return idx;
        }
        return self.children.len;
    }

    /// Internal unsafe routine: get the last char.
    fn last_char(self: *const Node) u5
    {
        return self.children[self.children.len - 1].data.char;
    }

    /// Debug print routine.
    pub fn print(self: *const Node) void
    {
        std.debug.print("char({}) ", .{self.data.char});
        std.debug.print("children: [", .{});
        for(self.children) |child|
        {
            std.debug.print("{},", .{ child.data.char });
        }
        std.debug.print("]\n", .{});
    }

    pub fn print_tree(self: *const Node, depth: u32) void
    {
        _ = self;
        _ = depth;
    }
};

pub const Gaddag = struct
{
    node_count: u32,
    word_count: u32,
    root: Node,


    pub fn init() !Gaddag
    {
        return Gaddag
        {
            .node_count = 0,
            .word_count = 0,
            .root = try Node.init(0),
        };
    }

    pub fn deinit(self: *Gaddag) void
    {
        self.root.deinit();
    }

    pub fn load_from_file(self: *Gaddag, filename: []const u8) !void
    {
        //_ = self;
        const file = try std.fs.openFileAbsolute(filename, .{});
        defer file.close();

        const buf: []u8 = try allocator.alloc(u8, 64); // [_]u8{0} ** 32;
        defer allocator.free(buf);

        // Create a buffered reader
        var reader = std.io.bufferedReader(file.reader());
        const buf_reader = &reader.reader();

        // Read line by line
        while (true)
        {
            //const line = buf_reader.readUntilDelimiterAlloc(allocator, '\n', 32) catch break; // TODO: use 1 local buffer readUntilDelimiter
            //defer allocator.free(line);

            const line = buf_reader.readUntilDelimiter(buf, '\n') catch break; // TODO: use 1 local buffer readUntilDelimiter

            const word = line; //std std.mem.trim(u8, line, " \r");
            if (word.len > 0)
            {
                //std.debug.print("Word: {s}\n", .{word});
                try self.add_word(word);
            }
            else
            {
                break;
            }
        }
    }

    /// Add all rotated character values of this word to the gaddag tree
    fn add_word(self: *Gaddag, word: []const u8) !void
    {
        std.debug.print("Word: {s}\n", .{word});
        std.debug.print("  ", .{});

        //const root: *Node = &self.root;
        var parentnode: *Node = &self.root;

        var it = try utils.str_iterator(word);
        while (it.nextCodepoint()) |cp|
        {
            if (cp > 511)
            {
                return ScrabbleError.UnsupportedCharacter;
            }
            const cc: CharCode = @truncate(cp);
            //std.debug.print("(adding)", .{});
            parentnode = try self.check_add_node(parentnode, cc);
            //std.debug.print("{any}-", .{cc});
        }

        std.debug.print("\n", .{});
    }

    fn add_word_gaddag(self: *Gaddag, word: []const u8) !void
    {
        std.debug.print("Word: {s}\n", .{word});
        std.debug.print("  ", .{});

        //const root: *Node = &self.root;
        var parentnode: *Node = &self.root;

        var it = try utils.str_iterator(word);
        while (it.nextCodepoint()) |cp|
        {
            if (cp > 511)
            {
                return ScrabbleError.UnsupportedCharacter;
            }
            const cc: CharCode = @truncate(cp);
            //std.debug.print("(adding)", .{});
            parentnode = try self.check_add_node(parentnode, cc);
            //std.debug.print("{any}-", .{cc});
        }

        std.debug.print("\n", .{});
    }

    fn check_add_node(self: *Gaddag, parent: *Node, char: CharCode) !*Node
    {
        if (parent.find(char)) |node|
        {
            std.debug.print("(existing {})", .{char});
            return node;
        }
        const result: AddResult = try parent.add_or_get(char);
        if (result.is_new)
        {
            std.debug.print("(new {})", .{char});
            self.node_count += 1;
        }
        return result.node;
    }

    // fn find_node(self: *Gaddag) ?*Node
    // {

    // }

    pub fn load_example(self: *Gaddag) !void
    {
        //var root = try Node.init(12);
        //defer root.deinit();
        const root: *Node = &self.root;

        self.node_count = 1;

        _ = try self.add_node(root, 24);
        _ = try self.add_node(root, 31);
        _ = try self.add_node(root, 27);
        const middle: *Node = try self.add_node(root, 1);
        _ = try self.add_node(middle, 14);

        _ = try self.add_node(root, 15);
        _ = try self.add_node(root, 10);
        _ = try self.add_node(root, 28);
        // try n.add_child(24);
        // try n.add_child(31);
        // try n.add_child(27);
        // try n.add_child(14);
        // try n.add_child(28);
        // try n.add_child(1);
        root.print();
    }

};












/// This structure is used afte reorganizing the memory.
pub const SmartNode = struct
{
    /// The character data for this node.
    data: NodeData,
    /// Index to the first child in fixed memory data chunk.
    child_idx: u32,

    fn init(data: NodeData, child_idx: u32) SmartNode
    {
        return SmartNode
        {
            .data = data,
            .child_idx = child_idx,
        };
    }
};