main :: () {
    data := read_entire_file("Hack-Regular.ttf");
    size_sdf := 32;
    size_bitmap := 256;

    font: stbtt_fontinfo;
    stbtt_InitFont(*font, data.data, stbtt_GetFontOffsetForIndex(data.data, 0));

    ascent, descent: s32;
    stbtt_GetFontVMetrics(*font, *ascent, *descent, null);

    scale := stbtt_ScaleForPixelHeight(*font, xx size_sdf);
    baseline := cast(s32)(cast(float)ascent*scale);

    shape, metrics := make_shape(*font, stbtt_FindGlyphIndex(*font, #char "J"), size_sdf, size_sdf, false);
    for contour: shape.contours {
        log("contour %", it_index);
        for edge: contour.edges {
            log("edge % %", it_index, edge);
        }
    }

    log("metrics: %", metrics);
    windings := prepare_shape(*shape);

    msdf := generate_msdf(shape, windings, metrics, size_sdf, size_sdf);

    bitmap_sdf := make_bitmap_sdf(msdf, size_sdf);
    bitmap := make_bitmap_render(msdf, size_sdf, size_bitmap);

    stbi_write_png("test_msdf.png", xx size_sdf, xx size_sdf, 3, bitmap_sdf.data, xx (size_sdf*3));
    stbi_write_png("test_out.png", xx size_bitmap, xx size_bitmap, 3, bitmap.data, xx (size_bitmap*3));

    free(data);
    array_free(msdf);
    array_free(bitmap_sdf);
    array_free(bitmap);

    report_memory_leaks();
}

#import "Basic"()(MEMORY_DEBUGGER = true);
#import "File";
#import "Math";
#import "stb_truetype";
#import "stb_image_write";
#import,file "module.jai"(STB_TRUETYPE = true);
