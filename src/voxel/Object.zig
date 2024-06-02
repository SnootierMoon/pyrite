const std = @import("std");

const Chunk = @import("Chunk.zig");
const ChunkCoord = @import("coord.zig").ChunkCoord;
const ChunkIndex = @import("coord.zig").ChunkIndex;
const Dir = @import("coord.zig").Dir;
const Object = @This();
const RayMarcher = @import("RayMarcher.zig");
const Sphere = @import("Sphere.zig");
const Voxel = @import("../voxel.zig").Voxel;
const VoxelCoord = @import("coord.zig").VoxelCoord;
const lm = @import("../linmath.zig");

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

pub fn get(object: Object, coord: VoxelCoord) Voxel {
    if (object.chunks.get(coord.chunkCoord())) |chunk| {
        return chunk.get(coord.chunkIndex());
    } else {
        return .air;
    }
}

pub fn getPtr(object: *Object, allocator: std.mem.Allocator, coord: VoxelCoord) !*Voxel {
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
    if (object.get(rm.curr) != .air) {
        return rm.curr;
    }
    while (rm.next() < range) {
        if (object.get(rm.curr) != .air) {
            return rm.curr;
        }
    }
    return null;
}

pub fn rayMarchAir(object: Object, source: lm.Vec3D, dir: lm.Vec3D, range: f64) ?VoxelCoord {
    var rm = RayMarcher.init(source, dir);
    if (object.get(rm.curr) != .air) {
        return null;
    }
    var prev = rm.curr;
    while (rm.next() < range) {
        if (object.get(rm.curr) != .air) {
            return prev;
        }
        prev = rm.curr;
    }
    return null;
}

pub fn generateMesh(object: Object, chunk_coord: ChunkCoord, mesh: *std.ArrayList(u32)) !bool {
    if (object.chunks.get(chunk_coord)) |chunk| {
        inline for (comptime std.enums.values(Dir)) |dir| {
            const nb_chunk = object.chunks.get(chunk_coord.adj(dir));
            var it = ChunkIndex.Iterator{};
            while (it.next()) |index| {
                if (chunk.get(index) != .air) {
                    const nb, const ov = index.adjWithOverflow(dir);
                    const air_nb = if (ov == 0)
                        chunk.get(nb) == .air
                    else if (nb_chunk) |nb_ch|
                        nb_ch.get(nb) == .air
                    else
                        true;

                    if (air_nb) {
                        try mesh.append(@as(u15, @bitCast(index)) | (@as(u32, @intFromEnum(dir)) << 15));
                    }
                }
            }
        }
        return true;
    } else {
        return false;
    }
}
