const std = @import("std");

const lm = @import("../linmath.zig");

pub const ChunkCoord = struct {
    vec: lm.Vec(3, i27),

    pub fn root(coord: ChunkCoord) VoxelCoord {
        return VoxelCoord{ .vec = @as(lm.Vec3I, @intCast(coord.vec)) << @splat(5) };
    }
};

pub const ChunkIndex = packed struct {
    x: u5,
    y: u5,
    z: u5,

    pub const Iterator = struct {
        nxt: ?ChunkIndex = @bitCast(0),

        pub fn next(it: *Iterator) ?ChunkIndex {
            const curr = it.nxt;
            if (it.nxt) |n| {
                var i: u15 = @bitCast(n);
                i, const ov = @addWithOverflow(i, 1);
                it.nxt = if (ov == 0) @bitCast(i) else null;
            }
            return curr;
        }
    };
};

pub const VoxelCoord = struct {
    vec: lm.Vec3I,

    pub fn fromPos(pos: lm.Vec3D) VoxelCoord {
        return VoxelCoord{ .vec = @intFromFloat(@floor(pos)) };
    }

    pub fn center(coord: VoxelCoord) lm.Vec3D {
        return @as(lm.Vec3D, @floatFromInt(coord.vec)) + lm.vec3d.splat(0.5);
    }

    pub fn fromChunkCoordIndex(coord: ChunkCoord, index: ChunkIndex) VoxelCoord {
        return VoxelCoord{ .vec = lm.Vec3I{ index.x, index.y, index.z } | coord.root().vec };
    }

    pub fn chunkCoord(coord: VoxelCoord) ChunkCoord {
        return ChunkCoord{ .vec = @intCast(coord.vec >> @splat(5)) };
    }

    pub fn chunkIndex(coord: VoxelCoord) ChunkIndex {
        const i: lm.Vec(3, u5) = @intCast(coord.vec & lm.vec3i.splat(31));
        return .{ .x = i[0], .y = i[1], .z = i[2] };
    }
};
