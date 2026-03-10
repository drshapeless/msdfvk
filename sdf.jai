// This is a direct copy of stbtt_GetGlyphSDF
generate_glyph_sdf :: (info: *stbtt_fontinfo, scale: float, glyph: s32, padding: s32, onedge_value: u8, pixel_dist_scale: float) -> success:bool, width:s32, height:s32, xoff:s32, yoff:s32, data:[]u8 {
    if scale == 0 return false, 0, 0, 0, 0, {};

    scale_x := scale;
    scale_y := scale;

    ix0, iy0, ix1, iy1: s32;
    width, height: s32;
    data: []u8;

    stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale, scale, 0, 0, *ix0, *iy0, *ix1, *iy1);

    if x0 == x1 || y0 == y1 {
        return false, 0, 0, 0, 0, {};
    }

    ix0 -= padding;
    iy0 -= padding;
    ix1 += padding;
    iy1 += padding;

    width = ix1 - ix0;
    height = iy1 - iy0;

    scale_y = -scale_y;

    {
        eps: float = 1.0 / 1024;
        eps2 := eps * eps;

        verts: []stbtt_vertex;
        verts.count := xx stbtt_GetGlyphShape(info, glyph, *verts.data);
        data = NewArray(width * height, u8);
        precompute := NewArray(num_verts, float);

        j := verts.count - 1;
        for i: 0..verts.count - 1 {
            if verts[i].type == xx STBTT.vline {
                x0 := verts[i].x * scale_x;
                y0 := verts[i].y * scale_y;
                x1 := verts[j].x * scale_x;
                y1 := verts[j].y * scale_y;
                dist := sqrt(cast(float)((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)));
                precompute[i] = ifx dist < eps then 0.0 else 1.0 / dist;
            } else if verts[i].type == xx STBTT.vcurve {
                x2 := verts[j].x  * scale_x;
                y2 := verts[j].y  * scale_y;
                x1 := verts[i].cx * scale_x;
                y1 := verts[i].cy * scale_y;
                x0 := verts[i].x  * scale_x;
                y0 := verts[i].y  * scale_y;

                bx := x0 - 2 * x1 + x2;
                by := y0 - 2 * y1 + y2;
                len2 := bx * bx + by * by;
                if len2 >= eps2 {
                    precompute[i] = 1.0 / cast(float) len2;
                } else {
                    precompute[i] = 0.0;
                }
            } else {
                precompute[i] = 0.0;
            }

            j = i;
        }

        for y: iy0..iy1 - 1 {
            for x: ix0..ix1 - 1 {
                val: float;
                min_dist: float = 999999.0;
                sx := cast(float) x + 0.5;
                sy := cast(float) y + 0.5;
                x_gspace := sx / scale_x;
                y_gspace := sy / scale_y;


            }
        }
    }

    return true, width, height, ix0, iy0, data;
}

generate_codepoint_sdf :: (font: *stbtt_fontinfo, scale: float, glyph: s32, padding: s32, onedge_value: u8, pixel_dist_scale: float) -> success:bool, width:s32, height:s32, xoff:s32, yoff:s32, []u8 {


    return false, 0, 0, 0, 0, {};
}

#scope_file
compute_crossings_x :: (x: float, y: float, nverts: s32, verts: []stbtt_vertex) {
    orig := Vector2.{1, 0};
    ray  := Vector2.{1, 0};
    y_frac := fmod_cycling(y, 1.0); // TODO: Does this equal to fmod in C?
    winding := 0;
}

#import "Basic";
#import "File";
#import "Math";
#import "stb_truetype";
