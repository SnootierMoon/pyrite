const c = @import("root").c;
const std = @import("std");

const RuneRange = struct { start: u21, end: u21 };

const Vec2 = struct { x: f32, y: f32 };

const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

const Image = struct {
    user_ptr: ?*anyopaque,
    w: u16,
    h: u16,
    region: [4]u16,
};

const Cursor = struct {
    image: Image,
    size: Vec2,
    offset: Vec2,
};

const UserFont = struct {
    user_ptr: ?*anyopaque,
    height: f32,
    width_fn: *const fn (?*anyopaque, height: f32, txt: []const u8) f32,
    query_fn: *const fn (?*anyopaque, height: f32, codepoint: u21, next_codepoint: u21) Glyph,
    texture: ?*anyopaque,

    const Glyph = struct {
        uv: [2]Vec2,
        offset: Vec2,
        width: f32,
        height: f32,
        xadvance: f32,
    };
};

const BakedFont = struct {
    height: f32,
    ascent: f32,
    descent: f32,
    glyph_offset: u21,
    glyph_count: u21,
    ranges: []const RuneRange,
};

pub const Font = struct {
    user_font: UserFont,
    baked_font: BakedFont,
    scale: f32,
    glyphs: []Font.Glyph,
    fallback: *Font.Glyph,
    fallback_codepoint: u21,
    texture: ?*anyopaque,
    configs: FontConfig.List,
    nkuf: c.nk_user_font,

    const List = std.SegmentedList(Font, 8);

    const Glyph = struct {
        codepoint: u21,
        xadvance: f32,
        x0: f32,
        y0: f32,
        x1: f32,
        y1: f32,
        w: f32,
        h: f32,
        u0: f32,
        v0: f32,
        u1: f32,
        v1: f32,
    };

    fn findGlyph(font: *const Font, codepoint: u21) *Glyph {
        var config_it = font.configs.constIterator(0);
        var glyph_offset: usize = 0;
        while (config_it.next()) |config| {
            for (config.ranges) |range| {
                defer glyph_offset += range.end - range.start;

                if (range.start <= codepoint and codepoint < range.end) {
                    return &font.glyphs[glyph_offset + (codepoint - range.start)];
                }
            }
        }
        return font.fallback;
    }

    fn widthFnNk(font_ptr: c.nk_handle, h: f32, buf: ?[*]const u8, len: c_int) callconv(.C) f32 {
        return widthFn(font_ptr.ptr, h, buf.?[0..@intCast(len)]);
    }

    fn queryFnNk(font_ptr: c.nk_handle, font_height: f32, glyph: ?*c.nk_user_font_glyph, codepoint: c.nk_rune, next_codepoint: c.nk_rune) callconv(.C) void {
        const gg = queryFn(font_ptr.ptr, font_height, @intCast(codepoint), @intCast(next_codepoint));
        glyph.?.* = .{
            .width = gg.width,
            .height = gg.height,
            .offset = .{ .x = gg.offset.x, .y = gg.offset.y },
            .xadvance = gg.xadvance,
            .uv = .{
                .{ .x = gg.uv[0].x, .y = gg.uv[0].y },
                .{ .x = gg.uv[1].x, .y = gg.uv[1].y },
            },
        };
    }

    fn widthFn(font_ptr: ?*anyopaque, height: f32, txt: []const u8) f32 {
        const font: *Font = @alignCast(@ptrCast(font_ptr.?));
        const scale = height / font.baked_font.height;
        var text_width: f32 = 0.0;

        var it = (std.unicode.Utf8View.init(txt) catch unreachable).iterator();
        while (it.nextCodepointSlice()) |slice| {
            const codepoint = std.unicode.utf8Decode(slice) catch unreachable;
            const glyph = font.findGlyph(codepoint);
            text_width += glyph.xadvance * scale;
        }
        return text_width;
    }

    fn queryFn(font_ptr: ?*anyopaque, height: f32, codepoint: u21, next_codepoint: u21) UserFont.Glyph {
        _ = next_codepoint;
        const font: *Font = @alignCast(@ptrCast(font_ptr.?));
        const scale = height / font.baked_font.height;
        const glyph = font.findGlyph(codepoint);

        return .{
            .width = (glyph.x1 - glyph.x0) * scale,
            .height = (glyph.y1 - glyph.y0) * scale,
            .offset = .{ .x = glyph.x0 * scale, .y = glyph.y0 * scale },
            .xadvance = glyph.xadvance * scale,
            .uv = .{
                .{ .x = glyph.u0, .y = glyph.v0 },
                .{ .x = glyph.u1, .y = glyph.v1 },
            },
        };
    }
};

const TexCoordType = enum { uv, pixel };

const FontConfig = struct {
    ttf: []const u8,
    height: f32,

    merge_mode: bool,
    pixel_snap: bool,
    oversample_h: u8,
    oversample_v: u8,

    tex_coord_type: TexCoordType,
    spacing: Vec2,
    ranges: []const RuneRange,
    baked_font: *BakedFont,
    fallback_codepoint: u21,

    const List = std.SegmentedList(FontConfig, 8);
};

pub const FontAtlas = struct {
    texture_width: u32,
    texture_height: u32,
    custom: Rect,

    glyphs: []Font.Glyph,
    default_font: ?*Font,

    fonts_len: usize,
    fonts: Font.List,

    // TODO
    // struct nk_cursor cursors[NK_CURSOR_COUNT];

    pub const TTFAddInfo = struct {
        ttf: []const u8,
        height: f32,

        merge_mode: bool = false,
        pixel_snap: bool = false,
        oversample_h: u8 = 3,
        oversample_v: u8 = 1,

        tex_coord_type: TexCoordType = .uv,
        spacing: Vec2 = .{ .x = 0.0, .y = 0.0 },
        ranges: []const RuneRange = &.{.{ .start = 0x20, .end = 0x100 }},
        fallback_codepoint: u21 = '?',
    };

    pub fn init(gpa: std.mem.Allocator) !*FontAtlas {
        const atlas = try gpa.create(FontAtlas);
        atlas.* = .{
            .texture_width = undefined,
            .texture_height = undefined,
            .custom = undefined,
            .glyphs = &.{},
            .default_font = undefined,
            .fonts_len = 0,
            .fonts = .{},
        };
        return atlas;
    }

    const FontIterator = std.SegmentedList(Font, 8).Iterator;

    const ConfigIterator = struct {
        font_it: FontIterator,
        config_it: std.SegmentedList(FontConfig, 8).Iterator,

        fn next(it: *ConfigIterator) ?*FontConfig {
            while (true) {
                if (it.config_it.next()) |config| {
                    return config;
                } else if (it.font_it.next()) |font| {
                    it.config_it = font.configs.iterator(0);
                } else return null;
            }
        }
    };

    fn fontIterator(atlas: *FontAtlas) FontIterator {
        return atlas.fonts.iterator(0);
    }

    fn configIterator(atlas: *FontAtlas) ConfigIterator {
        var it = atlas.fontIterator();
        return if (it.next()) |font| .{
            .font_it = it,
            .config_it = font.configs.iterator(0),
        } else .{
            .font_it = (@constCast(&std.SegmentedList(Font, 8){})).iterator(0),
            .config_it = (@constCast(&std.SegmentedList(FontConfig, 8){})).iterator(0),
        };
    }

    pub fn deinit(atlas: *FontAtlas, gpa: std.mem.Allocator) void {
        gpa.free(atlas.glyphs);
        var font_it = atlas.fontIterator();
        while (font_it.next()) |font| {
            font.configs.deinit(gpa);
        }
        atlas.fonts.deinit(gpa);
        gpa.destroy(atlas);
    }

    pub fn addTTF(atlas: *FontAtlas, gpa: std.mem.Allocator, info: TTFAddInfo) !*Font {
        std.debug.assert(info.height > 0.0);

        const font = if (info.merge_mode)
            atlas.fonts.at(atlas.fonts.len - 1)
        else
            try atlas.fonts.addOne(gpa);
        errdefer if (!info.merge_mode) {
            atlas.fonts.len -= 1;
        };

        const config = try font.configs.addOne(gpa);
        errdefer font.configs.len -= 1;

        config.* = .{
            .ttf = info.ttf,
            .height = info.height,
            .merge_mode = info.merge_mode,
            .pixel_snap = info.pixel_snap,
            .oversample_h = info.oversample_h,
            .oversample_v = info.oversample_v,
            .tex_coord_type = info.tex_coord_type,
            .spacing = info.spacing,
            .ranges = info.ranges,
            .baked_font = &font.baked_font,
            .fallback_codepoint = info.fallback_codepoint,
        };

        atlas.fonts_len += 1;
        return font;
    }

    pub const Result = struct {
        pixels: []const u8,
        width: usize,
        height: usize,
    };

    pub fn bake(
        atlas: *FontAtlas,
        gpa: std.mem.Allocator,
        format: FontBaker.Format,
    ) !Result {
        std.debug.assert(atlas.fonts_len > 0);

        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();

        var total_glyph_count: usize = 0;
        var total_range_count: usize = 0;

        var config_it = atlas.configIterator();
        while (config_it.next()) |config| {
            total_range_count += config.ranges.len;
            for (config.ranges) |range| {
                total_glyph_count += range.end - range.start;
            }
        }

        var baker: *FontBaker = try .init(
            arena.allocator(),
            atlas,
            total_glyph_count,
            total_range_count,
            atlas.fonts_len,
        );

        atlas.custom.x = 0;
        atlas.custom.y = 0;
        atlas.custom.w = (cursor_data_width * 2) + 1;
        atlas.custom.h = cursor_data_height + 1;

        {
            try baker.begin();
            defer baker.end();
            try baker.pack();
            // if I ever port STBTT/STBRP to Zig, then allocate this outside the
            // arena and perform a8_unorm -> r8a8g8b8_unorm conversion in place
            baker.pixels = try arena.allocator().alloc(u8, baker.height * baker.width);
            try baker.bake();
        }
        atlas.glyphs = try gpa.alloc(Font.Glyph, total_glyph_count);
        errdefer {
            gpa.free(atlas.glyphs);
            atlas.glyphs = &.{};
        }
        try baker.finalize();

        const pixels = try gpa.alloc(u8, switch (format) {
            .r8g8b8a8_unorm => baker.height * baker.width * 4,
            .a8_unorm => baker.height * baker.width,
        });
        errdefer gpa.free(pixels);
        switch (format) {
            .r8g8b8a8_unorm => {
                for (0..baker.height * baker.width) |i| {
                    pixels[i * 4] = 0xff;
                    pixels[i * 4 + 1] = 0xff;
                    pixels[i * 4 + 2] = 0xff;
                    pixels[i * 4 + 3] = baker.pixels[i];
                }
            },
            .a8_unorm => @memcpy(pixels, baker.pixels),
        }

        atlas.texture_width = baker.width;
        atlas.texture_height = baker.height;

        var font_it = atlas.fontIterator();
        while (font_it.next()) |font| {
            const config = font.configs.at(0);
            const scale = config.height / font.baked_font.height;
            font.user_font.user_ptr = font;
            font.user_font.height = font.baked_font.height * scale;
            font.user_font.width_fn = Font.widthFn;
            font.user_font.query_fn = Font.queryFn;
            font.nkuf = .{
                .userdata = .{ .ptr = font },
                .height = font.baked_font.height * scale,
                .width = Font.widthFnNk,
                .query = Font.queryFnNk,
            };
            font.scale = scale;
            font.glyphs = atlas.glyphs[font.baked_font.glyph_offset..][0..font.baked_font.glyph_count];
            font.fallback_codepoint = config.fallback_codepoint;
            font.fallback = font.findGlyph(font.fallback_codepoint);
        }

        return .{
            .pixels = pixels,
            .width = baker.width,
            .height = baker.height,
        };
    }

    pub fn end(atlas: *FontAtlas, texture: ?*anyopaque, tex_null: ?*c.nk_draw_null_texture) void {
        if (tex_null) |t| {
            t.texture = c.nk_handle_ptr(texture);
            t.uv.x = (@as(f32, @floatFromInt(atlas.custom.x)) + 0.5) / @as(f32, @floatFromInt(atlas.texture_width));
            t.uv.y = (@as(f32, @floatFromInt(atlas.custom.y)) + 0.5) / @as(f32, @floatFromInt(atlas.texture_width));
        }
        var font_it = atlas.fontIterator();
        while (font_it.next()) |font| {
            font.texture = texture;
            font.user_font.texture = texture;
            font.nkuf.texture = c.nk_handle_ptr(texture);
        }
    }
};

const FontBaker = struct {
    arena: std.mem.Allocator,
    atlas: *FontAtlas,
    spc: c.stbtt_pack_context,
    fonts: []FontInfo,
    packedchars: []c.stbtt_packedchar,
    rects: []c.stbrp_rect,
    ranges: []c.stbtt_pack_range,

    width: u32,
    height: u32,
    pixels: []u8,

    const Format = enum { a8_unorm, r8g8b8a8_unorm };

    const FontInfo = struct {
        info: c.stbtt_fontinfo,
        rects: []c.stbrp_rect,
        ranges: []c.stbtt_pack_range,
    };

    fn init(
        arena: std.mem.Allocator,
        atlas: *FontAtlas,
        total_glyph_count: usize,
        total_range_count: usize,
        fonts_len: usize,
    ) !*FontBaker {
        const baker = try arena.create(FontBaker);
        baker.* = .{
            .arena = arena,
            .atlas = atlas,
            .spc = undefined,
            .fonts = try arena.alloc(FontInfo, fonts_len),
            .packedchars = try arena.alloc(c.stbtt_packedchar, total_glyph_count),
            .rects = try arena.alloc(c.stbrp_rect, total_glyph_count),
            .ranges = try arena.alloc(c.stbtt_pack_range, total_range_count),

            .width = undefined,
            .height = undefined,
            .pixels = undefined,
        };

        var index: usize = 0;
        var config_it = baker.atlas.configIterator();
        while (config_it.next()) |config| : (index += 1) {
            if (c.stbtt_InitFont(
                &baker.fonts[index].info,
                config.ttf.ptr,
                c.stbtt_GetFontOffsetForIndex(config.ttf.ptr, 0),
            ) == 0) {
                return error.Stbtt;
            }
            baker.fonts[index].info.userdata = @import("root").AAA;
        }

        return baker;
    }

    fn begin(baker: *FontBaker) !void {
        // ????
        const max_height = 1024 * 32;
        baker.height = 0;
        baker.width = if (baker.packedchars.len > 1000) 1024 else 512;

        if (c.stbtt_PackBegin(
            &baker.spc,
            null,
            @intCast(baker.width),
            max_height,
            0,
            1,
            @import("root").AAA,
        ) == 0) {
            return error.Stbtt;
        }
    }

    fn end(baker: *FontBaker) void {
        c.stbtt_PackEnd(&baker.spc);
    }

    fn pack(baker: *FontBaker) !void {
        var custom_space = std.mem.zeroInit(c.stbrp_rect, .{
            .w = @as(c_int, @intCast(baker.atlas.custom.w)),
            .h = @as(c_int, @intCast(baker.atlas.custom.h)),
        });
        c.stbtt_PackSetOversampling(&baker.spc, 1, 1);
        if (c.stbrp_pack_rects(@alignCast(@ptrCast(baker.spc.pack_info)), &custom_space, 1) == 0) {
            return error.Stbrp;
        }
        baker.height = @max(baker.height, @as(u32, @intCast(custom_space.y + custom_space.h)));
        baker.atlas.custom.x = @intCast(custom_space.x);
        baker.atlas.custom.y = @intCast(custom_space.y);
        baker.atlas.custom.w = @intCast(custom_space.w);
        baker.atlas.custom.h = @intCast(custom_space.h);

        var range_offset: usize = 0;
        var packedchars_offset: usize = 0;
        var rect_offset: usize = 0;

        var index: usize = 0;
        var config_it = baker.atlas.configIterator();
        while (config_it.next()) |config| : (index += 1) {
            const baker_font = &baker.fonts[index];
            var glyph_count: usize = 0;
            for (config.ranges) |range| {
                glyph_count += range.end - range.start;
            }
            defer range_offset += config.ranges.len;
            baker_font.ranges = baker.ranges[range_offset..][0..config.ranges.len];
            for (baker_font.ranges, config.ranges) |*font_range, cfg_range| {
                const num_chars = cfg_range.end - cfg_range.start;
                defer packedchars_offset += num_chars;
                font_range.* = .{
                    .font_size = config.height,
                    .first_unicode_codepoint_in_range = cfg_range.start,
                    .num_chars = num_chars,
                    .chardata_for_range = baker.packedchars[packedchars_offset..].ptr,
                };
            }
            defer rect_offset += glyph_count;
            baker_font.rects = baker.rects[rect_offset..][0..glyph_count];
            c.stbtt_PackSetOversampling(&baker.spc, config.oversample_h, config.oversample_v);
            std.debug.assert(c.stbtt_PackFontRangesGatherRects(
                &baker.spc,
                &baker_font.info,
                baker_font.ranges.ptr,
                @intCast(baker_font.ranges.len),
                baker_font.rects.ptr,
            ) == glyph_count);
            if (c.stbrp_pack_rects(
                @alignCast(@ptrCast(baker.spc.pack_info)),
                baker_font.rects.ptr,
                @intCast(glyph_count),
            ) == 0) {
                return error.Stbrp;
            }
            for (baker_font.rects[0..glyph_count]) |rect| {
                baker.height = @max(baker.height, @as(u32, @intCast(rect.y + rect.h)));
            }
        }

        baker.height = std.math.ceilPowerOfTwo(u32, baker.height) catch unreachable;
        std.debug.assert(range_offset == baker.ranges.len);
        std.debug.assert(packedchars_offset == baker.packedchars.len);
        std.debug.assert(rect_offset == baker.rects.len);
    }

    fn bake(baker: *FontBaker) !void {
        @memset(baker.pixels, 0);
        baker.spc.pixels = baker.pixels.ptr;
        baker.spc.height = @intCast(baker.height);

        var index: usize = 0;
        var config_it = baker.atlas.configIterator();
        while (config_it.next()) |config| : (index += 1) {
            const baker_font = &baker.fonts[index];
            c.stbtt_PackSetOversampling(
                &baker.spc,
                config.oversample_h,
                config.oversample_v,
            );
            if (c.stbtt_PackFontRangesRenderIntoRects(
                &baker.spc,
                &baker_font.info,
                baker_font.ranges.ptr,
                @intCast(baker_font.ranges.len),
                baker_font.rects.ptr,
            ) == 0) {
                return error.Stbtt;
            }
        }
    }

    fn finalize(baker: *FontBaker) !void {
        var glyph_offset: u21 = 0;

        var index: usize = 0;
        var config_it = baker.atlas.configIterator();
        while (config_it.next()) |config| : (index += 1) {
            const baker_font = &baker.fonts[index];
            const font_scale = c.stbtt_ScaleForPixelHeight(&baker_font.info, config.height);
            var unscaled_ascent: c_int = undefined;
            var unscaled_descent: c_int = undefined;
            var unscaled_line_gap: c_int = undefined;
            c.stbtt_GetFontVMetrics(
                &baker_font.info,
                &unscaled_ascent,
                &unscaled_descent,
                &unscaled_line_gap,
            );
            if (!config.merge_mode) {
                config.baked_font.ranges = config.ranges;
                config.baked_font.height = config.height;
                config.baked_font.ascent = @as(f32, @floatFromInt(unscaled_ascent)) * font_scale;
                config.baked_font.descent = @as(f32, @floatFromInt(unscaled_descent)) * font_scale;
                config.baked_font.ascent = @as(f32, @floatFromInt(unscaled_ascent)) * font_scale;
                config.baked_font.glyph_offset = glyph_offset;
                config.baked_font.glyph_count = 0;
            }

            var glyph_count: u21 = 0;
            defer config.baked_font.glyph_count += glyph_count;
            defer glyph_offset += glyph_count;

            for (baker_font.ranges) |range| {
                for (0..@intCast(range.num_chars)) |char_idx| {
                    defer glyph_count += 1;
                    const pc = &range.chardata_for_range[char_idx];
                    var dummy_x: f32 = undefined;
                    var dummy_y: f32 = undefined;
                    var q: c.stbtt_aligned_quad = undefined;
                    c.stbtt_GetPackedQuad(
                        range.chardata_for_range,
                        @intCast(baker.width),
                        @intCast(baker.height),
                        @intCast(char_idx),
                        &dummy_x,
                        &dummy_y,
                        &q,
                        0,
                    );
                    const scale_x: f32, const scale_y: f32 = switch (config.tex_coord_type) {
                        .pixel => .{ @floatFromInt(baker.width), @floatFromInt(baker.height) },
                        .uv => .{ 1.0, 1.0 },
                    };
                    baker.atlas.glyphs[
                        config.baked_font.glyph_offset +
                            config.baked_font.glyph_count +
                            glyph_count
                    ] = .{
                        .codepoint = @as(u21, @intCast(range.first_unicode_codepoint_in_range)) +
                            @as(u21, @intCast(char_idx)),
                        .x0 = q.x0,
                        .y0 = q.y0 + config.baked_font.ascent + 0.5,
                        .x1 = q.x1,
                        .y1 = q.y1 + config.baked_font.ascent + 0.5,
                        .w = q.x1 - q.x0 + 0.5,
                        .h = q.y1 - q.y0,
                        .u0 = q.s0 * scale_x,
                        .v0 = q.t0 * scale_y,
                        .u1 = q.s1 * scale_x,
                        .v1 = q.t1 * scale_y,
                        .xadvance = if (config.pixel_snap)
                            @round(pc.xadvance + config.spacing.x + 0.5)
                        else
                            pc.xadvance + config.spacing.x,
                    };
                }
            }
        }

        for (0..cursor_data_height) |y| {
            for (0..cursor_data_width) |x| {
                const data_idx = y * cursor_data_width + x;
                const idx_white = (baker.atlas.custom.y + y) * baker.width + baker.atlas.custom.x + x;
                const idx_black = idx_white + cursor_data_width + 1;
                baker.pixels[idx_white] = if (cursor_data[data_idx] == '.') 0xFF else 0x00;
                baker.pixels[idx_black] = if (cursor_data[data_idx] == 'X') 0xFF else 0x00;
            }
        }
    }
};

const cursor_data_width = 90;
const cursor_data_height = 27;
const cursor_data: [cursor_data_height * cursor_data_width]u8 =
    ("..-         -XXXXXXX-    X    -           X           -XXXXXXX          -          XXXXXXX" ++
    "..-         -X.....X-   X.X   -          X.X          -X.....X          -          X.....X" ++
    "---         -XXX.XXX-  X...X  -         X...X         -X....X           -           X....X" ++
    "X           -  X.X  - X.....X -        X.....X        -X...X            -            X...X" ++
    "XX          -  X.X  -X.......X-       X.......X       -X..X.X           -           X.X..X" ++
    "X.X         -  X.X  -XXXX.XXXX-       XXXX.XXXX       -X.X X.X          -          X.X X.X" ++
    "X..X        -  X.X  -   X.X   -          X.X          -XX   X.X         -         X.X   XX" ++
    "X...X       -  X.X  -   X.X   -    XX    X.X    XX    -      X.X        -        X.X      " ++
    "X....X      -  X.X  -   X.X   -   X.X    X.X    X.X   -       X.X       -       X.X       " ++
    "X.....X     -  X.X  -   X.X   -  X..X    X.X    X..X  -        X.X      -      X.X        " ++
    "X......X    -  X.X  -   X.X   - X...XXXXXX.XXXXXX...X -         X.X   XX-XX   X.X         " ++
    "X.......X   -  X.X  -   X.X   -X.....................X-          X.X X.X-X.X X.X          " ++
    "X........X  -  X.X  -   X.X   - X...XXXXXX.XXXXXX...X -           X.X..X-X..X.X           " ++
    "X.........X -XXX.XXX-   X.X   -  X..X    X.X    X..X  -            X...X-X...X            " ++
    "X..........X-X.....X-   X.X   -   X.X    X.X    X.X   -           X....X-X....X           " ++
    "X......XXXXX-XXXXXXX-   X.X   -    XX    X.X    XX    -          X.....X-X.....X          " ++
    "X...X..X    ---------   X.X   -          X.X          -          XXXXXXX-XXXXXXX          " ++
    "X..X X..X   -       -XXXX.XXXX-       XXXX.XXXX       ------------------------------------" ++
    "X.X  X..X   -       -X.......X-       X.......X       -    XX           XX    -           " ++
    "XX    X..X  -       - X.....X -        X.....X        -   X.X           X.X   -           " ++
    "      X..X          -  X...X  -         X...X         -  X..X           X..X  -           " ++
    "       XX           -   X.X   -          X.X          - X...XXXXXXXXXXXXX...X -           " ++
    "------------        -    X    -           X           -X.....................X-           " ++
    "                    ----------------------------------- X...XXXXXXXXXXXXX...X -           " ++
    "                                                      -  X..X           X..X  -           " ++
    "                                                      -   X.X           X.X   -           " ++
    "                                                      -    XX           XX    -           ").*;
