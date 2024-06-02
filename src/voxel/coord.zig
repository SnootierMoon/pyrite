const std = @import("std");

const lm = @import("../linmath.zig");

pub const Axis = enum(u2) {
    x = 0,
    y = 1,
    z = 2,
};

pub const Dir = enum(u3) {
    pos_x = 0,
    pos_y = 1,
    pos_z = 2,
    neg_x = 4,
    neg_y = 5,
    neg_z = 6,

    pub fn init(axis_: Axis, sign_: u1) Dir {
        return switch (axis_) {
            .x => if (sign_ == 0) .pos_x else .neg_x,
            .y => if (sign_ == 0) .pos_y else .neg_y,
            .z => if (sign_ == 0) .pos_z else .neg_z,
        };
    }

    pub fn fromVec(v: lm.Vec3D) ?Dir {
        const abs = @abs(v);
        const m = @reduce(.Max, abs);
        if (m == 0) {
            return null;
        } else if (abs[0] == m) {
            return if (v[0] > 0) .pos_x else .neg_x;
        } else if (abs[1] == m) {
            return if (v[1] > 0) .pos_y else .neg_y;
        } else {
            return if (v[2] > 0) .neg_x else .neg_z;
        }
    }

    pub fn axis(dir: Dir) Axis {
        return switch (dir) {
            .pos_x, .neg_x => .x,
            .pos_y, .neg_y => .y,
            .pos_z, .neg_z => .z,
        };
    }

    pub fn sign(dir: Dir) u1 {
        return switch (dir) {
            .pos_x, .pos_y, .pos_z => 0,
            .neg_x, .neg_y, .neg_z => 1,
        };
    }
};

pub const ChunkIndex = packed struct {
    x: u5,
    y: u5,
    z: u5,

    pub const Iterator = struct {
        nxt: ?ChunkIndex = .{ .x = 0, .y = 0, .z = 0 },

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

    pub fn adj(index: ChunkIndex, dir: Dir) ?ChunkIndex {
        const neighbor, const ov = index.adjWithOverflow(dir);
        return if (ov == 0) neighbor else null;
    }

    pub fn adjWithOverflow(index: ChunkIndex, dir: Dir) struct { ChunkIndex, u1 } {
        switch (dir) {
            inline else => |d| {
                var neighbor = index;
                @field(neighbor, @tagName(d.axis())), const ov = if (d.sign() == 0)
                    @addWithOverflow(@field(index, @tagName(d.axis())), 1)
                else
                    @subWithOverflow(@field(index, @tagName(d.axis())), 1);
                return .{ neighbor, ov };
            },
        }
    }
};

pub const ChunkCoord = struct {
    vec: lm.Vec(3, i27),

    pub fn root(coord: ChunkCoord) VoxelCoord {
        return VoxelCoord{ .vec = @as(lm.Vec3I, @intCast(coord.vec)) << @splat(5) };
    }

    pub fn adj(coord: ChunkCoord, dir: Dir) ChunkCoord {
        switch (dir) {
            inline else => |d| {
                var neighbor = coord;
                neighbor.vec[@intFromEnum(d.axis())] = if (d.sign() == 0)
                    coord.vec[@intFromEnum(d.axis())] + 1
                else
                    coord.vec[@intFromEnum(d.axis())] - 1;
                return neighbor;
            },
        }
    }
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

    pub fn adj(coord: VoxelCoord, dir: Dir) VoxelCoord {
        switch (dir) {
            inline else => |d| {
                var neighbor = coord;
                neighbor.vec[@intFromEnum(d.axis())] = if (d.sign() == 0)
                    coord.vec[@intFromEnum(d.axis())] + 1
                else
                    coord.vec[@intFromEnum(d.axis())] - 1;
                return neighbor;
            },
        }
    }
};
