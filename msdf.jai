generate_msdf :: (info: *stbtt_fontinfo, glyph_index: s32, scale: float) -> bool, []float, width:s32, height: s32 {
    width, height: s32;
    {
        x0, y0, x1, y1: s32;
        stbtt_GetGlyphBox(info, glyph_index, *x0, *y0, *x1, *y1);

        width = x1 - x0;
        height = y1 - y0;
    }

    log("scale %", scale);

    bitmap := NewArray(width * height, float);

    vertices := get_glyph_shape(info, glyph_index);

    contours: [..] Contour;
    edges: [..] Edge;
    start: Vector2;
    for vertices {
        current_point := Vector2.{xx it.x, xx it.y};

        if it.type == {
        case xx STBTT.vmove;
            if edges.count > 0 {
                contour := Contour.{edges = array_copy(edges)};
                array_add(*contours, contour);
                array_reset_keeping_memory(*edges);
            }
            start = current_point;
        case xx STBTT.vline;
            edge := Edge.{
                type  = .LINEAR,
                start = start,
                end   = current_point
            };
            array_add(*edges, edge);
            start = current_point;

        case xx STBTT.vcurve;
            edge := Edge.{
                type    = .QUADRATIC,
                start   = start,
                end     = .{xx it.x, xx it.y},
                control = current_point
            };
            array_add(*edges, edge);
            start = current_point;

        case;
            assert(false, "No cubic curve is supported at the moment");
        }
    }
    // Add the last
    contour := Contour.{edges = edges};
    array_add(*contours, contour);

    log("%", contours);

    return false, bitmap, width, height;
}

get_glyph_shape :: (info: *stbtt_fontinfo, glyph_index: s32) -> [] stbtt_vertex {
    vertices: [] stbtt_vertex;
    vertices.count = xx stbtt_GetGlyphShape(info, glyph_index, *vertices.data);

    return vertices;
}

#scope_file
Interval :: struct {
    start: s64;
    end:   s64;
}

Edge_Type :: enum {
    ERROR :: 0;
    LINEAR :: 1;
    QUADRATIC :: 2;
}

Edge :: struct {
    type:    Edge_Type;
    start:   Vector2;
    end:     Vector2;
    control: Vector2;
}

Contour :: struct {
    edges: [] Edge;
}

edge_signed_distance :: (point: Vector2, edge: Edge) -> float {

}

#import "stb_truetype";
#import "Basic";
#import "Math";
