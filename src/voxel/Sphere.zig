const lm = @import("../linmath.zig");
const VoxelCoord = @import("coord.zig").VoxelCoord;
const Sphere = @This();
const AABB = @import("AABB.zig");

radius: f64,
center: lm.Vec3D,

// want to find all points p where dist(p, center) <= radius

pub fn iterator(sphere: Sphere) Iterator {
    return .{
        .sphere = sphere,
        .aabb_it = (AABB{
            .min = sphere.center - lm.vec3d.splat(sphere.radius),
            .max = sphere.center + lm.vec3d.splat(sphere.radius),
        }).iterator(),
    };
}

pub const Iterator = struct {
    sphere: Sphere,
    aabb_it: AABB.Iterator,

    pub fn next(it: *Iterator) ?VoxelCoord {
        while (it.aabb_it.next()) |coord| {
            if (it.sphere.contains(coord)) {
                return coord;
            }
        }
        return null;
    }
};

pub fn contains(sphere: Sphere, coord: VoxelCoord) bool {
    return lm.vec3d.distSq(coord.center(), sphere.center) <= sphere.radius * sphere.radius;
}
