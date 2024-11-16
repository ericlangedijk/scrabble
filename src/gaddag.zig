
const std = @import("std");
const assert = std.debug.assert;


const utils =  @import("utils.zig");
const scrabble =  @import("scrabble.zig");

const ScrabbleError = scrabble.ScrabbleError;
const Char = scrabble.Char;
const CharCode = scrabble.CharCode;
const Settings = scrabble.Settings;

const NodeData = packed struct
{
    /// The 5 bits character code
    code: CharCode,
    /// Is this node the beginning of a word?
    is_bow: bool = false,
    /// Is this node the end of a word?
    is_eow: bool = false,
    /// Is this node a whole word?
    is_whole: bool = false,

    fn init(code: CharCode) NodeData
    {
        return NodeData
        {
            .code = code,
        };
    }
};

const AddResult = struct
{
    node: *Node,
    is_new: bool,
};


/// TODO checkout MemoryPool for nodes?
/// This structure is used to initially build the tree.
pub const Node = struct
{
    /// The character data for this node.
    data: NodeData,
    /// Dynamically growing sorted children array.
    children: []Node,

    // TODO: we could think of bitflags here for identifying the children in one step, but the memory would grow quite some bit

    pub fn init(allocator: std.mem.Allocator, char: CharCode) !Node
    {
        return Node
        {
            .data = NodeData.init(char),
            .children = try allocator.alloc(Node, 0)
        };
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void
    {
        for(self.children) |*child|
        {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }

    fn grow(self: *Node, allocator: std.mem.Allocator) !void
    {
        const new_len: usize = self.children.len + 1;
        //std.debug.print("grow {}\n", .{new_len});
        self.children = try allocator.realloc(self.children, new_len);
    }

    pub fn has_children(self: *const Node) bool
    {
        return self.children.len > 0;
    }

    pub fn is_bow(self: *const Node) bool
    {
        return self.data.is_bow;
    }

    pub fn is_eow(self: *const Node) bool
    {
        return self.data.is_eow;
    }

    pub fn is_whole(self: *const Node) bool
    {
        return self.data.is_whole;
    }

    pub fn bow(self: *const Node) ?*Node
    {
        //assert(self.is_bow() and self.children.len > 0);
        if (self.is_bow())
        {
            return &self.children[0];
        }
        else
        {
            return null;
        }
    }

    pub fn find(self: *Node, char: CharCode) ?*Node
    {
        for(self.children) |*node|
        {
            if (node.data.code == char)
            {
                return node;
            }
        }
        return null;
    }

    /// Adds or gets a node to the children (sorted).\
    /// When a new node was created the result's `is_new` flag will be set to true.
    fn add_or_get(self: *Node, allocator: std.mem.Allocator, char: CharCode) !(AddResult)
    {
        assert(self.children.len < 32);
        if (self.find(char)) |nodeptr|
        {
            return AddResult { .node = nodeptr, .is_new = false };
        }
        const new_node: *Node = try self.add_sorted(allocator, char);
        return AddResult { . node = new_node, .is_new = true };
    }

    fn add_sorted(self: *Node, allocator: std.mem.Allocator, char: CharCode) !*Node
    {
        assert(self.children.len < 32);
        const idx = self.find_insertion_index(char);
        try self.grow(allocator);
        if (idx == self.children.len)
        {
            self.children[self.children.len - 1] = try Node.init(allocator, char);
        }
        else
        {
            self.shift(idx);
            self.children[idx] = try Node.init(allocator, char);
        }
        return &self.children[idx];
    }

    fn shift(self: *Node, idx: usize) void
    {
        const shift_len: usize = self.children.len - idx - 1;
        std.mem.copyBackwards(Node, self.children[idx + 1..idx + 1 + shift_len], self.children[idx..idx + shift_len]);
    }

    fn find_insertion_index(self: *const Node, new_char: u5) usize
    {
        if (self.children.len == 0) return 0; // it is the first.
        if (self.last_char() < new_char) return self.children.len; // a little shortcut check.
        // Find place.
        for(self.children, 0..) |child, idx|
        {
            assert(new_char != child.data.code);
            if (child.data.code > new_char) return idx;
        }
        return self.children.len;
    }

    /// Internal unsafe routine: get the last char.
    fn last_char(self: *const Node) u5
    {
        return self.children[self.children.len - 1].data.code;
    }

    /// Debug print routine.
    pub fn print(self: *const Node) void
    {
        std.debug.print("char({}) ", .{self.data.code});
        std.debug.print("children: [", .{});
        for(self.children) |child|
        {
            std.debug.print("{},", .{ child.data.code });
        }
        std.debug.print("]\n", .{});
    }

};

pub const Gaddag = struct
{

    /// The current settings, which determines the charcodes with which we build our tree.
    allocator: std.mem.Allocator,
    settings: *const Settings,
    node_count: u32,
    word_count: u32,
    root: Node,

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings) !Gaddag
    {
        return Gaddag
        {
            .allocator = allocator,
            .settings = settings,
            .node_count = 0,
            .word_count = 0,
            .root = try Node.init(allocator, 0),
        };
    }

    pub fn deinit(self: *Gaddag) void
    {
        self.root.deinit(self.allocator);
    }

    pub fn load_from_file(self: *Gaddag, filename: []const u8) !void
    {
        // load text file in memory.
        const file = try std.fs.openFileAbsolute(filename, .{});
        defer file.close();

        const file_buffer = try file.readToEndAlloc(self.allocator, 8000000);
        defer self.allocator.free(file_buffer);

        // Read line by line
        var it = std.mem.splitAny(u8, file_buffer, &.{13, 10});
        while (it.next()) |word|
        {
            if (word.len == 0) continue; // skip empty (split any is a bit strange)
            //std.debug.print("Word: [{s}]\n", .{word});
            try self.add_word(word);
        }
        //_ = self;
    }


    /// Some words about the gaddag tree structure. Designed to enable backward tracking at any position in any word using backward prefixes and forward suffixes
    /// Let's take the word "instances". it is added to the tree as follows:\
    /// `1. i + nstances`\
    /// `2. ni + stances`\
    /// `3. sni + tances`\
    /// `4. tsni + ances`\
    /// `5. atsni + nces`\
    /// `6. natsni + ces`\
    /// `7. cnatsni + es`\
    /// `7. ecnatsni + s`\
    /// `8. secnatsni`\
    /// The character before the "+" is marked as nf_bow. A bow-node is inserted at index 0 of the children.\
    /// The character "i" at #8 is marked as nf_whole
    fn add_word(self: *Gaddag, word: []const u8) !void
    {
        assert(self.node_count < 200000000);
        self.word_count += 1;
        if (self.word_count % (8192 * 4) == 0)
        {
             std.debug.print("words {} nodes {} {s}\n", .{self.word_count, self.node_count, word});
        }

        const len: usize = word.len;
        var buf = try std.BoundedArray(CharCode, 32).init(0);
        var prefix = try std.BoundedArray(CharCode, 32).init(0);

        // convert
        for (word) |u|
        {
            buf.appendAssumeCapacity(try self.settings.codepoint_to_charcode(u));
        }
        for (0..len) |i|
        {
            try prefix.resize(0);
            prefix.appendSliceAssumeCapacity(buf.slice()[0..i + 1]);
            std.mem.reverse(CharCode, prefix.slice());
            var node = &self.root;
            for (0..prefix.len) |j|
            {
                node = try self.add_or_get_node(node, prefix.get(j)); // TODO: use just node function.

                // at the end of the prefix.
                if ( j == prefix.len - 1)
                {

                    const bownode: ?*Node = node.bow();
                    if (bownode == null)
                    {
                        node.data.is_bow = true;
                        _ = try self.add_or_get_node(node, 0); // add begin of word node
                    }
                    if (prefix.len == len)
                    {
                        node.data.is_whole = true;
                    }
                    // suffix
                    var suffix = node.bow() orelse return ScrabbleError.GaddagBuildError;
                    for (j + 1..len) |k|
                    {
                        suffix = try self.add_or_get_node(suffix, buf.get(k));
                        if (k == len - 1)
                        {
                            suffix.data.is_eow = true; // mark end of word
                        }
                    }
                }
            }
        }
    }

    fn print_slice(self: *const Gaddag, slice: []CharCode) void
    {
        for(slice) |cc|
        {
            const u = self.settings.code_to_char(cc);
            std.debug.print("{c}", .{u});
        }
            std.debug.print("\n", .{});
    }

    pub fn find_node(self: *Gaddag, word: []const u8) ?*Node
    {
        assert(word.len > 0);
        const fc: CharCode = self.settings.codepoint_to_charcode(word[0]) catch return null;
        var node: *Node = self.root.find(fc) orelse return null;
        std.debug.print("BOW {} bow={} eow={} whole={}\n", .{node.data.code, node.is_bow(), node.is_eow(), node.is_whole()});
        node = node.bow() orelse return null;
        for(word[1..]) |cp|
        {
            const cc: CharCode = self.settings.codepoint_to_charcode(cp) catch return null;
            node = node.find(cc) orelse return null;
            std.debug.print("SEARCH {} bow={} eow={} whole={}\n", .{node.data.code, node.is_bow(), node.is_eow(), node.is_whole()});
        }
        return node;
    }

    fn normalize(cp: u21) u21
    {
        return switch (cp)
        {
            'é', 'è', 'ë' => 'e',
            'á' => 'a',
            'í', 'î', 'ï' => 'i',
            'ó' => 'o',
            'ú' => 'u',
            else => cp,
        };
    }

    fn add_or_get_node(self: *Gaddag, parent: *Node, char: CharCode) !*Node
    {
        if (parent.find(char)) |node|
        {
            //std.debug.print("(existing {})", .{char});
            return node;
        }
        const result: AddResult = try parent.add_or_get(self.allocator, char);
        if (result.is_new)
        {
            //std.debug.print("(new {})", .{char});
            self.node_count += 1;
        }
        return result.node;
    }

    pub fn print_tree(self: *const Gaddag) void
    {
        self.print_recursive(&self.root, 0);
    }

    fn print_recursive(self: *const Gaddag, node: *const Node, level: usize) void
    {
        for(0..level) |_|
        {
            std.debug.print(" ", .{});
        }
        //std.debug.print("|", .{});
        const c = self.settings.code_to_char(node.data.code);
        std.debug.print("{u}\n", .{ c });
        for(node.children) |*child|
        {
            self.print_recursive(child, level + 1);
        }
    }

};

// pub const SmartNode = struct
// {
//     /// The character data for this node.
//     data: NodeData,
//     /// Index to the first child in fixed memory data chunk.
//     child_idx: u32,

//     fn init(data: NodeData, child_idx: u32) SmartNode
//     {
//         return SmartNode
//         {
//             .data = data,
//             .child_idx = child_idx,
//         };
//     }
// };


// OLD SHIT

    // Add all rotated character values of this word to the gaddag tree
    // fn add_word(self: *Gaddag, word: []const u8) !void
    // {
    //     std.debug.print("Word: {s}\n", .{word});
    //     std.debug.print("  ", .{});

    //     //const root: *Node = &self.root;
    //     var parentnode: *Node = &self.root;

    //     var it = try utils.str_iterator(word);
    //     while (it.nextCodepoint()) |cp|
    //     {
    //         if (cp > 511)
    //         {
    //             return ScrabbleError.UnsupportedCharacter;
    //         }
    //         const cc: CharCode = @truncate(cp);
    //         //std.debug.print("(adding)", .{});
    //         parentnode = try self.check_add_node(parentnode, cc);
    //         //std.debug.print("{any}-", .{cc});
    //     }

    //     std.debug.print("\n", .{});
    // }


    //    pub fn load_example(self: *Gaddag) !void
    // {
    //     //var root = try Node.init(12);
    //     //defer root.deinit();
    //     const root: *Node = &self.root;

    //     self.node_count = 1;

    //     _ = try self.add_node(root, 24);
    //     _ = try self.add_node(root, 31);
    //     _ = try self.add_node(root, 27);
    //     const middle: *Node = try self.add_node(root, 1);
    //     _ = try self.add_node(middle, 14);

    //     _ = try self.add_node(root, 15);
    //     _ = try self.add_node(root, 10);
    //     _ = try self.add_node(root, 28);
    //     // try n.add_child(24);
    //     // try n.add_child(31);
    //     // try n.add_child(27);
    //     // try n.add_child(14);
    //     // try n.add_child(28);
    //     // try n.add_child(1);
    //     root.print();
    // }



    // /// Validate and encode unicode string into a CharCode arraylist.\
    // fn encode_word(self: *Gaddag, word: []const u8) !std.ArrayList(CharCode) // []CharCode
    // {
    //     //var buf: [32]CharCode = undefined;
    //     var result = try std.ArrayList(CharCode).initCapacity(allocator, 32);
    //     errdefer result.deinit();

    //     var it = try utils.unicode_iterator(word);
    //     while (it.nextCodepoint()) |cp|
    //     {
    //         //const normalized: u21 = normalize(cp);
    //         const cc: CharCode = try self.settings.codepoint_to_charcode(cp);
    //         //buf[len] = cc;
    //         if (cc == 0) break;
    //         result.appendAssumeCapacity(cc);
    //     }
    //     //buf[len - 1] = 0;
    //     //length.* = len - 1;
    //     return result;
    // }
