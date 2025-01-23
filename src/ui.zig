pub const Font = struct {};
pub const FontConfig = struct {};

pub const FontAtlas = struct {
    pub fn addDefault(atlas: *FontAtlas, pixel_height: f32, config: *FontConfig) Font {
        return atlas.addCompressedBase85(pixel_height, config);
    }
};
