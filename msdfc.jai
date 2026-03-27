// This is almost a line by line port from msdf-c by solenum, https://github.com/solenum/msdf-c
//
// All struct type are converted from snake case with t suffix to
// Capital snake case, e.g. bar_t to Bar
//
// All floating point number are in float32 only. No double precision is used.

#scope_file
INF :: -1.0e24;
RANGE :: 1.0;
EDGE_THRESHOLD :: 0.02;

Signed_Distance :: struct {
    dist: float;
    d:    float;
}

Edge_Segment :: struct {
    Color :: enum {
        BLACK   :: 0;
        RED     :: 1;
        GREEN   :: 2;
        YELLOW  :: 3;
        BLUE    :: 4;
        MAGENTA :: 5;
        CYAN    :: 6;
        WHITE   :: 7;
    }

    color:    Color;
    // The original code uses an array to store all the point without
    // specifying what they are. What a mess.
    // vline:  p[0] is start, p[1] is end
    // vcurve: p[0] is start, p[1] is control, p[2] is end
    // vcubic: p[0] is start, p[1] is control, p[2] is control1, p[3] is end
    start:    Vector2;
    end:      Vector2;
    control:  Vector2;
    control1: Vector2;
    type:     STBTT;
}

median :: (a: float, b: float, c: float) -> float {
    return max(min(a, b), min(max(a, b), c));
}

nonzero_sign :: (n: float) -> s32 {
    return 2 * cast(s32) (n > 0) - 1;
}

cross :: (a: Vector2, b: Vector2) -> float {
    return a.x*b.y - a.y*b.x;
}

scale :: (v: Vector2, s: float) -> Vector2 {
    return .{v.x * s, v.y * s};
}

// mul_inner is the dot product, use dot instead

// leng is provided by length in built-in Math module
// norm is provided by normalize in built-in Math module

// sub, Jai supports vector subtraction by default.
// Use a - b is enough

solve_quadratic :: (a: float, b: float, c: float) -> solution_count:int, solutions:[2]float {
    // This is called x because the original code is x
    x: [2]float;

    if abs(a) < 1.0e-14 {
        if abs(b) < 1.0e-14 {
            if c == 0 {
                return -1, x;
            }
        }
        x[0] = -c/b;
        return 1, x;
    }

    dscr := b*b-4*a*c;
    if dscr > 0 {
        dscr = sqrt(dscr);
        x[0] = (-b+dscr)/(2*a);
        x[1] = (-b-dscr)/(2*a);
        return 2, x;
    } else if dscr == 0 {
        x[0] = -b/(2*a);
        return 1, x;
    } else {
        return 0, x;
    }
}

solve_cubic_normed :: (a: float, b: float, c: float) -> solution_count:int, solutions:[3]float {
    x: [3]float;

    a2 := a*a;
    q  := (a2 - 3*b)/9;
    r  := (a*(2*a2-9*b) + 27*c)/54;
    r2 := r*r;
    q3 := q*q*q;
    A, B: float;
    if r2 < q3 {
        t := r/sqrt(q3);
        if t < -1 t = -1;
        if t >  1 t =  1;
        t = acos(t);
        a /= 3;
        q = -2*sqrt(q);
        x[0] = q*cos(t/3)-a;
        x[1] = q*cos((t+2*PI)/3)-a;
        x[2] = q*cos((t-2*PI)/3)-a;
        return 3, x;
    } else {
        A = -pow(abs(r)+sqrt(r2-q3), 1.0/3.0);
        if r < 0 A = -A;
        B = ifx A == 0 then 0 else q/A;
        a /= 3;
        x[0] = (A+B)-a;
        x[1] = -0.5*(A+B)-a;
        x[2] = 0.5*sqrt(3.0)*(A-B);
        if abs(x[2]) < 1.0e-14
            return 2, x;
        return 1, x;
    }
}

solve_cubic :: (a: float, b: float, c: float, d: float) -> solution_count:int, solutions:[3]float {
    if abs(a) < 1.0e-14 {
        solution_count, solutions := solve_quadratic(b, c, d);
        x: [3]float;
        x[0] = solutions[0];
        x[1] = solutions[1];
        return solution_count, x;
    }
    solution_count, solutions := solve_cubic_normed(b/a, c/a, d/a);
    return solution_count, solutions;
}

getortho :: (v: Vector2, polarity: bool, allow_zero: bool) -> Vector2 {
    r: Vector2;

    len := length(v);
    if len == 0 {
        if polarity {
            r.x = 0;
            r.y = cast(float) (!allow_zero);
        } else {
            r.x = 0;
            r.y = - cast(float) (!allow_zero);
        }
        return r;
    }

    if polarity {
        r.x = -v.y / len;
        r.y =  v.x / len;
    } else {
        r.x =  v.y / len;
        r.y = -v.x / len;
    }

    return r;
}

pixel_clash :: (a: Vector3, b: Vector3, threshold: float) -> bool {
    // I intentionally keep the camal case
    aIn :bool = (cast(int)(a.x > 0.5) + cast(int)(a.y > 0.5) + cast(int)(a.z > 0.5)) >= 2;
    bIn :bool = (cast(int)(b.x > 0.5) + cast(int)(b.y > 0.5) + cast(int)(b.z > 0.5)) >= 2;
    if aIn != bIn return false;

    components_smaller_than :: (v: Vector3, i: float) -> bool {
        return v.x > i && v.y > i && v.z > i;
    }

    components_larger_than  :: (v: Vector3, i: float) -> bool {
        return v.x < i && v.y < i && v.z < i;
    }

    if components_larger_than(a, 0.5) || components_smaller_than(a, 0.5) || components_larger_than(b, 0.5) || components_smaller_than(b, 0.5) {
        return false;
    }

    aa, ab, ba, bb, ac, bc: float;
    if (a.x > 0.5) != (b.x > 0.5) && (a.x < 0.5) != (b.x < 0.5) {
        aa = a.x;
        ba = b.x;
        if (a.y > 0.5) != (b.y > 0.5) && (a.y < 0.5) != (b.y < 0.5) {
            ab = a.y;
            bb = b.y;
            ac = a.z;
            bc = b.z;
        } else if (a.z > 0.5) != (b.z > 0.5) && (a.z < 0.5) != (b.z < 0.5) {
            ab = a.z;
            bb = b.z;
            ac = a.y;
            bc = b.y;
        } else {
            return false;
        }
    } else if (a.y > 0.5) != (b.y > 0.5) && (a.y < 0.5) != (b.y < 0.5) && (a.z > 0.5) != (b.z > 0.5) && (a.z < 0.5) != (b.z < 0.5) {
        aa = a.y;
        ba = b.y;
        ab = a.z;
        bb = b.z;
        ac = a.x;
        bc = b.x;
    } else {
        return false;
    }

    return (abs(aa-ba) >= threshold) && (abs(ab-bb) >= threshold) && (abs(ac-0.5) >= abs(bc-0.5));
}

mix :: (a: Vector2, b: Vector2, weight: float) -> Vector2 {
    r: Vector2;
    r.x = (1-weight)*a.x + weight*b.x;
    r.y = (1-weight)*a.y + weight*b.y;
    return r;
}

linear_direction :: (e: Edge_Segment, param: float) -> Vector2 {
    r: Vector2;
    r.x = e.end.x - e.start.x;
    r.y = e.end.y - e.start.y;

    return r;
}

quadratic_direction :: (e: Edge_Segment, param: float) -> Vector2 {
    a := e.control - e.start;
    b := e.end     - e.control;
    return mix(a, b, param);
}

// TODO: This function is messy
cubic_direction :: (e: Edge_Segment, param: float) -> Vector2 {
    r: Vector2;
    a := e.control  - e.start;
    b := e.control1 - e.control;
    c := mix(a, b, param);

    a  = e.end - e.control1;
    d := mix(b, a, param);
    t := mix(c, d, param);

    // if (!t[0] && !t[1])
    // I made it cleaner to read
    if t.x == 0 && t.y == 0 {
        if param == 0 {
            // r.x = e.control1.x - e.start.x;
            // r.y = e.control1.y - e.start.y;
            r = e.control1 - e.start;
            return r;
        }
        if param == 1 {
            r = e.end - e.control;
            return r;
        }
    }
    r = t;

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
    case;
        assert(false);
    }
    return .{};
}

linear_point :: (e: Edge_Segment, param: float) -> Vector2 {
    return mix(e.start, e.end, param);
}

quadratic_point :: (e: Edge_Segment, param: float) -> Vector2 {
    a := mix(e.start, e.control, param);
    b := mix(e.control, e.end, param);
    return mix(a, b, param);
}

cubic_point :: (e: Edge_Segment, param: float) -> Vector2 {
    p12 := mix(e.control, e.control1, param);
    a   := mix(e.start, e.control, param);
    b   := mix(a, p12, param);
    c   := mix(e.control1, e.end, param);
    d   := mix(p12, c, param);
    return mix(b, d, param);
}

point :: (e: Edge_Segment, param: float) -> Vector2 {
    if e.type == {
    case .vline;
        return linear_point(e, param);
    case .vcurve;
        return quadratic_point(e, param);
    case .vcubic;
        return cubic_point(e, param);
    case;
        assert(false);
    }
    return .{};
}

// linear edge signed distance
linear_dist :: (e: Edge_Segment, origin: Vector2) -> Signed_Distance, param:float {
    aq, ab, eq: Vector2;
    param: float;
    aq = origin - e.start;
    ab = e.end - e.start;
    param = dot(aq, ab) / dot(ab, ab);
    if param > 0.5 {
        eq = e.end - origin;
    } else {
        eq = e.start - origin;
    }

    endpoint_distance := length(eq);
    if param > 0 && param < 1 {
        ab_ortho := getortho(ab, false, false);
        ortho_dist := dot(ab_ortho, aq);
        if abs(ortho_dist) < endpoint_distance {
            return .{ortho_dist, 0}, param;
        }
    }

    ab = normalize(ab);
    eq = normalize(eq);
    dist := xx nonzero_sign(cross(aq, ab)) * endpoint_distance;
    d    := abs(dot(ab, eq));
    return .{dist, d}, param;
}

// quadratic edge signed distance
quadratic_dist :: (e: Edge_Segment, origin: Vector2) -> Signed_Distance, param:float {

}

#import "stb_truetype";
#import "Math";
#import "Basic";
