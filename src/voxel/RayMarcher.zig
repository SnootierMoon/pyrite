const std = @import("std");

const RayMarcher = @This();
const VoxelCoord = @import("coord.zig").VoxelCoord;
const lm = @import("../linmath.zig");

source: lm.Vec3D,
dir: lm.Vec3D,

curr: VoxelCoord,

pub fn init(source: lm.Vec3D, dir: lm.Vec3D) RayMarcher {
    const curr = VoxelCoord.fromPos(source);
    return .{
        .source = source,
        .dir = dir,
        .curr = curr,
    };
}

pub fn next(rm: *RayMarcher) f64 {
    // position of face
    const f = @as(lm.Vec3D, @floatFromInt(rm.curr.vec)) + @select(f64, rm.dir > lm.vec3d.zero, lm.vec3d.splat(1), lm.vec3d.zero);
    const tv = @select(f64, rm.dir != lm.vec3d.zero, (f - rm.source) / rm.dir, lm.vec3d.splat(std.math.inf(f64)));

    var t = std.math.inf(f64);
    var n = rm.curr;
    inline for (0..3) |i| {
        if (tv[i] < t) {
            t = tv[i];
            if (rm.dir[i] > 0) {
                n = rm.curr;
                n.vec[i] += 1;
            } else {
                n = rm.curr;
                n.vec[i] -= 1;
            }
        }
    }
    rm.curr = n;

    return t;
}
