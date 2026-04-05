main :: () {
    size_sdf := 32;
    size_bitmap := 256;

    face := hb_face_create_from_file_or_fail("Hack-Regular.ttf", 0);
    assert(face != null);
    upem := hb_face_get_upem(face);
    defer hb_face_destroy(face);

    font := hb_font_create(face);
    defer hb_font_destroy(font);

    glyph_index: hb_codepoint_t;
    success := hb_font_get_nominal_glyph(font, #char "J", *glyph_index);
    assert(xx success);

    draw_funcs := make_draw_funcs();
    defer hb_draw_funcs_destroy(draw_funcs);

    shape, metrics := make_shape(font, glyph_index, size_sdf, size_sdf, draw_funcs, upem, true);
    log("metrics: %", metrics);
    windings := prepare_shape(*shape);

    msdf := generate_msdf(shape, windings, metrics, size_sdf, size_sdf);
    defer array_free(msdf);

    bitmap_sdf := make_bitmap_sdf(msdf, size_sdf);
    bitmap := make_bitmap_render(msdf, size_sdf, size_bitmap);
    defer array_free(bitmap_sdf);
    defer array_free(bitmap);

    stbi_write_png("test1_msdf.png", xx size_sdf, xx size_sdf, 3, bitmap_sdf.data, xx (size_sdf*3));
    stbi_write_png("test1_out.png", xx size_bitmap, xx size_bitmap, 3, bitmap.data, xx (size_bitmap*3));
}

#import "Basic";
#import "String";
#import "File";
#import "HarfBuzz";
#import,file "module.jai"(HARFBUZZ = true);
#import "stb_image_write";
