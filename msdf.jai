// The original code is filled with double, and I don't quite
// understand the reason of using double instead of float in most
// cases

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
    type:  STBTT;
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

cross :: (a: Vector2, b: Vector2) -> float64 {
    return a.x * b.y - a.y * b.x;
}

scale :: (v: Vector2, s: float) -> Vector2 {
    r: Vector2;
    r.x = v.x * s;
    r.y = v.y * s;

    return r;
}

mul_inner :: (a: Vector2, b: Vector2) -> float {
    return b.x * a.x + b.y * a.y;
}

// leng is provided by length in built-in Math module
// norm is provided by normalize in built-in Math module
sub :: (a: Vector2, b: Vector2) -> Vector2 {
    r: Vector2;
    r.x = a.x - b.x;
    r.y = a.y - b.y;
    return r;
}

solve_quadratic :: (a: float64, b: float64, c: float64) -> int, [2]float64 {
    x: [2]float64;
    if abs(a) < 1.0e-14 {
        if abs(b) < 1.0e-14 {
            if c == 0 {
                return -1, x;
            } else {
                return 0, x;
            }
        }

        x[0] = -c / b;
        return 1, x;
    }

    dscr := b * b - 4 * a * c;
    if dscr > 0 {
        dscr = sqrt(dscr);
        x[0] = (-b + dscr) / (2 * a);
        x[1] = (-b - dscr) / (2 * a);
        return 2, x;
    } else if dscr == 0 {
        x[0] = -b / (2 * a);
        return 1, x;
    } else {
        return 0, x;
    }

    return 0, x;
}

solve_cubic_normed :: (a: float64, b: float64, c: float64) -> int, [3]float64 {
    a2 := a * a;
    q  := (a2 - 3 * b) / 9;
    r  := (a * (2 * a2 - 9 * b) + 27 * c) / 54;
    r2 := r * r;
    q3 := q * q * q;
    A: float64;
    B: float64;

    x: [3]float64;

    if r2 < q3 {
        t :float64 = r / sqrt(q3);
        if t < -1 {
            t = -1;
        } else if t > 1 {
            t = 1;
        }
        t = acos(t);
        a /= 3;
        q = -2 * sqrt(q);

        x[0] = q * cos(t / 3) - a;
        x[1] = q * cos((t + 2 * PI64) / 3) - a;
        x[2] = q * cos((t - 2 * PI64) / 3) - a;
        return 3, x;
    } else {
        A = -pow(abs(r) + sqrt(r2 - q3), 1.0 / 3.0);
        if r < 0 {
            A = -A;
        }

        B = ifx A == 0 then 0 else q / A;
        a /= 3;
        x[0] = (A + B) - a;
        x[1] = -0.5 * (A + B) - a;
        x[2] = 0.5 * sqrt(cast(float64)3.0) * (A - B);
        if abs(x[2]) < 1.0e-14 {
            return 2, x;
        } else {
            return 1, x;
        }
    }

    return 0, x;
}

solve_cubic :: (a: float64, b: float64, c: float64, d: float64) -> int, [3]float64 {
    if abs(a) < 1.0e-14 {
        i, result := solve_quadratic(b, c, d);
        x: [3]float64;
        x[0] = result[0];
        x[1] = result[1];
        return i, x;
    } else {
        i, result := solve_cubic_normed(b / a, c / a, d / a);
        return i, result;
    }
}

get_ortho :: (v: Vector2, polarity: bool, allow_zero: bool) -> Vector2 {
    len: float = xx length(v);

    r: Vector2;

    if len == 0 {
        if polarity {
            r.x = 0;
            r.y = xx !allow_zero;
        } else {
            r.x = 0;
            r.y = -cast(float)!allow_zero;
        }
        return r;
    }

    if polarity {
        r.x = -v.y / len;
        r.y = v.x / len;
    } else {
        r.x = v.y / len;
        r.y = -v.x / len;
    }

    return r;
}

// This function is hand typed, may be wrong by typo.
pixel_clash :: (a: Vector3, b: Vector3, threshold: float) -> int {
    // What the hell??
    a_in :int = cast(int)(cast(int)(a.x > 0.5) + cast(int)(a.y > 0.5) + cast(int)(a.z > 0.5) >= 2);
    b_in :int = cast(int)(cast(int)(b.x > 0.5) + cast(int)(b.y > 0.5) + cast(int)(b.z > 0.5) >= 2);
    if a_in != b_in {
        return 0;
    }

    if (a.x > 0.5 && a.y > 0.5 && a.z > 0.5) ||
    (a.x < 0.5 && a.y < 0.5 && a.z < 0.5) ||
    (a.x > 0.5 && a.y > 0.5 && a.z > 0.5) ||
    (a.x < 0.5 && a.y < 0.5 && a.z < 0.5) {
        return 0;
    }

    aa, ab, ba, bb, ac, bc: float;

    if ((a.x > 0.5) != (b.x > 0.5)) && ((a.x < 0.5) != (b.x < 0.5)) {
        aa = a.x;
        ba = b.x;

        if ((a.y > 0.5) != (b.y > 0.5)) && ((a.y < 0.5) != (b.y < 0.5)) {
            ab = a.y;
            bb = b.y;
            ac = a.z;
            bc = b.z;
        } else if ((a.z > 0.5) != (b.z > 0.5)) && ((a.z < 0.5) != (b.z < 0.5)) {
            ab = a.y;
            bb = b.y;
            ac = a.x;
            bc = b.x;
        } else {
            return 0;
        }
    } else if ((a.y > 0.5) != (b.y > 0.5)) && ((a.y < 0.5) != (b.y < 0.5)) &&
    ((a.z > 0.5) != (b.z > 0.5)) && ((a.z < 0.5) != (b.z < 0.5)) {
        aa = a.y;
        ba = b.y;
        ab = a.z;
        bb = b.z;
        ac = a.x;
        bc = b.x;
    } else {
        return 0;
    }

    return cast(int)((abs(aa - ba) >= threshold) && (abs(ab - bb) >= threshold) && (abs(ac - 0.5) >= abs(bc - 0.5)));
}

mix :: (a: Vector2, b: Vector2, weight: float) -> Vector2 {
    r: Vector2;
    r.x = (1.0 - weight) * a.x + weight * b.x;
    r.y = (1.0 - weight) * a.y + weight * b.y;
    return r;
}

linear_direction :: (e: Edge_Segment, param: float) -> Vector2 {
    r: Vector2;
    r.x = e.p[1].x - e.p[0].x;
    r.y = e.p[1].y - e.p[0].y;
    return r;
}

quadratic_direction :: (e: Edge_Segment, param: float) -> Vector2 {
    a := sub(e.p[1], e.p[0]);
    b := sub(e.p[2], e.p[1]);
    return mix(a, b, param);
}

cubic_direction :: (e: Edge_Segment, param: float) -> Vector2 {
    a := sub(e.p[1], e.p[0]);
    b := sub(e.p[2], e.p[1]);
    c := mix(a, b, param);
    a =  sub(e.p[3], e.p[2]);
    d := mix(b, a, param);
    t := mix(c, d, param);

    r: Vector2;
    if t.x == 0 && t.y == 0 {
        if param == 0 {
            r.x = e.p[2].x - e.p[0].x;
            r.y = e.p[2].y - e.p[0].y;
            return r;
        }

        if param == 1 {
            r.x = e.p[3].x - e.p[1].x;
            r.y = e.p[3].y - e.p[1].y;
            return r;
        }
    }

    r.x = t.x;
    r.y = t.y;
    return r;
}

direction :: (e: Edge_Segment, param: float) -> Vector2 {
    if e.type == {
    case .vline;
        return linear_direction(e, param);
    case .vcurve;
        return quadratic_direction(e, param);
    case .vcubic;
        return cubic_direction(e, param);
    }

    assert(false);
    return .{};
}

linear_point :: (e: Edge_Segment, param: float) -> Vector2 {
    return mix(e.p[0], e.p[1], param);
}

quadratic_point :: (e: Edge_Segment, param: float) -> Vector2 {
    a := mix(e.p[0], e.p[1], param);
    b := mix(e.p[1], e.p[2], param);
    return mix(a, b, param);
}

cubic_point :: (e: Edge_Segment, param: float) -> Vector2 {
    p12 := mix(e.p[1], e.p[2], param);
    a   := mix(e.p[0], e.p[1], param);
    b   := mix(a, p12, param);

    c   := mix(e.p[2], e.p[3], param);
    d   := mix(p12, c, param);

    return mix(b, d, param);
}

#import "stb_truetype";
#import "Math";
#import "Basic";
