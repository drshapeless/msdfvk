// Some words before the code.
//
// I have read through the thesis by Viktor Chlumský over and over
// again. I have convinced that I cannot reproduce the code just by
// the thesis alone because of the lack of related knowledge. I was
// completely lost around the realization part 4.3
//
// Instead of keep banging my head to magically understand the
// thesis. I decided to look into the original C++ code. It is very
// painful to port anything object oriented to a non-OOP language. The
// C++ code is so ugly, and filled with a lot of unnecessary
// encapsulation on non-important data.
//
// Everything in the following code is using float instead of
// double. I don't understand if there is a need for anything to be in
// double at all. I may make another version for this.
//
// For the y-axis, the generated data has a y origin at the
// bottom-left corner. The same as the truetype storage. If anyone
// want to have y origin at the top-left the data can easily inverse
// after generation.
//
// Since the original library supports other formats other than msdf,
// the following code would strip out those irrelevant parts.

// void generateMSDF(const BitmapSection<float, 3> &output, const Shape &shape, const SDFTransformation &transformation, const MSDFGeneratorConfig &config = MSDFGeneratorConfig());
//
// translation are in em's
//
// There is something called overlap support, we are not dealing with
// that at the moment
generate_msdf :: (info: *stbtt_fontinfo, glyph_index: u32, scale: float, translation: Vector2, range: Vector2) -> []float {

}

#scope_file

Shape :: struct {
    Bound :: struct {
        left, bottom, right, top: float;
    }

    contours: [..] Contour;
    bound: Bound;
}

load_glyph :: (info: *stbtt_fontinfo, glyph_index: u32, pixel_height: float) -> Shape {
    ix0, iy0, ix1, iy1: s32;
    stbtt_GetGlyphBox(info, glyph_index, *ix0, *iy0, *ix1, *iy1);

    scale := stbtt_ScaleForMappingEmToPixels(info, pixel_height);

    shape: Shape;

    // y-origin at bottom left
    shape.bound = .{
        left   = cast(float) ix0 * scale,
        bottom = cast(float) iy0 * scale,
        right  = cast(float) ix1 * scale,
        top    = cast(float) iy1 * scale,
    };

    vertices := get_glyph_shape(info, glyph_index);

    edges: [..] Edge;
    start_point: Vector2;
    for vertices {
        current_point := Vector2.{xx it.x, xx it.y};
        if it.type == {
        case xx STBTT.vmove;
            if edges.count > 0 {
                contour := Contour.{edges = array_copy(edges)};
                array_add(*shape.contours, contour);
                array_reset_keeping_memory(*edges);
            }
            start_point = current_point;

        case xx STBTT.vline;
            edge := Edge.{
                type  = .LINEAR,
                start = start_point,
                end   = current_point
            };
            array_add(*edges, edge);
            start_point = current_point;

        case xx STBTT.vcurve;
            edge := Edge.{
                type = .QUADRATIC,
                start   = start_point,
                end     = current_point,
                control = .{xx it.cx, xx it.cy}
            };
            array_add(*edges, edge);
            start_point = current_point;
        }
    }

    return shapel
}

Contour :: struct {
    edges: [] Edge;
}

Edge_Color :: enum {
    BLACK   :: 0;
    RED     :: 1;
    GREEN   :: 2;
    YELLOW  :: 3;
    BLUE    :: 4;
    MAGENTA :: 5;
    CYAN    :: 6;
    WHITE   :: 7;
}

Edge :: struct {
    Edge_Type :: enum {
        ERROR     :: 0;
        LINEAR    :: 1;
        QUADRATIC :: 2;
        CUBIC     :: 3;
    }

    type: Edge_Type;
    color: Edge_Color = .WHITE;

    start:    Point;
    end:      Point;
    control1: Point;
    control2: Point;
}

Point :: Vector2;

get_glyph_shape :: (info: *stbtt_fontinfo, glyph_index: s32) -> [] stbtt_vertex {
    vertices: [] stbtt_vertex;
    vertices.count = xx stbtt_GetGlyphShape(info, glyph_index, *vertices.data);

    return vertices;
}

#import "stb_truetype";
#import "Math";
#import "Basic";
