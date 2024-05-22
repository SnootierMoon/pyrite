const std = @import("std");

const Chunk = @import("Chunk.zig");
const ChunkCoord = @import("coord.zig").ChunkCoord;
const Object = @This();
const RayMarcher = @import("RayMarcher.zig");
const VoxelCoord = @import("coord.zig").VoxelCoord;
const lm = @import("../linmath.zig");
const Sphere = @import("Sphere.zig");

chunks: std.AutoHashMapUnmanaged(ChunkCoord, *Chunk),

pub fn init() Object {
    return .{
        .chunks = .{},
    };
}

pub fn deinit(object: *Object, allocator: std.mem.Allocator) void {
    var chunks = object.chunks.valueIterator();
    while (chunks.next()) |chunk| {
        allocator.destroy(chunk.*);
    }
    object.chunks.deinit(allocator);
}

pub fn get(object: Object, coord: VoxelCoord) u32 {
    if (object.chunks.get(coord.chunkCoord())) |chunk| {
        return chunk.get(coord.chunkIndex());
    } else {
        return 0;
    }
}

pub fn getPtr(object: *Object, allocator: std.mem.Allocator, coord: VoxelCoord) !*u32 {
    if (object.chunks.get(coord.chunkCoord())) |chunk| {
        return chunk.getPtr(coord.chunkIndex());
    } else {
        var chunk = try allocator.create(Chunk);
        chunk.clear();
        try object.chunks.put(allocator, coord.chunkCoord(), chunk);
        return chunk.getPtr(coord.chunkIndex());
    }
}

pub fn rayMarchNonAir(object: Object, source: lm.Vec3D, dir: lm.Vec3D, range: f64) ?VoxelCoord {
    var rm = RayMarcher.init(source, dir);
    if (object.get(rm.curr) != 0) {
        return rm.curr;
    }
    while (rm.next() < range) {
        if (object.get(rm.curr) != 0) {
            return rm.curr;
        }
    }
    return null;
}

pub fn rayMarchAir(object: Object, source: lm.Vec3D, dir: lm.Vec3D, range: f64) ?VoxelCoord {
    var rm = RayMarcher.init(source, dir);
    if (object.get(rm.curr) != 0) {
        return null;
    }
    var prev = rm.curr;
    while (rm.next() < range) {
        if (object.get(rm.curr) != 0) {
            return prev;
        }
        prev = rm.curr;
    }
    return null;
}
