//! Linear Algebra Tools
//!
//! Matrices use the Row-Major convention for storage.
//! Furthermore, the (i, j)-index of a matrix corresponds to row i, column j.
//! For example, the xz element of a matrix is the third field of the first row.
//!
//! There are two coordinate systems:
//!  - World-Space Coordinates (3D).
//!    Vectors belong to the space of positions in the world.
//!      +x: north,  +y: east,  +z: up
//!      -x: south,  -y: west,  -z: down
//!  - OpenGL-Compatible Coordinates (3/4D).
//!    https://learnopengl.com/img/getting-started/coordinate_systems_right_handed.png
//!    Vectors belong to the space of relative positions to the camera.
//!      +x: right,  +y: up,    +z: backwards   +/-w: depth
//!      -x: left,   -y: down,  -z: forwards

const std = @import("std");

pub const Vec3U = Vec(3, u32);
pub const Vec3I = Vec(3, i32);
pub const Vec3F = Vec(3, f32);
pub const Vec3D = Vec(3, f64);

pub const vec3u = vec(3, u32);
pub const vec3i = vec(3, i32);
pub const vec3f = vec(3, f32);
pub const vec3d = vec(3, f64);

pub const Vec4U = Vec(4, u32);
pub const Vec4I = Vec(4, i32);
pub const Vec4F = Vec(4, f32);
pub const Vec4D = Vec(4, f64);

pub const vec4u = vec(4, u32);
pub const vec4i = vec(4, i32);
pub const vec4f = vec(4, f32);
pub const vec4d = vec(4, f64);

pub const Mat3U = Mat(3, u32);
pub const Mat3I = Mat(3, i32);
pub const Mat3F = Mat(3, f32);
pub const Mat3D = Mat(3, f64);

pub const mat3u = mat(3, u32);
pub const mat3i = mat(3, i32);
pub const mat3f = mat(3, f32);
pub const mat3d = mat(3, f64);

pub const Mat4U = Mat(4, u32);
pub const Mat4I = Mat(4, i32);
pub const Mat4F = Mat(4, f32);
pub const Mat4D = Mat(4, f64);

pub const mat4u = mat(4, u32);
pub const mat4i = mat(4, i32);
pub const mat4f = mat(4, f32);
pub const mat4d = mat(4, f64);

pub fn Vec(comptime N: comptime_int, comptime T: type) type {
    return @Vector(N, T);
}

pub fn Mat(comptime N: comptime_int, comptime T: type) type {
    return [N]@Vector(N, T);
}

pub fn vec(comptime N: comptime_int, comptime T: type) type {
    return struct {
        pub const zero: Vec(N, T) = @as([N]T, .{0} ** N);

        pub fn splat(x: T) Vec(N, T) {
            return @splat(x);
        }

        pub fn dot(lhs: Vec(N, T), rhs: Vec(N, T)) T {
            return @reduce(.Add, lhs * rhs);
        }

        pub fn magSq(v: Vec(N, T)) T {
            return dot(v, v);
        }

        pub fn mag(v: Vec(N, T)) T {
            return @sqrt(magSq(v));
        }

        pub fn distSq(v1: Vec(N, T), v2: Vec(N, T)) T {
            return magSq(v2 - v1);
        }

        pub fn dist(v1: Vec(N, T), v2: Vec(N, T)) T {
            return mag(v2 - v1);
        }

        pub fn normalize(v: Vec(N, T), tol_sq: T) ?Vec(N, T) {
            const mag_sq = magSq(v);
            if (mag_sq < tol_sq) {
                return null;
            } else {
                return v / splat(@sqrt(mag_sq));
            }
        }

        pub fn scaleTo(v: Vec(N, T), new_mag: T, tol_sq: T) ?Vec(N, T) {
            const mag_sq = magSq(v);
            if (mag_sq < tol_sq) {
                return null;
            } else {
                return v * splat(new_mag / @sqrt(mag_sq));
            }
        }

        pub usingnamespace switch (N) {
            3 => struct {
                pub fn cross(lhs: Vec(3, T), rhs: Vec(3, T)) Vec(3, T) {
                    var r1 = @shuffle(T, lhs, undefined, .{ 1, 2, 0 });
                    r1 *= @shuffle(T, rhs, undefined, .{ 2, 0, 1 });
                    var r2 = @shuffle(T, rhs, undefined, .{ 1, 2, 0 });
                    r2 *= @shuffle(T, lhs, undefined, .{ 2, 0, 1 });
                    return r1 - r2;
                }
            },
            4 => struct {},
            else => unreachable,
        };

        pub usingnamespace switch (@typeInfo(T)) {
            .int => struct {},
            .float => struct {},
            else => unreachable,
        };
    };
}

pub fn mat(comptime N: comptime_int, comptime T: type) type {
    return struct {
        pub const zero: Mat(N, T) = .{vec(N, T).zero} ** N;
        pub const id: Mat(N, T) = blk: {
            var m: Mat(N, T) = zero;
            for (0..N) |i| {
                m[i][i] = 1;
            }
            break :blk m;
        };

        pub fn row(m: Mat(N, T), i: usize) Vec(N, T) {
            return m[i];
        }

        pub fn col(m: Mat(N, T), i: usize) Vec(N, T) {
            var v: Vec(N, T) = undefined;
            inline for (0..N) |j| {
                v[j] = m[j][i];
            }
            return v;
        }

        pub fn rowMajorArray(m: Mat(N, T)) [N * N]T {
            var a: [N * N]T = undefined;
            inline for (0..N) |i| {
                a[N * i .. N * (i + 1)].* = m[i];
            }
            return a;
        }

        pub fn mul(lhs: Mat(N, T), rhs: Mat(N, T)) Mat(N, T) {
            var m: Mat(N, T) = undefined;
            inline for (0..N) |j| {
                const rc = col(rhs, j);
                inline for (0..N) |i| {
                    const lr = row(lhs, i);
                    m[i][j] = vec(N, T).dot(lr, rc);
                }
            }
            return m;
        }

        pub fn mulv(lhs: Mat(N, T), rhs: Vec(N, T)) Vec(N, T) {
            var v: Vec(N, T) = undefined;
            inline for (0..N) |i| {
                const lr = row(lhs, i);
                v[i] = vec(N, T).dot(lr, rhs);
            }
            return v;
        }

        pub fn rot(from: usize, to: usize, angle: T) Mat(N, T) {
            std.debug.assert(from != to);
            var m = id;
            const c = @cos(angle);
            const s = @sin(angle);
            m[from][from] = c;
            m[from][to] = -s;
            m[to][from] = s;
            m[to][to] = c;
            return m;
        }

        pub usingnamespace switch (N) {
            3 => struct {},
            4 => struct {},
            else => unreachable,
        };

        pub usingnamespace switch (@typeInfo(T)) {
            .int => struct {},
            .float => struct {},
            else => unreachable,
        };
    };
}

pub const transform = struct {
    pub fn perspective(z_near: f32, fov_y: f32, aspect_ratio: f32) Mat4F {
        var m = mat4f.zero;
        const scale_y = 1.0 / @tan(fov_y * 0.5);
        const scale_x = scale_y / aspect_ratio;
        m[0][0] = scale_x;
        m[1][1] = scale_y;
        m[2][2] = -1.0;
        m[2][3] = -2.0 * z_near;
        m[3][2] = -1.0;
        return m;
    }

    pub fn ortho(width: f32, height: f32) Mat4F {
        return Mat4F{
            .{ 2.0 / width, 0.0, 0.0, -1.0 },
            .{ 0.0, -2.0 / height, 0.0, 1.0 },
            .{ 0.0, 0.0, -1.0, 0.0 },
            .{ 0.0, 0.0, 0.0, 1.0 },
        };
    }

    pub fn look(pos: Vec3F, yaw: f32, pitch: f32) Mat4F {
        const cy = @cos(yaw);
        const sy = @sin(yaw);
        const cp = @cos(pitch);
        const sp = @sin(pitch);
        const c_x: Vec3F = .{ sy, -cy, 0 }; // right
        const c_y: Vec3F = .{ -cy * sp, -sy * sp, cp }; // up
        const c_z: Vec3F = .{ -cy * cp, -sy * cp, -sp }; // backwards
        return .{
            @as([3]f32, c_x) ++ .{-vec3f.dot(c_x, pos)},
            @as([3]f32, c_y) ++ .{-vec3f.dot(c_y, pos)},
            @as([3]f32, c_z) ++ .{-vec3f.dot(c_z, pos)},
            .{ 0, 0, 0, 1 },
        };
    }

    pub fn translation(v: Vec3F) Mat4F {
        var m = mat4f.id;
        m[0][3] = v[0];
        m[1][3] = v[1];
        m[2][3] = v[2];
        return m;
    }
};
