const AABB = @This();
const lm = @import("../linmath.zig");
const VoxelCoord = @import("coord.zig").VoxelCoord;

min: lm.Vec3D,
max: lm.Vec3D,

pub fn iterator(aabb: AABB) Iterator {
    const min_bd: lm.Vec3I = @intFromFloat(@ceil(aabb.min - lm.vec3d.splat(0.5)));
    const max_bd: lm.Vec3I = @intFromFloat(@floor(aabb.max - lm.vec3d.splat(0.5)));
    return .{
        .curr = min_bd,
        .min_bd = min_bd,
        .max_bd = max_bd,
    };
}

pub const Iterator = struct {
    curr: lm.Vec3I,
    min_bd: lm.Vec3I,
    max_bd: lm.Vec3I,

    pub fn next(it: *Iterator) ?VoxelCoord {
        if (it.curr[2] < it.max_bd[2]) {
            it.curr[2] += 1;
            return VoxelCoord{ .vec = it.curr };
        }
        it.curr[2] = it.min_bd[2];
        if (it.curr[1] < it.max_bd[1]) {
            it.curr[1] += 1;
            return VoxelCoord{ .vec = it.curr };
        }
        it.curr[1] = it.min_bd[1];
        if (it.curr[0] < it.max_bd[0]) {
            it.curr[0] += 1;
            return VoxelCoord{ .vec = it.curr };
        } else {
            return null;
        }
    }
};
