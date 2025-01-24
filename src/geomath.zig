//! Geometry functions.
//!
//! The model coordinate system for models has:
//!  * +X is east   -X is west
//!  * +Y is north  -Y is south
//!  * +Z is up     -Z is down
//! This system is also known as "right-handed Z-up".
//! ```
//!            +Z
//!             ^  +Y
//!          __ | _/_____, horizontal
//!         /   | /     /  plane
//!        /    |/     /
//! -X <--------o--------> +X
//!      /     /     /
//!     /_____/_____/
//!          /  |
//!        -Y   v
//!            -Z
//! ```
//!
//! An azimuthal angle is defined as the angle on the horizontal plane from +X
//! which is counterclockwise when looking down from +Z, so that an angle of t
//! corresponds to the vector (x, y, z) = (cos(t), sin(t), 0).
//! An angle of inclination is defined in the domain [-pi/2, pi/2], with -pi/2
//! being straight down, 0 being level, and pi/2 being straight up.
//!
//! The camera coordinate system has +X going right, +Y going up, and +Z going
//! backwards (out of the screen). This is the right-handed coordinate system
//! where X is horizontal, Y is vertical, and Z is in/out.
//! ```
//!            +Y
//!             ^  -Z
//!             |  /
//!        ,----+----, screen
//!        |    |    |
//! -X <---+----o----+---> +X
//!        |   /|    |
//!        '--/-+----'
//!          /  |
//!        +Z   v
//!            -Y
//! ```

pub const std = @import("std");

pub const Vec2 = Vector(2, f32);
pub const Vec3 = Vector(3, f32);
pub const Vec4 = Vector(4, f32);

pub const Mat3 = Matrix(3, 3, f32);
pub const Mat4 = Matrix(4, 4, f32);

const TypeInfo = union(enum) {
    vec: Vec,
    mat: Mat,

    const Vec = struct { dimn: usize, T: type };
    const Mat = struct { rows: usize, cols: usize, T: type };

    fn get(t: type) ?TypeInfo {
        return if (@typeInfo(t) == .@"struct" and
            @hasDecl(t, "type_info") and
            @TypeOf(t.type_info) == TypeInfo)
            t.type_info
        else
            null;
    }
};

pub const Axis2 = enum(u2) { x = 0, y = 1 };
pub const Axis3 = enum(u2) { x = 0, y = 1, z = 2 };
pub const Axis4 = enum(u2) { x = 0, y = 1, z = 2, w = 3 };

pub const AxisDir2 = enum(u3) { pos_x = 0, pos_y = 1 };
pub const AxisDir3 = enum(u3) { pos_x = 0, pos_y = 1, pos_z = 2 };
pub const AxisDir4 = enum(u3) { pos_x = 0, pos_y = 1, pos_z = 2, pos_w = 3 };

pub fn Axis(dimn: usize) type {
    return switch (dimn) {
        2 => Axis2,
        3 => Axis3,
        4 => Axis4,
        else => @compileError("Axis only supports 2 <= dimn <= 4"),
    };
}

pub fn AxisDir(dimn: usize) type {
    return switch (dimn) {
        2 => AxisDir2,
        3 => AxisDir3,
        4 => AxisDir4,
        else => @compileError("AxisDir only supports 2 <= dimn <= 4"),
    };
}

pub fn Vector(dimn: usize, T: type) type {
    return struct {
        base: @Vector(dimn, T),

        const type_info: TypeInfo = .{ .vec = .{ .dimn = dimn, .T = T } };

        pub fn init2(x: T, y: T) Vector(2, T) {
            return .{ .base = .{ x, y } };
        }

        pub fn init3(x: T, y: T, z: T) Vector(3, T) {
            return .{ .base = .{ x, y, z } };
        }

        pub fn init4(x: T, y: T, z: T, w: T) Vector(4, T) {
            return .{ .base = .{ x, y, z, w } };
        }

        pub fn initArray(a: [dimn]T) Vector(dimn, T) {
            return .{ .base = a };
        }

        pub const init = switch (dimn) {
            2 => init2,
            3 => init3,
            4 => init4,
            else => @compileError("Vector.init only supports 2 <= dimn <= 4"),
        };

        pub fn splat(scalar: T) Vector(dimn, T) {
            return .{ .base = @splat(scalar) };
        }

        pub const zero: Vector(dimn, T) = splat(0);

        pub fn axisUnitIdx(axis: usize) Vector(dimn, T) {
            var vec = zero;
            vec[axis] = 1;
            return vec;
        }

        pub fn axisUnit(axis: Axis(dimn)) Vector(dimn, T) {
            return axisUnitIdx(@intFromEnum(axis));
        }

        pub fn getIdx(vec: Vector(dimn, T), axis: usize) T {
            return vec.base[axis];
        }

        pub fn get(vec: Vector(dimn, T), axis: Axis(dimn)) T {
            return vec.getIdx(@intFromEnum(axis));
        }

        pub fn getPtrIdx(vec: *Vector(dimn, T), axis: usize) *T {
            return &vec.base[axis];
        }

        pub fn getPtr(vec: *Vector(dimn, T), axis: Axis(dimn)) *T {
            return vec.getPtrIdx(@intFromEnum(axis));
        }

        pub fn swizzle(vec: Vector(dimn, T), comptime s: []const u8) Vector(s.len, T) {
            return .{ .base = @shuffle(T, vec.base, undefined, mask: {
                var mask: @Vector(s.len, i32) = undefined;
                for (0.., s) |i, ch| {
                    mask[i] = std.mem.indexOfScalar(u8, "xyzw"[0..dimn], ch) orelse
                        @compileError("Vector.swizzle only supports 2 <= dimn <= 4");
                }
                break :mask mask;
            }) };
        }

        pub fn add(lhs: Vector(dimn, T), rhs: Vector(dimn, T)) Vector(dimn, T) {
            return .{ .base = lhs.base + rhs.base };
        }

        pub fn sub(lhs: Vector(dimn, T), rhs: Vector(dimn, T)) Vector(dimn, T) {
            return .{ .base = lhs.base - rhs.base };
        }

        pub fn dot(lhs: Vector(dimn, T), rhs: Vector(dimn, T)) T {
            return @reduce(.Add, lhs.base * rhs.base);
        }

        pub fn cross(lhs: Vector(dimn, T), rhs: Vector(dimn, T)) Vector(dimn, T) {
            if (dimn != 3) {
                @compileError("Vector.cross only supports dimn == 3");
            }
            const ret1 = @shuffle(T, lhs.base, undefined, .{ 1, 2, 0 });
            ret1 *= @shuffle(T, rhs.base, undefined, .{ 2, 0, 1 });
            const ret2 = @shuffle(T, rhs.base, undefined, .{ 1, 2, 0 });
            ret2 *= @shuffle(T, lhs.base, undefined, .{ 2, 0, 1 });
            return .{ .base = ret1 - ret2 };
        }

        pub fn lengthSquared(vec: Vector(dimn, T)) T {
            return vec.dot(vec);
        }

        pub fn length(vec: Vector(dimn, T)) T {
            return @sqrt(vec.lengthSquared());
        }

        pub fn distanceSquared(vec1: Vector(dimn, T), vec2: Vector(dimn, T)) T {
            return vec1.sub(vec2).lengthSquared();
        }

        pub fn distance(vec1: Vector(dimn, T), vec2: Vector(dimn, T)) T {
            return @sqrt(vec1.distanceSquared(vec2));
        }

        pub fn scale(vec: Vector(dimn, T), scalar: T) Vector(dimn, T) {
            return .{ .base = vec.base * @as(@Vector(dimn, T), @splat(scalar)) };
        }

        pub fn scaleTo(vec: Vector(dimn, T), scalar: T, comptime tol: T) ?Vector(dimn, T) {
            const len_sq = vec.lengthSquared();
            return if (!std.math.approxEqAbs(T, len_sq, 0, tol))
                vec.scale(scalar / @sqrt(len_sq))
            else
                null;
        }

        pub fn normalize(vec: Vector(dimn, T), comptime tol: T) ?Vector(dimn, T) {
            return vec.scaleTo(1, tol);
        }
    };
}

pub fn Matrix(rows: usize, cols: usize, T: type) type {
    return struct {
        base: @Vector(rows * cols, T) = undefined,

        const type_info: TypeInfo = .{ .mat = .{ .rows = rows, .cols = cols, .T = T } };

        fn idx(rowi: usize, colj: usize) usize {
            return cols * rowi + colj;
        }

        pub fn initRowMajor(arr: *const [rows * cols]T) Matrix(rows, cols, T) {
            return .{ .base = arr.* };
        }

        pub fn initColMajor(arr: *const [cols * rows]T) Matrix(rows, cols, T) {
            return Matrix(cols, rows, T).initRowMajor(arr).transpose();
        }

        pub fn toRowMajor(mat: *const Matrix(rows, cols, T)) [rows * cols]T {
            return mat.base;
        }

        pub const zero: Matrix(rows, cols, T) = .initRowMajor(&(.{0} ** (rows * cols)));

        pub const identity: Matrix(rows, cols, T) = if (rows == cols and rows != 0)
            .initRowMajor(&((.{1} ++ .{0} ** rows) ** (rows - 1) ++ .{1}))
        else if (rows == cols)
            .{ .base = .{} }
        else
            @compileError("Matrix.identity only supports rows == cols");

        pub fn getIdx(mat: *const Matrix(rows, cols, T), rowi: usize, colj: usize) T {
            return mat.base[idx(rowi, colj)];
        }

        pub fn get(mat: *const Matrix(rows, cols, T), rowi: Axis(rows), colj: Axis(cols)) T {
            return mat.getIdx(@intFromEnum(rowi), @intFromEnum(colj));
        }

        pub fn getPtrIdx(mat: *Matrix(rows, cols, T), rowi: usize, colj: usize) *T {
            return mat.base[idx(rowi, colj)];
        }

        pub fn getPtr(mat: *Matrix(rows, cols, T), rowi: Axis(rows), colj: Axis(cols)) *T {
            return &mat.getPtrIdx(@intFromEnum(rowi), @intFromEnum(colj));
        }

        pub const Transpose = Matrix(cols, rows, T);

        pub fn transpose(mat: *const Matrix(rows, cols, T)) Transpose {
            return .{ .base = @shuffle(T, mat.base, undefined, mask: {
                var mask: @Vector(cols * rows, i32) = undefined;
                for (0..rows) |rowi| {
                    for (0..cols) |colj| {
                        mask[Transpose.idx(colj, rowi)] = idx(rowi, colj);
                    }
                }
                break :mask mask;
            }) };
        }

        pub fn rowIdx(mat: *const Matrix(rows, cols, T), rowi: usize) Vector(cols, T) {
            return switch (rowi) {
                inline 0...(rows - 1) => |rowi_ct| .{
                    .base = @shuffle(T, mat.base, undefined, mask: {
                        var mask: @Vector(cols, i32) = undefined;
                        for (0..cols) |colj| {
                            mask[colj] = idx(rowi_ct, colj);
                        }
                        break :mask mask;
                    }),
                },
                else => @panic("rowIdx out of bounds"),
            };
        }

        pub fn row(mat: *const Matrix(rows, cols, T), rowi: Axis(rows)) Vector(cols, T) {
            return mat.rowIdx(@intFromEnum(rowi));
        }

        pub fn colIdx(mat: *const Matrix(rows, cols, T), colj: usize) Vector(rows, T) {
            return switch (colj) {
                inline 0...(cols - 1) => |colj_ct| .{
                    .base = @shuffle(T, mat.base, undefined, mask: {
                        var mask: @Vector(rows, i32) = undefined;
                        for (0..rows) |rowi| {
                            mask[rowi] = idx(rowi, colj_ct);
                        }
                        break :mask mask;
                    }),
                },
                else => @panic("colIdx out of bounds"),
            };
        }

        pub fn col(mat: *const Matrix(rows, cols, T), colj: Axis(cols)) Vector(rows, T) {
            return mat.colIdx(@intFromEnum(colj));
        }

        pub fn MultType(rhs: type) type {
            blk: {
                const base = switch (@typeInfo(rhs)) {
                    .pointer => |p| p.child,
                    .@"struct" => rhs,
                    else => break :blk,
                };
                switch (TypeInfo.get(base) orelse break :blk) {
                    .vec => |v| if (v.dimn == cols and v.T == T)
                        return Vector(rows, T),
                    .mat => |m| if (m.rows == cols and m.T == T)
                        return Matrix(rows, m.cols, T),
                }
            }
            @compileError("Matrix.mult does not support lhs " ++
                @typeName(*const Matrix(rows, cols, T)) ++ " with rhs " ++ @typeName(rhs));
        }

        pub fn mult(lhs: *const Matrix(rows, cols, T), rhs: anytype) MultType(@TypeOf(rhs)) {
            var prod: MultType(@TypeOf(rhs)) = undefined;
            const base = switch (@typeInfo(@TypeOf(rhs))) {
                .pointer => |p| p.child,
                .@"struct" => @TypeOf(rhs),
                else => comptime unreachable,
            };
            switch (comptime (TypeInfo.get(base).?)) {
                .vec => for (0..rows) |rowi| {
                    prod.base[rowi] = lhs.rowIdx(rowi).dot(rhs);
                },
                .mat => |m| for (0..m.cols) |colj| {
                    const rcol = rhs.colIdx(colj);
                    for (0..rows) |rowi| {
                        prod.base[@TypeOf(prod).idx(rowi, colj)] = lhs.rowIdx(rowi).dot(rcol);
                    }
                },
            }
            return prod;
        }

        pub fn look(pos: Vector(3, T), azimuth: T, inclination: T) Matrix(rows, cols, T) {
            if (rows != 4 or cols != 4) {
                @compileError("Matrix.look only supports rows == 4 and cols == 4");
            }
            if (T != f32 and T != f64) {
                @compileError("Matrix.look only supports T == f32 or T == f64");
            }
            const cy = @cos(azimuth);
            const sy = @sin(azimuth);
            const cp = @cos(inclination);
            const sp = @sin(inclination);
            const cam_x: Vector(3, T) = .init(sy, -cy, 0); // right
            const cam_y: Vector(3, T) = .init(-cy * sp, -sy * sp, cp); // up
            const cam_z: Vector(3, T) = .init(-cy * cp, -sy * cp, -sp); // backwards
            return .{ .base = .{
                cam_x.get(.x), cam_x.get(.y), cam_x.get(.z), -cam_x.dot(pos),
                cam_y.get(.x), cam_y.get(.y), cam_y.get(.z), -cam_y.dot(pos),
                cam_z.get(.x), cam_z.get(.y), cam_z.get(.z), -cam_z.dot(pos),
                0.0,           0.0,           0.0,           1.0,
            } };
        }

        pub fn perspective(z_near: T, fov_y: T, aspect_ratio: T) Matrix(rows, cols, T) {
            if (rows != 4 or cols != 4) {
                @compileError("Matrix.look only supports rows == 4 and cols == 4");
            }
            if (T != f32 and T != f64) {
                @compileError("Matrix.look only supports T == f32 or T == f64");
            }
            const scale_y = 1.0 / @tan(fov_y * 0.5);
            const scale_x = scale_y / aspect_ratio;
            return .{ .base = .{
                scale_x, 0.0,     0.0,  0.0,
                0.0,     scale_y, 0.0,  0.0,
                0.0,     0.0,     -1.0, -2.0 * z_near,
                0.0,     0.0,     -1.0, 0.0,
            } };
        }

        pub fn ortho(width: T, height: f32) Matrix(rows, cols, T) {
            if (rows != 4 or cols != 4) {
                @compileError("Matrix.look only supports rows == 4 and cols == 4");
            }
            if (T != f32 and T != f64) {
                @compileError("Matrix.look only supports T == f32 or T == f64");
            }
            return .{ .base = .{
                2.0 / width, 0.0,           0.0,  -1.0,
                0.0,         -2.0 / height, 0.0,  1.0,
                0.0,         0.0,           -1.0, 0.0,
                0.0,         0.0,           0.0,  1.0,
            } };
        }

        pub fn axisRotationIdx(from: usize, to: usize, angle: T) Matrix(rows, cols, T) {
            if (rows != cols) {
                @compileError("Matrix.axisRotationIdx only supports rows == cols");
            }
            if (T != f32 and T != f64) {
                @compileError("Matrix.axisRotationIdx only supports T == f32 or T == f64");
            }
            var mat: Matrix(rows, cols, T) = identity;
            if (from != to) {
                const c = @cos(angle);
                const s = @sin(angle);
                mat.base[idx(from, from)] = c;
                mat.base[idx(to, to)] = c;
                mat.base[idx(from, to)] = -s;
                mat.base[idx(to, from)] = s;
            }
            return mat;
        }

        pub fn axisRotation(from: Axis(rows), to: Axis(rows), angle: T) Matrix(rows, cols, T) {
            return axisRotationIdx(@intFromEnum(from), @intFromEnum(to), angle);
        }
    };
}
