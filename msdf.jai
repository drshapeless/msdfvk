Metrics :: struct {
    glyph_idx:    int;
    left_bearing: int;
    advance:      int;
    x0:           int;
    x1:           int;
    y0:           int;
    y1:           int;
}

Result :: struct {
    glyph_idx:    int;
    left_bearing: int;
    advance:      int;
    rgb:          [3]float;
    width:        int;
    height:       int;
    y_offset:     int;
}

gen_glyph :: (font: *stbtt_fontinfo, glyph_index: int, border_width: u32, scale: float, range: float) -> Result {
    return Result.{};
}

#scope_file
pixel_at :: (x: int, y: int, w: int, arr: []float) -> Vector3 {
    return Vector3.{
        arr[3 * (y * w + x)],
        arr[(3 * (y * w + x)) + 1],
        arr[(3 * (y * w + x)) + 2]
    };
}

EDGE_THRESHOLD :: 0.02;

Signed_Distance :: struct {
    dist: float64;
    d:    float64;
}

// the possible types:
// STBTT_vmove  = start of a contour
// STBTT_vline  = linear segment
// STBTT_vcurve = quadratic segment
// STBTT_vcubic = cubic segment
Edge_Segment :: struct {
    color: int;
    p:     [4]Vector2;
    type:  int;
}

Edge_Color :: enum {
    BLACK :: 0;
    RED   :: 1;
    GREEN :: 2;
    YELLOW :: 3;
    BLUE  :: 4;
    MAGENTA :: 5;
    CYAN  :: 6;
    WHITE :: 7;
}

median :: (a: float64, b: float64, c: float64) -> float64 {
    return max(min(a, b), min(max(a, b), c));
}

non_zero_sign :: (n: float64) -> int {
    return 2 * cast(int)(n > 0) - 1;
}

#import "stb_truetype";
#import "Math";
#import "Basic";
