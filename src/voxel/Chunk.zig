const std = @import("std");

const Chunk = @This();
const ChunkIndex = @import("coord.zig").ChunkIndex;
const Voxel = @import("../voxel.zig").Voxel;

voxels: [volume]Voxel,

pub const side_length = 32;
pub const face_area = 32 * 32;
pub const volume = 32 * 32 * 32;

pub fn clear(chunk: *Chunk) void {
    chunk.voxels = .{.air} ** volume;
}

pub fn get(chunk: Chunk, index: ChunkIndex) Voxel {
    return chunk.voxels[@intCast(@as(u15, @bitCast(index)))];
}

pub fn getPtr(chunk: *Chunk, index: ChunkIndex) *Voxel {
    return &chunk.voxels[@intCast(@as(u15, @bitCast(index)))];
}
