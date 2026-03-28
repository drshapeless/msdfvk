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
    qa, ab, br: Vector2;
    qa = e.start - origin;
    ab = e.control - e.start;
    // br.x = e.start.x + e.end.x - e.control.x - e.control.x;
    // br.y = e.start.y + e.end.y - e.control.y - e.control.y;
    br = e.start + e.end - e.control - e.control;

    a := dot(br, br);
    b := 3*dot(ab, br);
    c := 2*dot(ab, ab) + dot(qa, br);
    d := dot(qa, ab);

    solution_count, solutions := solve_cubic(a, b, c, d);

    // distance from a
    min_distance := xx nonzero_sign(cross(ab, qa)) * length(qa);
    param := -dot(qa, ab) / dot(ab, ab);
    {
        a := e.end - e.control;
        b := e.end - origin;

        // distance from b
        distance := xx nonzero_sign(cross(a, b))*length(b);
        if abs(distance) < abs(min_distance) {
            min_distance = distance;

            a = origin - e.control;
            b = e.end - e.control;
            param = dot(a, b) / dot(b, b);
        }
    }

    for i: 0..solution_count - 1 {
        t := solutions[i];
        if t > 0 && t < 1 {
            // end_point = p[0]+2*t[i]*ab+t[i]*t[i]*br;
            end_point, a, b: Vector2;
            end_point.x = e.start.x + 2*t*ab.x + t*t*br.x;
            end_point.y = e.start.y + 2*t*ab.y + t*t*br.y;

            a = e.end - e.start;
            b = end_point - origin;
            distance := xx nonzero_sign(cross(a, b))*length(b);
            if abs(distance) <= abs(min_distance) {
                min_distance = distance;
                param = t;
            }
        }
    }

    if param >= 0 && param <= 1 {
        return .{min_distance, 0}, param;
    }

    ab = normalize(ab);
    qa = normalize(qa);
    aa := e.end - e.control;
    aa = normalize(aa);
    bb := e.end - origin;
    bb = normalize(bb);

    if param < 0.5 {
        return .{min_distance, abs(dot(ab, qa))}, param;
    } else {
        return .{min_distance, abs(dot(aa, bb))}, param;
    }
}

// cubic edge signed distance
cubic_dist :: (e: Edge_Segment, origin: Vector2) -> Signed_Distance, param:float {
    qa, ab, br, as: Vector2;
    qa = e.start - origin;
    ab = e.control - e.start;
    // br.x = e.control1.x - e.control.x - ab.x;
    // br.y = e.control1.y - e.control.y - ab.y;
    br = e.control1 - e.control - ab;
    // as.x = (e.end.x - e.control1.x) - (e.control1.x - e.control.x) - br.x;
    // as.y = (e.end.y - e.control1.y) - (e.control1.y - e.control.y) - br.y;
    as = (e.end - e.control1) - (e.control1 - e.control) - br;

    ep_dir := direction(e, 0);

    // distance from a
    min_distance := xx nonzero_sign(cross(ep_dir, qa))*length(qa);
    param := -dot(qa, ep_dir) / dot(ep_dir, ep_dir);
    {
        a := e.end - origin;
        ep_dir = direction(e, 1);
        // distance from b
        distance := xx nonzero_sign(cross(ep_dir, a))*length(a);
        if abs(distance) < abs(min_distance) {
            min_distance = distance;

            a = origin + ep_dir - e.end;
            param = dot(a, ep_dir) / dot(ep_dir, ep_dir);
        }
    }

    SEARCH_STARTS :: 4;
    for i: 0..SEARCH_STARTS - 1 {
        t :float = cast(float)i / cast(float)SEARCH_STARTS;
        step := 0;
        while 1 {
            defer step += 1;
            qpt := point(e, t);
            qpt = qpt - origin;
            d := direction(e, t);
            distance := xx nonzero_sign(cross(d, qpt))*length(qpt);
            if abs(distance) < abs(min_distance) {
                min_distance = distance;
                param = t;
            }
            if step == SEARCH_STARTS break;

            d1, d2: Vector2;
            d1.x = 3*as.x*t*t + 6*br.x*t + 3*ab.x;
            d1.y = 3*as.y*t*t + 6*br.y*t + 3*ab.y;
            d2.x = 6*as.x*t + 6*br.x;
            d2.y = 6*as.y*t + 6*br.y;

            t -= dot(qpt, d1) / (dot(d1, d1) + dot(qpt, d2));
            if t < 0 || t > 1 break;
        }
    }

    if param >= 0 && param <= 1 {
        return .{min_distance, 0}, param;
    }

    d0 := direction(e, 0);
    d1 := direction(e, 1);
    d0 = normalize(d0);
    d1 = normalize(d1);
    qa = normalize(qa);
    a := e.end - origin;
    a = normalize(a);

    if param < 0.5 {
        return .{min_distance, abs(dot(d0, qa))}, param;
    } else {
        return .{min_distance, abs(dot(d1, a))}, param;
    }
}

dist_to_pseudo :: (distance: *Signed_Distance, origin: Vector2, param: float, e: Edge_Segment) {
    if param < 0 {
        dir := direction(e, 0);
        dir  = normalize(dir);
        p   := point(e, 0);
        aq  := origin - p;
        ts  := dot(aq, dir);
        if ts < 0 {
            pseudo_dist := cross(aq, dir);
            if abs(pseudo_dist) <= abs(distance.dist) {
                distance.dist = pseudo_dist;
                distance.d    = 0;
            }
        }
    } else if param > 1 {
        dir := direction(e, 1);
        dir  = normalize(dir);
        p   := point(e, 1);
        bq  := origin - p;
        ts  := dot(bq, dir);
        if ts > 0 {
            pseudo_dist := cross(bq, dir);
            if abs(pseudo_dist) <= abs(distance.dist) {
                distance.dist = pseudo_dist;
                distance.d    = 0;
            }
        }
    }
}

signed_compare :: (a: Signed_Distance, b: Signed_Distance) -> bool {
    return abs(a.dist) < abs(b.dist) || (abs(a.dist) == abs(b.dist) && a.d < b.d);
}

is_corner :: (a: Vector2, b: Vector2, threshold: float) -> bool {
    return dot(a, b) <= 0 || abs(cross(a, b)) > threshold;
}

switch_color :: (color: *Edge_Segment.Color, seed: *u64, banned: Edge_Segment.Color) {
    combined := color.* & banned;
    if combined == .RED || combined == .GREEN || combined == .BLUE {
        color.* = combined ^ .WHITE;
        return;
    }

    if color.* == .BLACK || color.* == .WHITE {
        start :: Edge_Segment.Color.[.CYAN, .MAGENTA, .YELLOW];
        color.* = start[seed.* & 3];
        seed.* /= 3;
        return;
    }

    shifted := color.* << (1+(seed.* & 1));
    color.* = (shifted|shifted>>3)&.WHITE;
    seed.* >>= 1;
}

#import "stb_truetype";
#import "Math";
#import "Basic";
