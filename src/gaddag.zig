// https://ziggit.dev/t/is-there-an-iterator-for-slices-in-the-standard-library/620/2
// https://en.algorithmica.org/hpc/

// TODO check file against valid setting letters during load.

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

pub fn load_graph_from_text_file(filename: []const u8, allocator: std.mem.Allocator, settings: *const Settings) !Graph
{
    std.debug.print("loading graph from file...\n", .{});

    var timer: std.time.Timer = try std.time.Timer.start();

    // load text file in memory.
    const file: std.fs.File = try std.fs.openFileAbsolute(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const file_size = stat.size;

    const file_buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_buffer);

    const read_file_time = timer.lap();
    timer.reset();

    var graph: Graph = try Graph.init(allocator, settings, file_size);
    errdefer graph.deinit();

    // Read line by line
    var it = std.mem.splitAny(u8, file_buffer, &.{13, 10}); // TODO: make a byte + unicode version depending on settings.
    while (it.next()) |word|
    {
        //std.debug.print("[{s}]\n", .{word});
        //if (word.len == 0) continue; // skip empty (split any is a bit strange)
        try graph.add_word(word); // TODO: just skip invalid words
    }

    const building_time = timer.lap();
    timer.reset();

    try graph.after_loading();

    const sorting_time = timer.lap();
    timer.reset();

    // check if we can find all words.
    it.reset();
    var found: u32 = 0;
    while (it.next()) |word|
    {
        if (word.len < 2) continue;
        if (!graph.word_exists(word))
        {
            print("word not found {s}\n", .{word});
            break;
        }
        found += 1;
    }
    const search_time = timer.lap();

    print("read file time ms = {}, nanos = {} \n", .{ read_file_time / 1000000, read_file_time });
    print("building_time ms = {}, nanos = {} \n", .{ building_time / 1000000, building_time });
    print("sorttime ms = {}, nanos = {} \n", .{ sorting_time / 1000000, sorting_time });
    print("search all count = {}, time ms = {}, nanos = {}\n", .{ found, search_time / 1000000, search_time });
    print("number of words = {}, number of nodes = {}\n", .{graph.word_count, graph.nodes.items.len});

    return graph;
}

pub fn save_graph_to_bin_file(graph: *Graph, filename: []const u8) !void
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

/// TODO: try read directly into nodes memory.
pub fn load_graph_from_bin_file(filename: []const u8, allocator: std.mem.Allocator, settings: *const Settings) !Graph
{
     // load text file in memory.
    const file: std.fs.File = try std.fs.openFileAbsolute(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const file_size = stat.size;

    const file_buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_buffer);

    return Graph.load(allocator, settings, file_buffer);
}

/// The Graph is only usable after calling `after_loading`.
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
    freelists: [32]std.ArrayList(u32), // TODO: we should have an array of arraylist to save memory, not needed after building.
    word_count: u32,
    wasted: u32,

    pub fn init(allocator: std.mem.Allocator, settings: *const Settings, initial_capacity: usize) !Graph
    {
        return Graph
        {
            .allocator = allocator,
            .settings = settings,
            .nodes = try create_nodes(allocator, initial_capacity),
            .freelists = try create_freelists(allocator, 128),
            .word_count = 0,
            .wasted = 0,
        };
    }

    fn load(allocator: std.mem.Allocator, settings: *const Settings, bin: []const u8) !Graph
    {
        return Graph
        {
            .allocator = allocator,
            .settings = settings,
            .nodes = try load_nodes(allocator, bin),
            .freelists = try create_freelists(allocator, 0),
            .word_count = 0,
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

    // There is also simpler option (if you storing just one array in file) to use bytesAsSlice on the file content to get slice of your type. And then use std.array_list.ArrayListAligned.fromOwnedSlice
    fn load_nodes(allocator: std.mem.Allocator, bin: []const u8) !std.ArrayList(Node)
    {
        const initial_capacity: usize = bin.len / Node.STRUCTSIZE;
        //std.debug.print("cap {} len {} nodesize {} mod {}\n", .{initial_capacity, bin.len, Node.STRUCTSIZE, bin.len % Node.STRUCTSIZE});
        assert(bin.len % Node.STRUCTSIZE == 0);
        var result: std.ArrayList(Node) = try std.ArrayList(Node).initCapacity(allocator, initial_capacity);
        result.items.len = initial_capacity;
        const bytes = std.mem.sliceAsBytes(result.items);
        @memcpy(bytes, bin);
        return result;
    }

    // pub fn as_bytes(self: *Graph) []const u8
    // {
    //     return std.mem.sliceAsBytes(self.nodes.items);
    // }

    fn create_freelists(allocator: std.mem.Allocator, freelists_initial_capacity: usize) ![32]std.ArrayList(u32)
    {
        var result: [32]std.ArrayList(u32) = undefined;
        for (0..32) |i|
        {
            if (i > 0)
            {
                result[i] = try std.ArrayList(u32).initCapacity(allocator, freelists_initial_capacity); // this was the max used we found.
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
                //print("freeing #{} {} len {}\n", .{i, idx, i});
                @memset(self.nodes.items[idx..idx + i], Node.INVALIDNODE);
            }
        }

        for (0..32) |i|
        {
            var freelist = self.get_freelist(@intCast(i));
            freelist.clearAndFree();
        }

        // Sort all (valid) children.
        const len = self.nodes.items.len;
        for (0..len) |i|
        {
            const node: *const Node = self.get_node_by_index(@intCast(i));
            if (node.count > 1)
            {
                const slice = self.nodes.items[node.child_ptr..node.child_ptr + node.count];
                std.mem.sortUnstable(Node, slice, {}, less_than);
            }
        }
        // TODO: shrink capacity.
    }

    /// private for sorting childnodes
    fn less_than(_: void, a: Node, b: Node) bool
    {
        return a.data.code < b.data.code;
    }

    /// TODO: there seems to be a little BUG i did not manage to track yet....
    pub fn validate(self: *Graph) !void
    {
        const len = self.nodes.items.len;

        //for (0..self.nodes.items.len self.nodes.items, 0..) |node, idx|
        for (0..len) |idx|
        {
            //if (idx > 50) break;
            const node = self.nodes.items[idx];
            if (node.count == 0) continue;
            //print("NODE {} code [{}], children {} bow {} eow {} whole {} ptr {}\n", .{idx, node.data.code, node.count, node.data.is_bow, node.data.is_eow, node.data.is_whole_word, node.child_ptr});

            const child_idx: u32 = node.child_ptr;
            if (child_idx >= len)
            {
                return ScrabbleError.GaddagValidationFailed;
            }
            if (child_idx + node.count > len)
            {
                return ScrabbleError.GaddagValidationFailed;
            }

            if (node.count > 32)
            {
                return ScrabbleError.GaddagValidationFailed;
            }

            if (@popCount(node.mask) != node.count)
            {
                return ScrabbleError.GaddagValidationFailed;
            }

            // // //std.debug.print("\nidx {} code {} cnt {}\n", .{idx, node.data.code, node.count});
            // var cmask: CharCodeMask = CharCodeMask.initEmpty();//.{};//node.get_charcode_mask();// @bitCast(node.mask);
            // cmask.mask = node.mask;
            // // var offset: u32 = child_idx;
            // var iter = cmask.iterator(.{});
            // while (iter.next()) |bit|
            // {
            // //     print("{}/", .{bit});
            //      const c: CharCode = @intCast(bit);
            //     if (c == 0)
            //         std.debug.print("#/", .{})
            //     else
            //         std.debug.print("{c}/", .{self.settings.code_to_char(c)});

            //     if (self.find_node(node, c) == null) std.debug.print("(WTF)", .{});
            //     const check: Node = self.find_node(node, c) orelse Node.INVALIDNODE;
            //     if (check.data.code != c)
            //         std.debug.print("(WTF)", .{});
            // }
            // print("\n", .{});

            // const children = self.get_children(node);
            // for(children) |c|
            // {
            //     if (c.data.code == 0)
            //         std.debug.print("#/", .{})
            //     else
            //         std.debug.print("{c}/", .{self.settings.code_to_char(c.data.code)});
            // }
            // print("\n", .{});

        }
    }

    /// Direct get.
    pub fn get_node_by_index(self: *const Graph, idx: u32) *const Node
    {
        assert(idx < self.nodes.items.len);
        return &self.nodes.items[idx];
    }

    /// This is just the first node.
    pub fn get_rootnode(self: *const Graph) *const Node
    {
        return self.get_node_by_index(0);
    }

    /// Gets a child from the root. Note that the return value is *not* a bownode but a prefix (used for backward tracking).
    pub fn find_node_from_root(self: *const Graph, charcode: CharCode) ?*const Node
    {
        return self.find_node(self.get_rootnode(), charcode);
    }

    /// Key method. Using the node mask to directly convert it to an index. This only works if the childnodes are sorted.
    /// Thanks to Zig master Sze
    pub fn find_node(self: *const Graph, parentnode: *const Node, charcode: CharCode) ?*const Node
    {
        const charcode_mask: u32 = get_mask(charcode);
        if (parentnode.mask & charcode_mask == 0) return null;
        const index = @popCount(parentnode.mask & (charcode_mask -% 1));
        return &self.nodes.items[parentnode.child_ptr + index];
    }

    /// Sequential search. Debug only.
    pub fn find_node_unsorted(self: *const Graph, parentnode: *const Node, charcode: CharCode) ?*const Node
    {
        if (parentnode.count == 0) return null;
        const children = self.nodes.items[parentnode.child_ptr..parentnode.child_ptr + parentnode.count];
        for(children) |run| if (run.data.code == charcode) return run;
        return null;
    }

    /// Gets the bow node (only if this node has the is_bow flag set). The bow node is always the first child.
    pub fn get_bow(self: *const Graph, parentnode: *const Node) ?*const Node
    {
        if (parentnode.count == 0 or !parentnode.data.is_bow) return null;
        return self.get_node_by_index(parentnode.child_ptr);
    }

    /// Gets a direct slice to the child nodes.
    pub fn get_children(self: *const Graph, parentnode: *const Node) []const Node
    {
        return self.nodes.items[parentnode.child_ptr..parentnode.child_ptr + parentnode.count];
    }

    pub fn get_children_ptr(self: *const Graph, parentnode: *const Node) *const Node
    {
        return &self.nodes.items[parentnode.child_ptr];
    }

    pub fn word_exists(self: *const Graph, word: []const u8) bool
    {
        return self.find_word(word) != null;
    }

    pub fn encoded_word_exists(self: *const Graph, encoded_word: []const CharCode) bool
    {
        return self.find_encoded_word(encoded_word) != null;
    }

    fn find_word(self: *const Graph, word: []const u8) ?*const Node
    {
        if (word.len == 0) return null;
        const fc: CharCode = self.settings.encode(word[0]) catch return null;
        var node: *const Node = self.find_node(self.get_rootnode(), fc) orelse return null;
        node = self.get_bow(node) orelse return null;
        for(word[1..]) |cp|
        {
            const cc: CharCode = self.settings.encode(cp) catch return null;
            node = self.find_node(node, cc) orelse return null;
        }
        return if (node.data.is_eow) node else null;
    }

    fn find_encoded_word(self: *const Graph, word: []const CharCode) ?*const Node
    {
        if (word.len == 0) return null;
        const fc: CharCode = word[0];
        var node: *const Node = self.find_node(self.get_rootnode(), fc) orelse return null;
        node = self.get_bow(node) orelse return null;
        for(word[1..]) |cc|
        {
            node = self.find_node(node, cc) orelse return null;
        }
        return if (node.data.is_eow) node else null;
    }

    /// private
    /// TODO: allow one-letter words to be a whole word.
    fn add_word(self: *Graph, word: []const u8) !void
    {

        const buf = self.settings.encode_word(word) catch return;// catch { std.debug.print("WTF [{s}]\n", .{word}); return; };
        const word_len: usize = buf.len;
        if (word_len < 2) return;

        // var prefix = try std.BoundedArray(CharCode, 32).init(0);
        var prefix: std.BoundedArray(CharCode, 32) = .{};
        //std.debug.print("\nadd: [{s}]\n", .{word});

        self.word_count += 1; // TODO: we are not 100% sure, the word could be a duplicate
        for (0..word_len) |i|
        {
            prefix.len = 0;
            //try prefix.resize(0);
            prefix.appendSliceAssumeCapacity(buf.slice()[0..i + 1]);
            std.mem.reverse(CharCode, prefix.slice());

            //  for(prefix.slice()) |c|
            //  {
            //      std.debug.print("{u}/", .{self.settings.decode(c)});
            //  }
             //std.debug.print("\n", .{});

            var node: *Node = self.get_rootnode_ptr();
            for (0..prefix.len) |j|
            {
                node = try self.add_or_get_node(node, prefix.get(j), false);
                //if (j == 0 and word_len == 1) node.data.is_whole_word = true; //NOPE

                // At the end of the prefix.
                if (j == prefix.len - 1)
                {
                    if (prefix.len == word_len) node.data.is_whole_word = true;

                    var bow_node = self.get_bow_ptr(node);
                    if (bow_node == null)
                    {
                        node.data.is_bow = true;
                        bow_node = try self.add_node(node, 0, true); // add begin-of-word node (always index #0)
                        //assert(self.get_bow_ptr(node) == bow_node);
                        //std.debug.print("(+bow)+", .{});
                    }

                    // Switch to bow and add suffix.
                    var suffix = bow_node orelse return ScrabbleError.GaddagBuildError;
                    // I think this allows for 1-letter words.
                    //if (word_len == 1) suffix.data.is_eow = true;
                    for (j + 1..word_len) |k|
                    {
                        suffix = try self.add_or_get_node(suffix, buf.get(k), false);
                        //std.debug.print("{u}\\", .{self.settings.decode(suffix.data.code)});
                        if (k == word_len - 1)
                        {
                            suffix.data.is_eow = true; // mark end of word
                            //std.debug.print("(eow)\n", .{});
                        }
                    }
                }
            }
        }
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
    /// TODO: there seems to be a little BUG i did not manage to track yet....
    fn add_node(self: *Graph, parentnode: *Node, charcode: CharCode, comptime is_bow: bool) !*Node
    {
        const mask: u32 = get_mask(charcode);
        const new_node = Node.init(charcode);
        const old_index: u32 = parentnode.child_ptr;
        const old_count: u8 = parentnode.count;
        const new_count: u8 = old_count + 1;
        const freelist = self.get_freelist(new_count);
        // If we have freespace use that.
        if (freelist.items.len > 0)
        {
            const free_idx: u32 = freelist.pop(); // this is the free index with enough space
            const new_idx: u32 = if (is_bow) free_idx else free_idx + old_count;
            const copy_idx: u32 = if (is_bow)  free_idx + 1 else free_idx;

            parentnode.child_ptr = free_idx;
            parentnode.count = new_count;
            parentnode.mask |= mask;

            //if (free_idx == 1) std.debug.print("replace free at 1 {} {} {}\n", .{old_count, new_count, new_node});
            //if (copy_idx == old_index) std.debug.print("WTF", .{});

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
            const new_idx: u32 = if (is_bow) free_idx else free_idx + old_count;
            const copy_idx: u32 = if (is_bow) free_idx + 1 else free_idx;

            //if (free_idx == 1) std.debug.print("append free at 1 {} {} {}\n", .{old_count, new_count, new_node});
            //if (copy_idx == old_index) std.debug.print("WTF", .{});

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
    fn get_node_ptr_by_index(self: *Graph, idx: u32) *Node
    {
        assert(idx < self.nodes.items.len);
        return &self.nodes.items[idx];
    }

    /// private
    fn get_rootnode_ptr(self: *Graph) *Node
    {
        return self.get_node_ptr_by_index(0);
    }

    /// private
    fn get_bow_ptr(self: *Graph, parentnode: *Node) ?*Node
    {
        if (parentnode.count == 0 or !parentnode.data.is_bow) return null;
        return self.get_node_ptr_by_index(parentnode.child_ptr);
    }

    /// private. During build the children are not yet sorted: we have to search.
    fn find_node_ptr_unsorted(self: *Graph, parentnode: *Node, charcode: CharCode) ?*Node
    {
        if (parentnode.count == 0) return null;
        const popcount = @popCount(parentnode.mask);
        assert(popcount == parentnode.count);
        const children = self.nodes.items[parentnode.child_ptr..parentnode.child_ptr + parentnode.count];
        for(children) |*run| if (run.data.code == charcode) return run;
        return null;
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

};


/// 10 bytes with mask. TODO: we could squeeze 6 into 5 if we limit to 65 million nodes.
pub const Node = extern struct
{
    pub const STRUCTSIZE: usize = @sizeOf(Node);

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
    // TODO the count field can disappear and replaced by popcount. but it will have 3-5 clockcycles at each call for popcount i believe.

    inline fn init(charcode: CharCode) Node
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

    pub fn contains(self: *const Node, charcode: CharCode) bool
    {
        return self.mask & (@as(u32, 1) << charcode) != 0;
    }
};
