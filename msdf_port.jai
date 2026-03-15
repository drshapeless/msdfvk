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

// void generateMSDF(const BitmapSection<float, 3> &output, const Shape &shape, const SDFTransformation &transformation, const MSDFGeneratorConfig &config = MSDFGeneratorConfig());
//
// translation are in em's
//
// There is something called overlap support, we are not dealing with
// that at the moment
generate_msdf :: (info: *stbtt_fontinfo, glyph_index: s32, scale: float, translation: Vector2, range: Vector2) -> []float {

}

Shape :: struct {
    Bounds :: struct {
        left, bottom, right, top: float;
    }


}

Contour :: struct {

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

Edge_Segment :: struct {
    color: Edge_Color;
}

#import "stb_truetype";
#import "Math";
#import "Basic";
