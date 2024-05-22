const std = @import("std");

const Chunk = @This();
const ChunkIndex = @import("coord.zig").ChunkIndex;

voxels: [volume]u32,

pub const side_length = 32;
pub const face_area = 32 * 32;
pub const volume = 32 * 32 * 32;

pub fn clear(chunk: *Chunk) void {
    chunk.voxels = .{0} ** volume;
}

pub fn get(chunk: Chunk, index: ChunkIndex) u32 {
    return chunk.voxels[@intCast(@as(u15, @bitCast(index)))];
}

pub fn getPtr(chunk: *Chunk, index: ChunkIndex) *u32 {
    return &chunk.voxels[@intCast(@as(u15, @bitCast(index)))];
}

pub fn generateMesh(chunk: *Chunk, mesh: *std.ArrayList(u32)) !void {
    for (0..32) |i| {
        for (0..32) |j| {
            for (0..32) |k| {
                if (chunk.get(ChunkIndex{ .x = @intCast(i), .y = @intCast(j), .z = @intCast(k) }) == 1) {
                    if (i == 31 or chunk.get(ChunkIndex{ .x = @intCast(i + 1), .y = @intCast(j), .z = @intCast(k) }) == 0) {
                        try mesh.append(@intCast(i | (j << 5) | (k << 10) | (0 << 15)));
                    }
                    if (j == 31 or chunk.get(ChunkIndex{ .x = @intCast(i), .y = @intCast(j + 1), .z = @intCast(k) }) == 0) {
                        try mesh.append(@intCast(i | (j << 5) | (k << 10) | (1 << 15)));
                    }
                    if (k == 31 or chunk.get(ChunkIndex{ .x = @intCast(i), .y = @intCast(j), .z = @intCast(k + 1) }) == 0) {
                        try mesh.append(@intCast(i | (j << 5) | (k << 10) | (2 << 15)));
                    }
                    if (i == 0 or chunk.get(ChunkIndex{ .x = @intCast(i - 1), .y = @intCast(j), .z = @intCast(k) }) == 0) {
                        try mesh.append(@intCast(i | (j << 5) | (k << 10) | (4 << 15)));
                    }
                    if (j == 0 or chunk.get(ChunkIndex{ .x = @intCast(i), .y = @intCast(j - 1), .z = @intCast(k) }) == 0) {
                        try mesh.append(@intCast(i | (j << 5) | (k << 10) | (5 << 15)));
                    }
                    if (k == 0 or chunk.get(ChunkIndex{ .x = @intCast(i), .y = @intCast(j), .z = @intCast(k - 1) }) == 0) {
                        try mesh.append(@intCast(i | (j << 5) | (k << 10) | (6 << 15)));
                    }
                }
            }
        }
    }
}
