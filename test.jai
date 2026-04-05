main :: () {
    data := read_entire_file("Hack-Regular.ttf");
    size_sdf := 64;
    size_bitmap := 256;

    font: stbtt_fontinfo;
    stbtt_InitFont(*font, data.data, stbtt_GetFontOffsetForIndex(data.data, 0));

    ascent, descent: s32;
    stbtt_GetFontVMetrics(*font, *ascent, *descent, null);

    scale := stbtt_ScaleForPixelHeight(*font, xx size_sdf);
    baseline := cast(s32)(cast(float)ascent*scale);

    msdf := generate_msdf(*font, stbtt_FindGlyphIndex(*font, #char "1"), size_sdf, size_sdf);

    bitmap_sdf := NewArray(3*size_sdf*size_sdf, u8);
    for y: 0..size_sdf - 1 {
        for x: 0..size_sdf - 1 {
            index_sdf := (y * size_sdf + x) * 3;
            bitmap_sdf[index_sdf+0] = xx (255*(msdf[index_sdf+0]+cast(float) size_sdf)/cast(float)size_sdf);
            bitmap_sdf[index_sdf+1] = xx (255*(msdf[index_sdf+1]+cast(float)size_sdf)/cast(float)size_sdf);
            bitmap_sdf[index_sdf+2] = xx (255*(msdf[index_sdf+2]+cast(float)size_sdf)/cast(float)size_sdf);
        }
    }

    bitmap := NewArray(3*size_bitmap*size_bitmap, u8);
    scale_bitmap := 0.75*cast(float)size_bitmap/size_sdf;
    for y: 0..size_bitmap - 1 {
        for x: 0..size_bitmap - 1 {
            index := calc_index(x, y, size_bitmap, 3);
            gx := x/cast(float)size_bitmap*size_sdf;
            gy := y/cast(float)size_bitmap*size_sdf;
            gxi := cast(s32)gx;
            gyi := cast(s32)gy;

            c00: *float = *msdf[calc_index(gxi,   gyi,   size_sdf, 3)];
            c10: *float = *msdf[calc_index(gxi+1, gyi,   size_sdf, 3)];
            c01: *float = *msdf[calc_index(gxi,   gyi+1, size_sdf, 3)];
            c11: *float = *msdf[calc_index(gxi+1, gyi+1, size_sdf, 3)];
            r := blerp(c00[0], c10[0], c01[0], c11[0], gx-gxi, gy-gyi);
            g := blerp(c00[1], c10[1], c01[1], c11[1], gx-gxi, gy-gyi);
            b := blerp(c00[2], c10[2], c01[2], c11[2], gx-gxi, gy-gyi);

            sig_dist := scale_bitmap * (median(r, g, b)-0.5);
            a := clamp(sig_dist+0.5, 0.0, 1.0);

            bitmap[index+0] = cast(u8)(255*a);
            bitmap[index+1] = cast(u8)(255*a);
            bitmap[index+2] = cast(u8)(255*a);
        }
    }

    stbi_write_png("test_msdf.png", xx size_sdf, xx size_sdf, 3, bitmap_sdf.data, xx (size_sdf*3));
    stbi_write_png("test_out.png", xx size_bitmap, xx size_bitmap, 3, bitmap.data, xx (size_bitmap*3));

    free(data);
    array_free(msdf);
    array_free(bitmap_sdf);
    array_free(bitmap);

    report_memory_leaks();
}

calc_index :: (x: s64, y: s64, size: s64, num_channels: s64) -> s64 {
    x0 := clamp(x, 0, size-1);
    y0 := clamp(y, 0, size-1);
    return (y0*size + x0) * num_channels;
}

blerp :: (c00: float, c10: float, c01: float, c11: float, tx: float, ty: float) -> float {
    return lerp(lerp(c00, c10, tx), lerp(c01, c11, tx), ty);
}

median :: (r: float, g: float, b: float) -> float {
    return max(min(r, g), min(max(r, g), b));
}

#import "Basic"()(MEMORY_DEBUGGER = true);
#import "File";
#import "Math";
#import "stb_truetype";
#import "stb_image_write";
#import,file "module.jai";
