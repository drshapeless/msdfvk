make_shape :: (font: *stbtt_fontinfo, glyph_index: s32, w: s64, h: s64, autofit := true) -> Shape,  Metrics {
    scale := stbtt_ScaleForMappingEmToPixels(font, xx h);

    ix0, iy0, ix1, iy1: s32;
    xoff := 0.5;
    yoff := 0.5;

    stbtt_GetGlyphBox(font, glyph_index, *ix0, *iy0, *ix1, *iy1);

    if autofit {
        // calculate new height
        newh := h + (h - (iy1 - iy0) * scale) - 4;
        // calculate new scale
        // see 'stbtt_ScaleForMappingEmToPixels' in stb_truetype.h
        p := font.data + font.head + 18;
        units_per_em := p[0] * 256 + p[1];
        scale = newh / units_per_em;

        // make sure we are centered
        xoff = 0;
        yoff = 0;
    }

    left_bearing, advance: s32;
    stbtt_GetGlyphHMetrics(font, glyph_index, *advance, *left_bearing);
    left_bearing = xx (cast(float)left_bearing*scale);

    translate_x := (w/2) - (xx (ix1 - ix0)*scale)/2 - left_bearing;
    translate_y := (h/2) - (xx (iy1 - iy0)*scale)/2 - iy0*scale;

    metrics := Metrics.{
        scale = scale,
        xoff  = xoff,
        yoff  = yoff,
        translate_x = translate_x,
        translate_y = translate_y,
        y_flip = iy0 > iy1
    };

    get_glyph_shape :: (info: *stbtt_fontinfo, glyph_index: s32) -> [] stbtt_vertex {
        vertices: [] stbtt_vertex;
        vertices.count = xx stbtt_GetGlyphShape(info, glyph_index, *vertices.data);

        return vertices;
    }

    verts_to_shape :: (verts: []stbtt_vertex) -> Shape {
        shape: Shape;
        using shape;

        CSCALE :: 64.0; // Where does this number come from?

        initial: Vector2; // Assume the first vertex is vmove, I don't check here
        edges: [..]Edge_Segment;
        for v: verts {
            e := Edge_Segment.{color = .WHITE};
            if cast(STBTT) v.type == {
            case .vmove;
                if edges.count > 0 {
                    new_contour := Contour.{
                        edges = array_copy(edges)
                    };
                    array_add(*contours, new_contour);
                    array_reset_keeping_memory(*edges);
                }
                initial = .{xx v.x, xx v.y};
                initial /= CSCALE;

            case .vline;
                e.type = .vline;
                e.start = initial;
                e.end = .{xx v.x, xx v.y};
                e.end /= CSCALE;

                initial = e.end;
                array_add(*edges, e);

            case .vcurve;
                e.type = .vcurve;
                e.start = initial;
                e.control = .{xx v.cx, xx v.cy};
                e.control /= CSCALE;
                e.end = .{xx v.x, xx v.y};
                e.end /= CSCALE;

                if (e.start == e.control) || (e.control == e.end) {
                    e.control = 0.5*(e.start + e.end);
                }

                initial = e.end;
                array_add(*edges, e);

            case .vcubic;
                e.type = .vcubic;
                e.start = initial;
                e.control = .{xx v.cx, xx v.cy};
                e.control /= CSCALE;
                e.control1 = .{xx v.cx1, xx v.cy1};
                e.control1 /= CSCALE;
                e.end = .{xx v.x, xx v.y};
                e.end /= CSCALE;

                initial = e.end;
                array_add(*edges, e);
            }
        }

        // Here we add the last contour
        if edges.count > 0 {
            new_contour := Contour.{
                edges = array_copy(edges)
            };
            array_add(*contours, new_contour);
        }

        array_free(edges);

        return shape;
    }

    verts := get_glyph_shape(font, glyph_index);
    defer stbtt_FreeShape(font, verts.data);

    shape := verts_to_shape(verts);

    return shape, metrics;
}

#scope_file
#import "stb_truetype";
