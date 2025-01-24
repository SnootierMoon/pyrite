pub const TexNull = struct {};

pub const RenderConfig = struct {
    global_alpha: f32,
    line_AA: bool,
    shape_AA: bool,
    circle_segment_count: u16,
    arc_segment_count: u16,
    curve_segment_count: u16,
    tex_null: TexNull,

    // pub const TexNull = struct {
    //     texture: ?*anyopaque,
    //     uv:
    // };
};

// pub fn render(config: RenderConfig) void {
// }
