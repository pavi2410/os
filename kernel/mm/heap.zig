const paging = @import("../arch/x86_64/paging.zig");
const std = @import("std");
const virtual = @import("virtual.zig");

pub const min_align = 16;

pub const HeapError = error{
    OutOfMemory,
    InvalidFree,
    DoubleFree,
};

const magic_free: u32 = 0xF4EE0001;
const magic_used: u32 = 0xA110CAFE;

const BlockHeader = struct {
    size: usize,
    magic: u32,
    next: ?*BlockHeader,

    fn fromPayload(ptr: [*]u8) *BlockHeader {
        return @ptrCast(@alignCast(@as([*]u8, @ptrCast(ptr)) - @sizeOf(BlockHeader)));
    }

    fn payload(self: *BlockHeader) [*]u8 {
        return @ptrCast(@alignCast(@as([*]u8, @ptrCast(self)) + @sizeOf(BlockHeader)));
    }
};

var free_head: ?*BlockHeader = null;
var live_allocations: usize = 0;
var live_bytes: usize = 0;
var total_allocs: usize = 0;
var total_frees: usize = 0;

pub fn init() HeapError!void {
    free_head = null;
    live_allocations = 0;
    live_bytes = 0;
    total_allocs = 0;
    total_frees = 0;

    const page = virtual.allocPages(1) catch return HeapError.OutOfMemory;
    const block: *BlockHeader = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(page))));
    block.* = .{
        .size = paging.page_size,
        .magic = magic_free,
        .next = null,
    };
    insertFreeBlock(block);
}

pub fn kmalloc(size: usize) HeapError![*]u8 {
    if (size == 0) return @ptrCast(@alignCast(@as([*]u8, @ptrFromInt(min_align))));

    const needed = std.mem.alignForward(usize, size + @sizeOf(BlockHeader), min_align);

    var prev: ?*BlockHeader = null;
    var current = free_head;
    while (current) |block| {
        if (block.magic != magic_free) return HeapError.InvalidFree;
        if (block.size >= needed) {
            const remainder = block.size - needed;
            if (remainder >= @sizeOf(BlockHeader) + min_align) {
                const split: *BlockHeader = @ptrCast(@alignCast(@as([*]u8, @ptrCast(block)) + needed));
                split.* = .{
                    .size = remainder,
                    .magic = magic_free,
                    .next = block.next,
                };
                block.size = needed;
                block.next = null;
                if (prev) |p| {
                    p.next = split;
                } else {
                    free_head = split;
                }
            } else {
                unlinkBlock(block, prev);
            }

            block.magic = magic_used;
            block.next = null;
            live_allocations += 1;
            live_bytes += block.size;
            total_allocs += 1;
            return block.payload();
        }
        prev = block;
        current = block.next;
    }

    try growHeap(needed);
    return kmalloc(size);
}

pub fn kfree(ptr: [*]u8) HeapError!void {
    if (@intFromPtr(ptr) <= min_align) return;

    const block = BlockHeader.fromPayload(ptr);
    if (block.magic != magic_used) {
        if (block.magic == magic_free) return HeapError.DoubleFree;
        return HeapError.InvalidFree;
    }

    block.magic = magic_free;
    block.next = null;
    live_allocations -= 1;
    live_bytes -= block.size;
    total_frees += 1;
    insertFreeBlock(block);
    coalesceFreeList();
}

pub fn liveAllocations() usize {
    return live_allocations;
}

pub fn liveBytes() usize {
    return live_bytes;
}

pub fn totalAllocs() usize {
    return total_allocs;
}

pub fn totalFrees() usize {
    return total_frees;
}

fn growHeap(min_bytes: usize) HeapError!void {
    const pages = (min_bytes + paging.page_size - 1) / paging.page_size;
    const virt = virtual.allocPages(pages) catch return HeapError.OutOfMemory;
    const block: *BlockHeader = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(virt))));
    block.* = .{
        .size = pages * paging.page_size,
        .magic = magic_free,
        .next = null,
    };
    insertFreeBlock(block);
}

fn insertFreeBlock(block: *BlockHeader) void {
    if (free_head == null or @intFromPtr(block) < @intFromPtr(free_head.?)) {
        block.next = free_head;
        free_head = block;
        return;
    }

    var prev = free_head;
    while (prev) |current| : (prev = current.next) {
        if (current.next == null or @intFromPtr(block) < @intFromPtr(current.next.?)) {
            block.next = current.next;
            current.next = block;
            return;
        }
    }
}

fn unlinkBlock(block: *BlockHeader, prev: ?*BlockHeader) void {
    if (prev) |p| {
        p.next = block.next;
    } else {
        free_head = block.next;
    }
}

fn coalesceFreeList() void {
    var current = free_head;
    while (current) |block| {
        const block_end = @intFromPtr(block) + block.size;
        if (block.next) |next| {
            if (block_end == @intFromPtr(next)) {
                block.size += next.size;
                block.next = next.next;
                continue;
            }
        }
        current = block.next;
    }
}
