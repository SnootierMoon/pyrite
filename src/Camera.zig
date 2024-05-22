const std = @import("std");

const Camera = @This();
const ChunkCoord = @import("voxel/coord.zig").ChunkCoord;
const lm = @import("linmath.zig");

pos: lm.Vec3F,
yaw: f32,
pitch: f32,

pub fn init(pos: lm.Vec3F, yaw: f32, pitch: f32) Camera {
    return .{ .pos = pos, .yaw = yaw, .pitch = pitch };
}

pub fn model(cam: Camera, chunk_coord: ChunkCoord) lm.Mat4F {
    _ = cam;
    const root: lm.Vec3F = @floatFromInt(chunk_coord.root().vec);
    return lm.transform.translation(root);
}

pub fn viewProj(cam: Camera, z_near: f32, fov_y: f32, aspect_ratio: f32) lm.Mat4F {
    const proj = lm.transform.perspective(z_near, fov_y, aspect_ratio);
    const view = lm.transform.look(cam.pos, cam.yaw, cam.pitch);
    return lm.mat4f.mul(proj, view);
}

pub fn adjustOrientation(cam: *Camera, del_yaw: f32, del_pitch: f32) void {
    cam.yaw = @rem(cam.yaw + del_yaw, std.math.tau);
    cam.pitch = std.math.clamp(cam.pitch + del_pitch, -std.math.pi / 2.0, std.math.pi / 2.0);
}

/// Moves the Camera relative to its orientation.
/// v_rel.x is the amount to move forwards,
/// v_rel.y is the amount to move leftwards, and
/// v_rel.z is the amount to move upwards
pub fn move(cam: *Camera, v_rel: lm.Vec3F) void {
    cam.pos += lm.mat3f.mulv(lm.mat3f.rot(0, 1, cam.yaw), v_rel);
}

pub fn forward(cam: Camera) lm.Vec3F {
    const cy = @cos(cam.yaw);
    const sy = @sin(cam.yaw);
    const cp = @cos(cam.pitch);
    const sp = @sin(cam.pitch);
    return .{ cy * cp, sy * cp, sp };
}
