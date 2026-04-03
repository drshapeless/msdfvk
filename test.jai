main :: () {
    data := read_entire_file("Hack-Regular.ttf");
    size_sdf := 26;
    size_bitmap := 32;

    font: stbtt_fontinfo;
    stbtt_InitFont(*font, data.data, stbtt_GetFontOffsetForIndex(data.data, 0));

    ascent, descent: s32;
    stbtt_GetFontVMetrics(*font, *ascent, *descent, null);

    scale := stbtt_ScaleForPixelHeight(*font, xx size_sdf);
    baseline := cast(s32)(cast(float)ascent*scale);

    success, metrics, msdf := generate_msdf(*font, #char "e", size_sdf, size_sdf);
    if !success log("Fuck");

    log("metrics %", metrics);
    log("msdf count: %", msdf.count);

    bitmap_sdf := NewArray(3*size_sdf*size_sdf, u8);
    for y: 0..size_sdf - 1 {
        for x: 0..size_sdf - 1 {
            index_sdf := calc_index(x, y, size_sdf, 3);
            bitmap_sdf[index_sdf+0] = xx (255*(msdf[index_sdf+0]+size_sdf)/size_sdf);
            bitmap_sdf[index_sdf+1] = xx (255*(msdf[index_sdf+1]+size_sdf)/size_sdf);
            bitmap_sdf[index_sdf+2] = xx (255*(msdf[index_sdf+2]+size_sdf)/size_sdf);
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
            a := clamp(sig_dist+0.5, 1.0, 0.0);

            bitmap[index+0] = cast(u8)(255*a);
            bitmap[index+1] = cast(u8)(255*a);
            bitmap[index+2] = cast(u8)(255*a);
        }
    }

    stbi_write_png("test_msdf.png", xx size_sdf, xx size_sdf, 3, bitmap_sdf.data, xx (size_sdf*3));
    stbi_write_png("test_out.png", xx size_bitmap, xx size_bitmap, 3, bitmap.data, xx (size_sdf*3));

}

calc_index :: (x: s64, y: s64, size: s64, num_channels: s64) -> s64 {
    x0 := clamp(x, size-1, 0);
    y0 := clamp(y, size-1, 0);
    return num_channels*((y0*size)+x0);
}

blerp :: (c00: float, c10: float, c01: float, c11: float, tx: float, ty: float) -> float {
    return lerp(lerp(c00, c10, tx), lerp(c01, c11, tx), ty);
}

median :: (r: float, g: float, b: float) -> float {
    return max(min(r, g), min(max(r, g), b));
}

#import "Basic";
#import "File";
#import "Math";
#import "stb_truetype";
#import "stb_image_write";
#import,file "msdfc.jai";
