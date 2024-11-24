// https://ziggit.dev/t/is-there-an-iterator-for-slices-in-the-standard-library/620/2
// https://en.algorithmica.org/hpc/

// TODO check file against valid setting letters during load.
// TODO we do not have to work with node pointers, except when building.
//      make the pointer stuff private and use node copies for public.

/// TODO: write public get *const pointers, instead of returning a struct??

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const utils =  @import("utils.zig");
const scrabble =  @import("scrabble.zig");

const ScrabbleError = scrabble.ScrabbleError;
const Char = scrabble.Char;
const CharCode = scrabble.CharCode;
const CharCodeMask = scrabble.CharCodeMask;
const Settings = scrabble.Settings;

pub fn load_debug_graph(allocator: std.mem.Allocator, settings: *const Settings) !Graph
{
    std.debug.print("loading debug graph...\n", .{});
    var graph: Graph = try Graph.init(allocator, settings, 16);
    errdefer graph.deinit();
    try graph.add_word_rotated("de");
    //try graph.add_word_rotated("zd");
    try graph.add_word_rotated("azen");
    try graph.add_word_rotated("azend");
    try graph.add_word_rotated("zen");
    try graph.add_word_rotated("zend");
    try graph.after_loading();
    return graph;
}

pub fn load_graph_from_text_file(filename: []const u8, allocator: std.mem.Allocator, settings: *const Settings) !Graph
{
    std.debug.print("loading graph from file...\n", .{});

    // load text file in memory.
    const file: std.fs.File = try std.fs.openFileAbsolute(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const file_size = stat.size;

    const file_buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_buffer);

    var graph: Graph = try Graph.init(allocator, settings, file_size);
    errdefer graph.deinit();

    // Read line by line
    var it = std.mem.splitAny(u8, file_buffer, &.{13, 10});
    while (it.next()) |word|
    {
        if (word.len == 0) continue; // skip empty (split any is a bit strange)
        try graph.add_word_rotated(word);
    }

    try graph.after_loading();

    // check if we can find all words.
    var timer: std.time.Timer = try std.time.Timer.start();
    it.reset();
    var found: u32 = 0;
    while (it.next()) |word|
    {
        if (word.len == 0) continue; // skip empty (split any is a bit strange)
        if (!graph.word_exists(word))
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

pub fn save_graph_to_file(graph: *Graph, filename: []const u8,) !void
{
    var file = try std.fs.createFileAbsolute(filename, .{});
    defer file.close();
    var writer = std.io.bufferedWriter(file.writer());
    const bytes = std.mem.sliceAsBytes(graph.nodes.items);
    const written: usize = try writer.write(bytes);
    _ = written;
    // Ensure all data is flushed to the file
    try writer.flush();
}

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
/// The character before the "+" is marked as is_bow. A bow-node is inserted at index 0 of the children.\
/// The character "i" at #8 is marked as is_whole_word.\
/// All suffixes which are a whole word contain the flag is_eow.
pub const Graph = struct
{
    allocator: std.mem.Allocator,
    settings: *const Settings,
    nodes: std.ArrayList(Node),
    freelists: [32]std.ArrayList(u32),
    word_count: u32,
    node_count: u32,
    wasted: u32,

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings, initial_capacity: usize) !Graph
    {
        return Graph
        {
            .allocator = allocator,
            .settings = settings,
            .nodes = try create_nodes(allocator, initial_capacity),
            .freelists = try create_freelists(allocator),
            .word_count = 0,
            .node_count = 1,
            .wasted = 0,
        };
    }

    /// Create the node list + root
    fn create_nodes(allocator: std.mem.Allocator, initial_capacity: usize) !std.ArrayList(Node)
    {
        var result: std.ArrayList(Node) = try std.ArrayList(Node).initCapacity(allocator, initial_capacity);
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
        for (0..32) |i| self.freelists[i].deinit();
        self.nodes.deinit();
    }

    // TODO get rid of the get_freelist function.
    pub fn after_loading(self: *Graph) !void
    {
        for(1..32) |i|
        {
            const freelist = self.get_freelist(@intCast(i));
            self.wasted += @truncate(freelist.items.len * i);
            for (freelist.items) |idx|
            {
                @memset(self.nodes.items[idx..idx + i], Node.INVALIDNODE);
            }
        }

        for (0..32) |i|
        {
            var freelist = self.get_freelist(@intCast(i));
            freelist.clearAndFree();
        }

        var timer: std.time.Timer = try std.time.Timer.start();

        for (0..self.nodes.items.len) |i|
        {
            const node: Node = self.get_node_by_index(@intCast(i));
            if (node.count > 0)
            {
                const slice = self.nodes.items[node.child_ptr..node.child_ptr + node.count];
                std.mem.sortUnstable(Node, slice, {}, less_than);
            }
        }
        const elapsed = timer.lap();
        print("sorttime ms {} nanos {} \n", .{ elapsed / 1000000, elapsed });

       //try self.nodes.ensureTotalCapacityPrecise(self.nodes.items.len);// shrinkRetainingCapacity(self.nodes.items.len);
        //print("len {} cap {}", .{ self.nodes.items.len, self.nodes.capacity });
    }

    fn less_than(_: void, a: Node, b: Node) bool
    {
        return a.data.code < b.data.code;
    }

    pub fn as_bytes(self: *Graph) []const u8
    {
        return std.mem.sliceAsBytes(self.nodes.items);
    }

    /// This is just the first node.
    pub fn get_rootnode(self: *Graph) Node
    {
        return self.get_node_by_index(0);
    }

    /// Gets a child from the root. Note that the return value is *not* a bownode but a prefix (used for backward tracking).
    pub fn find_root_entry(self: *Graph, charcode: CharCode) ?Node
    {
        return self.find_node(self.get_rootnode(), charcode);
    }

    /// Direct get.
    pub fn get_node_by_index(self: *Graph, idx: u32) Node
    {
        assert(idx < self.nodes.items.len);
        return self.nodes.items[idx];
    }

    /// Key method. Using the node mask to directly convert it to an index. This only works if the nodes are sorted.
    /// Thanks to Zigmaster Sze
    pub fn find_node(self: *Graph, parentnode: Node, charcode: CharCode) ?Node
    {
        const charcode_mask: u32 = get_mask(charcode);
        if (parentnode.mask & charcode_mask == 0) return null;
        const index = @popCount(parentnode.mask & (charcode_mask -% 1));
        return self.nodes.items[parentnode.child_ptr + index];

        // The below code is sequential
        // if (parentnode.count == 0) return null;
        // const children = self.nodes.items[parentnode.child_ptr..parentnode.child_ptr + parentnode.count];
        // for(children) |run|
        // {
        //     //print("(find)searching {} actual {}\n", .{charcode, run.data.code});
        //     if (run.data.code == charcode) return run;
        // }
        // return null;
    }

    /// Gets the bow node (only if this node has the is_bow flag set). The bow node is always the first child.
    pub fn get_bow(self: *Graph, parentnode: Node) ?Node
    {
        if (parentnode.count == 0 or !parentnode.data.is_bow) return null;
        return self.get_node_by_index(parentnode.child_ptr);
    }

    // pub fn find_node_by_mask(self: *Graph, parentnode: Node, charcode: CharCode) ?Node
    // {
    //     const charcode_mask: u32 = get_mask(charcode);
    //     if (parentnode.mask & charcode_mask == 0) return null;
    //     const index = @popCount(parentnode.mask & (charcode_mask -% 1));
    //     return self.nodes.items[parentnode.child_ptr + index];
    // }

    /// Gets a direct slice to the child nodes.
    pub fn get_children(self: *Graph, parentnode: Node) []const Node
    {
        return self.nodes.items[parentnode.child_ptr..parentnode.child_ptr + parentnode.count];
    }

    pub fn word_exists(self: *Graph, word: []const u8) bool
    {
        return self.find_word(word) != null;
    }

    // TODO: we also want a codepoint_to_charcode which is a bit faster, if possible
    pub fn find_word(self: *Graph, word: []const u8) ?*Node
    {
        if (word.len == 0) return null;
        const fc: CharCode = self.settings.codepoint_to_charcode(word[0]) catch return null;
        var node = self.find_node_ptr_unsorted(self.get_rootnode_ptr(), fc) orelse return null;
        node = self.get_bow_ptr(node) orelse return null;
        for(word[1..]) |cp|
        {
            const cc: CharCode = self.settings.codepoint_to_charcode(cp) catch return null;
            node = self.find_node_ptr_unsorted(node, cc) orelse return null;
        }
        return node; // TODO: check is_eow
    }

    /// private
    fn get_rootnode_ptr(self: *Graph) *Node
    {
        return self.get_node_ptr_by_index(0);
    }

    /// private
    fn get_node_ptr_by_index(self: *Graph, idx: u32) *Node
    {
        assert(idx < self.nodes.items.len);
        return &self.nodes.items[idx];
    }

    /// private
    fn get_bow_ptr(self: *Graph, parentnode: *Node) ?*Node
    {
        if (parentnode.count == 0 or !parentnode.data.is_bow) return null;
        return self.get_node_ptr_by_index(parentnode.child_ptr);
    }

    /// private
    fn add_word_rotated(self: *Graph, word: []const u8) !void
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

            //std.debug.print("{any}\n", .{prefix});

            var node: *Node = self.get_rootnode_ptr();
            for (0..prefix.len) |j|
            {
                node = try self.add_or_get_node(node, prefix.get(j), false);

                // at the end of the prefix.
                if (j == prefix.len - 1)
                {
                    if (prefix.len == word_len) node.data.is_whole_word = true;
                    //node.data.is_bow = true;
                    var bow_node = self.get_bow_ptr(node);
                    if (bow_node == null)
                    {
                        node.data.is_bow = true;
                        bow_node = try self.add_node(node, 0, true); // add begin of word node at the beginning
                    }
                    var suffix = bow_node orelse return ScrabbleError.GaddagBuildError;
                    for (j + 1..word_len) |k|
                    {
                        suffix = try self.add_or_get_node(suffix, buf.get(k), false);
                        if (k == word_len - 1) suffix.data.is_eow = true; // mark end of word
                    }
                }
            }
        }
    }

    /// private
    fn encode_word(self: *Graph, word: []const u8) !std.BoundedArray(CharCode, 32)
    {
        var buf = try std.BoundedArray(CharCode, 32).init(0);
        for (word) |u|
        {
            buf.appendAssumeCapacity(try self.settings.codepoint_to_charcode(u));
        }
        return buf;
    }

    /// private
    fn find_node_ptr_unsorted(self: *Graph, parentnode: *Node, charcode: CharCode) ?*Node
    {
        if (parentnode.count == 0) return null;
        const children = self.nodes.items[parentnode.child_ptr..parentnode.child_ptr + parentnode.count];
        for(children) |*run|
        {
            if (run.data.code == charcode) return run;
        }
        return null;
    }

    /// private
    fn add_or_get_node(self: *Graph, parentnode: *Node, charcode: CharCode, comptime is_bow: bool) !*Node
    {
        if (self.find_node_ptr_unsorted(parentnode, charcode)) |node|
        {
            return node;
        }
        return try self.add_node(parentnode, charcode, is_bow);
    }

    /// private
    fn add_node(self: *Graph, parentnode: *Node, charcode: CharCode, comptime is_bow: bool) !*Node
    {
        self.node_count += 1;

        const mask: u32 = get_mask(charcode);
        const new_node = Node.init(charcode);
        const old_index: u32 = parentnode.child_ptr;
        const old_count = parentnode.count;
        const new_count = old_count + 1;
        const freelist = self.get_freelist(new_count);
        //assert(old_count < 28);
        // If we have freespace use that.
        if (freelist.items.len > 0)
        {
            const free_idx: u32 = freelist.pop(); // this is the free index with enough space
            const new_idx: u32 = if (is_bow == false) free_idx + old_count else free_idx;
            const copy_idx: u32 = if (is_bow == false) free_idx else free_idx + 1;

            parentnode.child_ptr = free_idx;
            parentnode.count = new_count;
            parentnode.mask |= mask;

            if (old_count > 0) @memcpy(self.nodes.items[copy_idx..copy_idx + old_count], self.nodes.items[old_index..old_index + old_count]);
            self.nodes.items[new_idx] = new_node;
            return self.get_node_ptr_by_index(new_idx);
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
            parentnode.mask |= mask;

            // Append space at the end.
            try self.nodes.appendNTimes(Node.EMPTYNODE, new_count);
            if (old_count > 0) @memcpy(self.nodes.items[copy_idx..copy_idx + old_count], self.nodes.items[old_index..old_index + old_count]);
            self.nodes.items[new_idx] = new_node;
            return self.get_node_ptr_by_index(new_idx);
        }
    }

    /// private
    fn get_freelist(self: *Graph, length: u8) *std.ArrayList(u32)
    {
        return &self.freelists[length];
    }

    /// private
    fn get_mask(charcode: CharCode) u32
    {
        return @as(u32, 1) << charcode;
    }

    /// TODO: more testing
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

/// 10 bytes with mask. 6 byte without mask. TODO: we could squeeze 6 into 5 if we limit to 65 million nodes.
pub const Node = extern struct
{
    pub const EMPTYNODE: Node = Node.init(0);

    /// When cleaning up the graph, we fill the unused nodes (from the remaining freelists) with invalid nodes.
    pub const INVALIDNODE: Node = Node.invalidnode();

    pub const Data = packed struct
    {
        /// The 5 bits character code
        code: CharCode = 0,
        /// Is this node the beginning of a word?
        is_bow: bool = false,
        /// Is this node the end of a word?
        is_eow: bool = false,
        /// Is this node a whole word?
        is_whole_word: bool = false,
    };

    /// Our 1 byte node data
    data: Data align(1),
    /// maximum count is 32
    count: u8 align(1),
    /// Index into Graph.nodes. Children are always sequential in memory.
    child_ptr: u32 align(1),
    // The charcode mask of children (not yet decided if we need that, probably not)
    mask: u32 align(1),
    // TODO: to make the mask working children should be sorted.
    // TODO check out performance when @popcounting the addres from here.
    // TODO try building the graph with children directly behind the parent. this would save us the child_ptr.
    // TODO the count can disappear and replaced by popcount.

    fn init(charcode: CharCode) Node
    {
        return Node {.data = Data {.code = charcode }, .count = 0, .child_ptr = 0, .mask = 0};
    }

    fn invalidnode() Node
    {
        return Node
        {
            .data = Data {},
            .count = 0,
            .child_ptr = 0xffffffff,
            .mask = 0,
        };
    }

    pub fn get_charcode_mask(self: *const Node) CharCodeMask
    {
        return @bitCast(self.mask);
    }

    pub fn get_not_charcode_mask(self: *const Node) CharCodeMask
    {
        return @bitCast(~self.mask);
    }
};

    // pub fn debug_find_word(self: *Graph, word: []const u8) void
    // {
    //     const root = self.get_rootnode();
    //     print("ROOT   : _ is_bow: {} is_eow: {} is_whole: {} childcount: {} childptr: {}\n", .{root.data.is_bow, root.data.is_eow, root.data.is_whole_word, root.count, root.child_ptr});
    //     if (word.len == 0) return;
    //     const fc: CharCode = self.settings.codepoint_to_charcode(word[0]) catch return;
    //     var node = self.find_node_ptr(self.get_rootnode_ptr(), fc) orelse return;
    //     print("ENTER  : {c} is_bow: {} is_eow: {} is_whole: {} childcount: {} childptr: {}\n", .{word[0], node.data.is_bow, node.data.is_eow, node.data.is_whole_word, node.count, node.child_ptr});
    //     node = self.get_bow_ptr(node) orelse return;
    //     print("BOWNODE: _ is_bow: {} is_eow: {} is_whole: {} childcount: {} childptr: {}\n", .{ node.data.is_bow, node.data.is_eow, node.data.is_whole_word, node.count, node.child_ptr});
    //     for(word[1..]) |cp|
    //     {
    //         const cc: CharCode = self.settings.codepoint_to_charcode(cp) catch return;
    //         node = self.find_node_ptr(node, cc) orelse return;
    //         print("PATH   : {c} is_bow: {} is_eow: {} is_whole: {} childcount: {} childptr: {}\n", .{cp, node.data.is_bow, node.data.is_eow, node.data.is_whole_word, node.count, node.child_ptr});
    //     }
    // }

    // pub fn find_raw_word(self: *Graph, word: []const u8) ?*Node
    // {
    //     if (word.len == 0) return null;
    //     const fc: CharCode = self.settings.codepoint_to_charcode(word[0]) catch return null;
    //     var node = self.find_node_ptr(self.get_rootnode_ptr(), fc) orelse return null;
    //     for(word[1..]) |cp|
    //     {
    //         const cc: CharCode = self.settings.codepoint_to_charcode(cp) catch return null;
    //         node = self.find_node_ptr(node, cc) orelse return null;
    //     }
    //     return node;
    // }


    // pub fn find_raw(self: *Graph, charcodes: []const CharCode) ?*Node
    // {
    //     var node = self.get_rootnode_ptr();
    //     if (node.count == 0) return null;// or !parentnode.mask.isSet(charcode)) return null;
    //     for (charcodes) |cc|
    //     {
    //         node = self.find_node_ptr(node, cc) orelse return null;
    //     }
    //     return node;
    // }



    // fn find_node_ptr_by_mask(self: *Graph, parentnode: *Node, charcode: CharCode) ?*Node
    // {
    //     const charcode_mask = get_mask(charcode);
    //     if (parentnode.mask & charcode_mask == 0) return null;
    //     const m = parentnode.mask & get_mask(charcode);
    //     if (m == 0) return null;
    //     const index = @popCount(parentnode.mask & (charcode_mask -% 1));
    //     return &self.nodes.items[parentnode.child_ptr + index];
    // }
