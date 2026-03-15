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

Signed_Distance :: struct {
    distance: float;
    dot:      float;
}

edge_signed_distance :: (point: Vector2, edge: Edge) -> Signed_Distance {
    if edge.type == {
    case .LINEAR;
        point_start := point - edge.start; // aq
        start_end := edge.end - edge.start; // ab
        // projection parameter, param
        t := dot(point_start, start_end) / dot(start_end, start_end);

        // This is not efficient as the original code, but clearer
        // Vector2 eq = p[param > .5]-origin;
        eq: Vector2;
        if t > 0.5 {
            eq = end - point;
        } else {
            eq = point - start;
        }

        endpoint_distance := length(eq);
        if t > 0 && t < 1 {
            ortho_distance := dot(orthonormal(start_end), point_start);
            if abs(ortho_distance) < endpoint_distance {
                return .{ortho_distance, 0};
            }
        }
        return Signed_Distance.{non_zero_sign(cross(point_start, start_end)) * endpoint_distance, abs(dot(normalize(start_end), normalize(eq)))};

    case .QUADRATIC;

    }
}

orthonormal :: (v: Vector2) -> Vector2 {
    len := length(v);
    return .{v.y / len, -v.x / len};
}

// Not fast but simple
// return 2*(n > T(0))-1;
non_zero_sign :: (n: float) -> float {
    if n > 0 {
        return 1;
    } else {
        return -1;
    }
}

cross :: (a: Vector2, b: Vector2) -> float {
    return a.x * b.y - a.y * b.x;
}

solve_quadratic :: (a: float, b: float, c: float) -> solution_count:s32, solutions:[2]float {
    solutions: [2]float;
    // a == 0 -> linear equation
    if a == 0 || abs(b) > 1.0e12*abs(a) {
        // a == 0, b == 0 -> no solution
        if b == 0 {
            if c == 0 {
                return -1, solutions;
            }
            return 0, solutions;
        }

        solutions[0] = -c/b;
        return 1, solutions;
    }

    dscr := b*b - 4*a*c;
    if dsrc > 0 {
        dscr = sqrt(dscr);
        solutions[0] = (-b + dscr) / (2*a);
        solutions[1] = (-b - dscr) / (2*a);
        return 2, solutions;
    } else if dscr == 0 {
        solutions[0] = -b/(2*a);
        return 1, solutions;
    } else {
        return 0, solutions;
    }
}

solve_cubic_normalized :: (a: float, b: float, c: float) -> solution_count:s32, solutions:[3]float {
    solutions: [3]float;

    a2 := a * a;
    q  := 1.0/9.0 * (a2 - 3*b);
    r  := 1.0/54.0 * (a * (2*a2 - 9*b) + 27*c);
    r2 := r*r;
    q3 := q*q*q;
    a  *= 1.0/3.0;
    if r2 < q3 {
        t := r / sqrt(q3);
        if t < -1 t = -1;
        if t >  1 t =  1;
        t = acos(t);
        q = -2*sqrt(q);
        solutions[0] = q*cos(1.0/3.0 * t) - a;
        solutions[1] = q*cos(1.0/3.0 * (t + 2*PI)) - a;
        solutions[2] = q*cos(1.0/3.0 * (t - 2*PI)) - a;
        return 3, solutions;
    } else {
        u := ifx r < 0 then 1 else -1;
        u  = u * pow(abs(r) + sqrt(r2 - q3), 1.0/3.0);
        v := ifx u == 0 then 0 else q/u;
        solutions[0] = (u+v)-a;
        if u == v || abs(u - v) < 1.0e-12*abs(u + v) {
            solutions[1] = -0.5*(u+v) - a;
            return 2, solutions;
        }

        return 1, solutions;
    }
}

solve_cubic :: (a: float, b: float, c: float, d: float) -> solution_count:s32, solutions:[3]float {
    count: s32;
    solutions: [3]float;
    if a != 0 {
        bn := b / a;
        if abs(bn) < 1.0e6 { // Above this ratio, the numerical error gets larger than if we treated a as zero
            count, solutions = solve_cubic_normalized(bn, c/a, d/a);
            return count, solutions;
        }
    }
    count=, quadratic_solutions := solve_quadratic(b, c, d);
    solutions[0] = quadratic_solutions[0];
    solutions[1] = quadratic_solutions[1];

    return count, solutions;
}

#import "stb_truetype";
#import "Basic";
#import "Math";
