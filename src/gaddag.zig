
const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const utils =  @import("utils.zig");
const scrabble =  @import("scrabble.zig");

const ScrabbleError = scrabble.ScrabbleError;
const Char = scrabble.Char;
const CharCode = scrabble.CharCode;
const Settings = scrabble.Settings;

pub fn load_graph_from_text_file(filename: []const u8, allocator: std.mem.Allocator, settings: *const Settings) !Graph
{
    std.debug.print("loading...\n", .{});

    // load text file in memory.
    const file = try std.fs.openFileAbsolute(filename, .{});
    defer file.close();

    const file_buffer = try file.readToEndAlloc(allocator, 8000000);
    defer allocator.free(file_buffer);

    var graph: Graph = try Graph.init(allocator, settings);
    errdefer graph.deinit();

    // Read line by line
    var it = std.mem.splitAny(u8, file_buffer, &.{13, 10});
    while (it.next()) |word|
    {
        if (word.len == 0) continue; // skip empty (split any is a bit strange)
        try graph.add_word_rotated(word);
    }
    graph.cleanup_free_space();

    // check if we can find all words.
    var timer: std.time.Timer = try std.time.Timer.start();
    it.reset();
    var found: u32 = 0;
    while (it.next()) |word|
    {
        if (word.len == 0) continue; // skip empty (split any is a bit strange)
        if (!graph.find_word(word))
        {
            print("word not found {s}", .{word});
            break;
        }
        found += 1;
    }
    const elapsed = timer.lap();
    print("search all {} time ms {}\n", .{ found, elapsed / 1000000 });

    return graph;
}

pub const NodeData = packed struct
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

pub const Node = extern struct
{
    const EMPTYNODE: Node = Node.init(0);
    //const INVALIDNODE: Node = Node.invalidnode();

    data: NodeData align(1), // 8 bits
    count: u8 align(1), // up to 32
    child_ptr: u32 align(1), // index into Graph.nodes.

    fn init(charcode: CharCode) Node
    {
        return Node {.data = NodeData.init(charcode), .count = 0, .child_ptr = 0 };
    }

    fn invalidnode() Node
    {
        return Node
        {
            .data = NodeData.init(0),
            .count = 0,
            .child_ptr = 0xffffffff,
        };
    }
};


pub const Graph = struct
{
    allocator: std.mem.Allocator,
    settings: *const Settings,
    nodes: std.ArrayList(Node),
    freelists: [32]std.ArrayList(u32),
    word_count: u32,
    node_count: u32,
    wasted: u32,

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings) !Graph
    {
        return Graph
        {
            .allocator = allocator,
            .settings = settings,
            .nodes = try create_nodes(allocator),
            .freelists = try create_freelists(allocator),
            .word_count = 0,
            .node_count = 1,
            .wasted = 0,
        };
    }

    fn create_nodes(allocator: std.mem.Allocator) !std.ArrayList(Node)
    {
        var result: std.ArrayList(Node) = try std.ArrayList(Node).initCapacity(allocator, 8192);
        result.appendAssumeCapacity(Node.EMPTYNODE);
        return result;
    }

    fn create_freelists(allocator: std.mem.Allocator) ![32]std.ArrayList(u32)
    {
        var result: [32]std.ArrayList(u32) = undefined;
        for (0..32) |i|
        {
            if (i > 0)
            {
                result[i] = try std.ArrayList(u32).initCapacity(allocator, 32); // this was the max used we found.
            }
            else
            {
                result[i] = std.ArrayList(u32).init(allocator); // this is an unused dummy
            }
        }
        return result;
    }

    pub fn deinit(self: *Graph) void
    {
        for (0..32) |i|
        {
            self.freelists[i].deinit();
        }
        self.nodes.deinit();
    }

    fn cleanup_free_space(self: *Graph) void
    {
        for(1..32) |i|
        {
            const freelist = self.get_freelist(@intCast(i));
            self.wasted += @truncate(freelist.items.len * i);
            for (freelist.items) |idx|
            {
                @memset(self.nodes.items[idx..idx + i], Node.EMPTYNODE);
            }
        }

        for (0..32) |i|
        {
            var freelist = self.get_freelist(@intCast(i));
            freelist.clearAndFree();
        }
    }

    fn get_node(self: *Graph, idx: u32) *Node
    {
        assert(idx < self.nodes.items.len);
        return &self.nodes.items[idx];
    }

    pub fn get_root(self: *Graph) *Node
    {
        return self.get_node(0);
    }

    fn get_bow(self: *Graph, parentnode: *Node) ?*Node
    {
        if (parentnode.count == 0) return null;
        return self.get_node(parentnode.child_ptr);
    }

    pub fn add_word_rotated(self: *Graph, word: []const u8) !void
    {
        self.word_count += 1; // TODO: we are not 100% sure, the word could be a duplicate

        const buf = try self.encode_word(word);
        const word_len: usize = word.len;
        var prefix = try std.BoundedArray(CharCode, 32).init(0);

        for (0..word_len) |i|
        {
            try prefix.resize(0);
            prefix.appendSliceAssumeCapacity(buf.slice()[0..i + 1]);
            std.mem.reverse(CharCode, prefix.slice());

            var node: *Node = self.get_root();
            for (0..prefix.len) |j|
            {
                node = try self.add_or_get_node(node, prefix.get(j), false);

                // at the end of the prefix.
                if ( j == prefix.len - 1)
                {
                    if (prefix.len == word_len)
                    {
                        node.data.is_whole = true;
                    }
                    node.data.is_bow = true;
                    var bow_node = self.get_bow(node);
                    if (bow_node == null)
                    {
                        bow_node = try self.add_node(node, 0, true); // add begin of word node at the beginning
                    }
                    var suffix = bow_node orelse return ScrabbleError.GaddagBuildError;
                    for (j + 1..word_len) |k|
                    {
                        suffix = try self.add_or_get_node(suffix, buf.get(k), false);
                        if (k == word_len - 1)
                        {
                            suffix.data.is_eow = true; // mark end of word
                        }
                    }
                }

            }
        }
    }

    fn encode_word(self: *Graph, word: []const u8) !std.BoundedArray(CharCode, 32)
    {
        var buf = try std.BoundedArray(CharCode, 32).init(0);
        for (word) |u|
        {
            buf.appendAssumeCapacity(try self.settings.codepoint_to_charcode(u));
        }
        return buf;
    }

    pub fn find_word(self: *Graph, word: []const u8) bool
    {
        if (word.len == 0) return false;
        const fc: CharCode = self.settings.codepoint_to_charcode(word[0]) catch return false;
        var node: *Node = self.get_root();
        node = self.find_node(node, fc) orelse return false;
        node = self.get_bow(node) orelse return false;

        for(word[1..]) |cp|
        {
            const cc: CharCode = self.settings.codepoint_to_charcode(cp) catch return false;
            node = self.find_node(node, cc) orelse return false;
        }
        return true;
    }

    fn find_node(self: *Graph, parentnode: *Node, charcode: CharCode) ?*Node
    {
        if (parentnode.count == 0) return null;
        const children = self.nodes.items[parentnode.child_ptr..];
        for(0..parentnode.count) |i|
        {
            const run: *Node = &children[i];
            if (run.data.code == charcode) return run;
        }
        return null;
    }

    fn add_or_get_node(self: *Graph, parentnode: *Node, charcode: CharCode, comptime is_bow: bool) !*Node
    {
        if (self.find_node(parentnode, charcode)) |node|
        {
            return node;
        }
        return try self.add_node(parentnode, charcode, is_bow);
    }

    fn add_node(self: *Graph, parentnode: *Node, charcode: CharCode, comptime is_bow: bool) !*Node
    {
        self.node_count += 1;

        //const or_mask: u32 = get_mask(charcode);
        const new_node = Node.init(charcode);
        const old_index: u32 = parentnode.child_ptr;
        const old_count = parentnode.count;
        const new_count = old_count + 1;
        const freelist = self.get_freelist(new_count);

        // If we have freespace use that.
        if (freelist.items.len > 0)
        {
            const free_idx = freelist.pop();
            const new_idx: u32 = if (is_bow == false) free_idx + old_count else free_idx;
            const copy_idx: u32 = if (is_bow == false) free_idx else free_idx + 1;

            parentnode.child_ptr = free_idx;
            parentnode.count = new_count;

            if (old_count > 0) @memcpy(self.nodes.items[copy_idx..copy_idx + old_count], self.nodes.items[old_index..old_index + old_count]);
            self.nodes.items[new_idx] = new_node;
            return self.get_node(new_idx);
        }
        // Otherwise append to nodes.
        else
        {
            // Store space for later re-use.
            if (old_count > 0)
            {
                const oldlist = self.get_freelist(old_count);
                try oldlist.append(parentnode.child_ptr);
            }
            const free_idx: u32 = @truncate(self.nodes.items.len);
            const new_idx: u32 = if (is_bow == false) free_idx + old_count else free_idx;
            const copy_idx: u32 = if (is_bow == false) free_idx else free_idx + 1;

            parentnode.count = new_count;
            parentnode.child_ptr = free_idx;

            // Append space at the end.
            try self.nodes.appendNTimes(Node.EMPTYNODE, new_count);
            if (old_count > 0) @memcpy(self.nodes.items[copy_idx..copy_idx + old_count], self.nodes.items[old_index..old_index + old_count]);
            self.nodes.items[new_idx] = new_node;
            return self.get_node(new_idx);
        }
    }

    /// Internal unsafe routine: get the last child char of the parentnode.
    fn last_char(self: *Graph, parentnode: *Node) CharCode
    {
        return self.get_node(parentnode.child_ptr + parentnode.count - 1).charcode;
    }

    fn get_freelist(self: *Graph, length: u8) *std.ArrayList(u32)
    {
        return &self.freelists[length];
    }

    fn get_mask(charcode: CharCode) u32
    {
        return @as(u32, 1) << charcode;
    }

    pub fn validate(self: *Graph) !void
    {
        const len = self.nodes.items.len;
        for (self.nodes.items) |*node|
        {
            if (node.count == 0) continue;
            const idx: u32 = node.child_ptr;
            if (idx >= len)
            {
                return ScrabbleError.GaddagValidationFailed;
            }
            if (idx + node.count > len)
            {
                return ScrabbleError.GaddagValidationFailed;
            }
        }
    }
};

// Let's take the word "instances". it is added to the tree as follows:\
// `1. i + nstances`\
// `2. ni + stances`\
// `3. sni + tances`\
// `4. tsni + ances`\
// `5. atsni + nces`\
// `6. natsni + ces`\
// `7. cnatsni + es`\
// `7. ecnatsni + s`\
// `8. secnatsni`\
// The character before the "+" is marked as is_bow. A bow-node is inserted at index 0 of the children.\
// The character "i" at #8 is marked as is_whole.

