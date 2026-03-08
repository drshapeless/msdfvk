// The original code is filled with double, and I don't quite
// understand the reason of using double instead of float in most
// cases, so I convert all of them into float for easier calculation

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
    rgb:          []float;
    width:        int;
    height:       int;
    y_offset:     int;
}

gen_glyph :: (font: *stbtt_fontinfo, glyph_index: s32, border_width: u32, scale: float, range: float) -> ok:bool, Result {
    x0, y0, x1, y1: s32;
    xoff, yoff: float;
    stbtt_GetGlyphBox(font, glyph_index, *x0, *y0, *x1, *y1); // TODO: check ok?

    glyph_width := cast(float) (x1 - x0);
    glyph_height := cast(float) (y1 - y0);
    border_width_f := cast(float) border_width;
    w_f := ceil(glyph_width * scale);
    h_f := ceil(glyph_height * scale);
    w_f += 2.0 * border_width_f;
    h_f += 2.0 * border_width_f;
    w := cast(s32) w_f;
    h := cast(s32) h_f;

    bitmap := NewArray(w * h * 3, float);

    glyph_org_x := x0 * scale;
    glyph_org_y := y0 * scale;
    border_width_x := border_width;
    border_width_y := border_width;

    translate_x := glyph_org_x - border_width;
    translate_y := glyph_org_y - border_width;

    verts: *stbtt_vertex;
    num_verts := stbtt_GetGlyphShape(font, glyph_index, *verts);

    contour_count: s32;
    for i: 0..num_verts - 1 {
        if verts[i].type == xx STBTT.vmove {
            contour_count += 1;
        }
    }

    if contour_count == 0 {
        return false, .{};
    }

    Indices :: struct {
        start, end: s32;
    }

    contours := NewArray(contour_count, Indices);
    j := 0;
    for i: 0..num_verts - 1 {
        if verts[i].type == xx STBTT.vmove {
            if i > 0 {
                contours[j].end = i;
                j += 1;
            }

            contours[j].start = i;
        } else if i >= num_verts {
            contours[j].end = i;
        }
    }

    Edge_Point :: struct {
        min_distance: Signed_Distance;
        near_edge: Edge_Segment;
        near_param: float;
    }

    Contour :: struct {
        edges: [] Edge_Segment;
        edge_count: s32;
    }

    initial: Vector2;
    contour_data := NewArray(contour_count, Contour);
    cscale :float = 64.0;
    for i: 0..contour_count - 1 {
        count := contours[i].end - contours[i].start;
        contour_data[i].edges = NewArray(count, Edge_Segment);

        k := 0;
        for j: contours[i].start..contours[i].end - 1 {
            e := *contour_data[i].edges[k];
            v := *verts[j];

            e.type = xx v.type;
            e.color = xx Edge_Color.WHITE;

            if v.type == {
            case xx STBTT.vmove;
                p := Vector2.{v.x / cscale, v.y / cscale};
                initial = p;

            case xx STBTT.vline;
                p := Vector2.{v.x / cscale, v.y / cscale};
                e.p[0] = initial;
                e.p[1] = p;
                initial = p;
                contour_data[i].edge_count += 1;
                k += 1;

            case xx STBTT.vcurve;
                p := Vector2.{v.x / cscale, v.y / cscale};
                c := Vector2.{v.cx / cscale, v.cy / cscale};
                e.p[0] = initial;
                e.p[1] = c;
                e.p[2] = p;
                if (e.p[0].x == e.p[1].x && e.p[0].y == e.p[1].y) || (e.p[1].x == e.p[2].x && e.p[1].y == e.p[2].y) {
                    e.p[1].x = 0.5 * (e.p[0].x + e.p[2].x);
                    e.p[1].y = 0.5 * (e.p[0].y + e.p[2].y);
                }

                initial = p;
                contour_data[i].edge_count += 1;
                k += 1;

            case xx STBTT.vcubic;
                p := Vector2.{v.x / cscale, v.y / cscale};
                c := Vector2.{v.cx / cscale, v.cy / cscale};
                c1 := Vector2.{v.cx1 / cscale, v.cy1 / cscale};
                e.p[0] = initial;
                e.p[1] = c;
                e.p[2] = c1;
                e.p[3] = p;
                initial = p;
                contour_data[i].edge_count += 1;
                k += 1;
            }
        }
    }

    seed :u64 = 0;
    angle_threshold := 3.0;
    cross_threshold := sin(angle_threshold);
    corner_count := 0;
    for i: 0..contour_count - 1 {
        for j: 0..contour_data[i].edge_count {
            corner_count += 1;
        }
    }

    corners := NewArray(corner_count, s32);
    corner_index :s32 = 0;
    for i: 0..contour_count - 1 {
        if contour_data[i].edge_count > 0 {
            prev_dir, dir: Vector2;
            prev_dir = direction(contour_data[i].edges[contour_data[i].edge_count - 1], 1);
            index :s32 = 0;
            for j: 0..contour_data[i].edge_count - 1 {
                e := *contour_data[i].edges[j];
                dir = direction(e, 0);
                dir = normalize(dir);
                prev_dir = normalize(prev_dir);
                if is_corner(prev_dir, dir, cross_threshold) {
                    corners[corner_index] = index;
                    corner_index += 1;
                }
                prev_dir = direction(e, 1);
                index += 1;
            }
        }

        if corner_index == 0 {
            for j: 0..contour_data[i].edge_count - 1 {
                contour_data[i].edges[j].color = .WHITE;
            }
        } else if corner_index == 1 {
            colors: [3]Edge_Color;
            colors[0] = .WHITE;
            colors[1] = .WHITE;
            switch_color(*colors[0], *seed, .BLACK);
            colors[2] = colors[0];
            switch_color(*colors[2], *seed, .BLACK);

            corner := corners[0];
            if contour_data[i].edge_count >= 3 {
                m := contour_data[i].edge_count;
                for j: 0..m - 1 {
                    // WTF is going on here?
                    // contour_data[i].edges[(corner + j) % m].color =
                    // (colors + 1)[(int)(3 + 2.875 * i / (m - 1) - 1.4375 + .5) - 3];

                    idx := cast(int) (3.0 + 2.875 * i / (m - 1) - 1.4375 + 0.5) - 3;
                    idx += 1;
                    contour_data[i].edges[(corner + j) % m].color = colors[idx];
                }
            } else if contour_data[i].edge_count >= 1 {
                parts: [6]Edge_Segment; // It was 7, but the last one is dummy
                used_part_count: s32;
                edge_split(contour_data[i].edges[0], *parts[0 + 3 * corner], *parts[1 + 3 * corner], *parts[2 + 3 * corner]);
                if contour_data[i].edge_count >= 2 {
                    edge_split(contour_data[i].edges[1], *parts[3 - 3 * corner], *parts[4 - 3 * corner], *parts[5 - 3 * corner]);
                    parts[0].color = colors[0];
                    parts[1].color = colors[0];
                    parts[2].color = colors[1];
                    parts[3].color = colors[1];
                    parts[4].color = colors[2];
                    parts[5].color = colors[2];
                    used_part_count = 6;
                } else {
                    parts[0].color = colors[0];
                    parts[1].color = colors[1];
                    parts[2].color = colors[2];
                    used_part_count = 3;
                }

                // TODO: I am not freeing this thing

                contour_data[i].edges = NewArray(used_part_count, Edge_Segment);
                contour_data[i].edge_count = used_part_count;
                // TODO: Why would you separate index and j, they are the same thing
                //
                // The original for loop is like this, what a pain in the ass
                // for (int j = 0; parts[j]; ++j)
                //
                // Hopefully this would work
                for * contour_data[i].edges {
                    it.* = parts[it_index];
                }
            }
        } else {
            spline: s32;
            start := corners[0];
            m := contour_data[i].edge_count;
            color := Edge_Color.WHITE;
            switch_color(*color, *seed, .BLACK);
            initial_color := color;
            for j: 0..m - 1 {
                index := (start + j) % m;
                if spline + 1 < corner_count && corners[spline + 1] == index {
                    spline += 1;

                    s :Edge_Color = xx (cast(int) (spline == corner_count - 1) * cast(int) initial_color);
                    switch_color(*color, *seed, s);
                }
                contour_data[i].edges[index].color = color;
            }
        }
    }

    // Not freeing

    // normalize shape
    for i: 0..contour_count - 1 {
        if contour_data[i].edge_count == 1 {
            parts: [3]Edge_Segment;
            edge_split(contour_data[i].edges[0], *parts[0], *parts[1], *parts[2]);

            contour_data[i].edges = NewArray(3, Edge_Segment);
            contour_data[i].edge_count = 3;
            for j: 0..3 - 1 {
                contour_data[i].edges[j] = parts[j];
            }
        }
    }

    // calculate windings
    windings := NewArray(contour_count, s32);
    for i: 0..contour_count - 1 {
        edge_count := contour_data[i].edge_count;
        if edge_count == 0 {
            windings[i] = 0;
            continue;
        }

        total: float;
        if edge_count == 1 {
            a, b, c: Vector2;
            a = point(contour_data[i].edges[0], 0);
            b = point(contour_data[i].edges[0], 1.0 / 3.0);
            c = point(contour_data[i].edges[0], 2.0 / 3.0);
            total += shoelace(a, b);
            total += shoelace(b, c);
            total += shoelace(c, a);
        } else if edge_count == 2 {
            a, b, c, d: Vector2;
            a = point(contour_data[i].edges[0], 0);
            b = point(contour_data[i].edges[0], 0.5);
            c = point(contour_data[i].edges[1], 0);
            d = point(contour_data[i].edges[1], 0.5);
            total += shoelace(a, b);
            total += shoelace(b, c);
            total += shoelace(c, d);
            total += shoelace(d, a);
        } else {
            prev: Vector2;
            prev = point(contour_data[i].edges[edge_count - 1], 0);
            for j: 0..edge_count - 1 {
                cur := point(contour_data[i].edges[j], 0);
                total += shoelace(prev, cur);
                prev = cur;
            }
        }

        windings[i] = (cast(s32) (0 < total) - cast(s32) (total < 0)); // sign
    }

    Multi_Distance :: struct {
        r, g, b: float = INF;
        med: float = INF;
    }
    contour_sd := NewArray(contour_count, Multi_Distance);

    inv_range := 1.0 / range;

    // Here should be the part that can be highly parallel
    for y: 0..h - 1 {
        row := ifx y0 > y1 then y else h - y - 1;
        for x: 0..w - 1 {
            a64 :float = 64.0;
            p := Vector2.{
                (translate_x + x + xoff) / (scale * a64),
                (translate_y + y + yoff) / (scale * a64),
            };

            sr, sg, sb: Edge_Point;

            // ??? the signess is a bit weird here
            d := abs(INF);
            neg_dist := -INF;
            pos_dist := INF;
            winding: s32;

            // calculate distance to contours from current point (and
            // if its inside or outside of the shape?)
            for j: 0..contour_count - 1 {
                r, g, b: Edge_Point;

                for k: 0..contour_data[j].edge_count - 1 {
                    e := contour_data[j].edges[k];
                    param: float;
                    distance: Signed_Distance;

                    if e.type == {
                    case xx STBTT.vline;
                        distance, param = linear_dist(e, p);
                    case xx STBTT.vcurve;
                        distance, param = quadratic_dist(e, p);
                    case xx STBTT.vcubic;
                        distance, param = cubic_dist(e, p);
                    }

                    if e.color & .RED && signed_compare(distance, r.min_distance) {
                        r.min_distance = distance;
                        r.near_edge = e;
                        r.near_param = param;
                    }

                    if e.color & .GREEN && signed_compare(distance, g.min_distance) {
                        g.min_distance = distance;
                        g.near_edge = e;
                        g.near_param = param;
                    }

                    if e.color & .BLUE && signed_compare(distance, b.min_distance) {
                        b.min_distance = distance;
                        b.near_edge = e;
                        b.near_param = param;
                    }
                }

                if signed_compare(r.min_distance, sr.min_distance) {
                    sr = r;
                }
                if signed_compare(g.min_distance, sg.min_distance) {
                    sg = g;
                }
                if signed_compare(b.min_distance, sb.min_distance) {
                    sb = b;
                }

                med_min_dist := abs(median(r.min_distance.dist, g.min_distance.dist, b.min_distance.dist));

                if med_min_dist < d {
                    d = med_min_dist;
                    winding = -windings[j];
                }

                // Since I don't use pointer the store Edge_Segment,
                // what I check the near_param instead, but I am not
                // sure whether the near_param would be zero TODO:
                // check if the near_param can equal to zero if
                // near_edge is set.

                dist_to_pseudo(*r.min_distance, p, r.near_param, r.near_edge);

                dist_to_pseudo(*g.min_distance, p, g.near_param, g.near_edge);

                dist_to_pseudo(*b.min_distance, p, b.near_param, b.near_edge);


                med_min_dist = median(r.min_distance.dist, g.min_distance.dist, b.min_distance.dist);

                contour_sd[j].r = r.min_distance.dist;
                contour_sd[j].g = g.min_distance.dist;
                contour_sd[j].b = b.min_distance.dist;
                contour_sd[j].med = med_min_dist;

                if windings[j] > 0 && med_min_dist >= 0 && abs(med_min_dist) < abs(pos_dist) {
                    pos_dist = med_min_dist;
                }
                if windings[j] < 0 && med_min_dist <= 0 && abs(med_min_dist) < abs(neg_dist) {
                    neg_dist = med_min_dist;
                }
            }

            dist_to_pseudo(*sr.min_distance, p, sr.near_param, sr.near_edge);
            dist_to_pseudo(*sg.min_distance, p, sg.near_param, sg.near_edge);
            dist_to_pseudo(*sb.min_distance, p, sb.near_param, sb.near_edge);


            msd: Multi_Distance;
            if pos_dist >= 0 && abs(pos_dist) <= abs(neg_dist) {
                msd.med = INF;
                winding = 1;
                for i: 0..contour_count - 1 {
                    if windings[i] > 0 && contour_sd[i].med > msd.med && abs(contour_sd[i].med) < abs(neg_dist) {
                        msd = contour_sd[i];
                    }
                }
            } else if neg_dist <= 0 && abs(neg_dist) <= abs(pos_dist) {
                msd.med = -INF;
                winding = -1;
                for i: 0..contour_count - 1 {
                    if windings[i] < 0 && contour_sd[i].med < msd.med && abs(contour_sd[i].med) < abs(pos_dist) {
                        msd = contour_sd[i];
                    }
                }
            }

            for i: 0..contour_count - 1 {
                if windings[i] != winding && abs(contour_sd[i].med) < abs(msd.med) {
                    msd = contour_sd[i];
                }
            }

            if median(sr.min_distance.dist, sg.min_distance.dist, sb.min_distance.dist) == msd.med {
                msd.r = sr.min_distance.dist;
                msd.g = sg.min_distance.dist;
                msd.b = sb.min_distance.dist;
            }

            index := 3 * ((row * w) + x);
            mr := msd.r * inv_range + 0.5;
            mg := msd.g * inv_range + 0.5;
            mb := msd.b * inv_range + 0.5;
            bitmap[index + 0] = mr;
            bitmap[index + 1] = mg;
            bitmap[index + 2] = mb;
        }
    }

    Clash :: struct {
        x, y: s32;
    }

    clashes := NewArray(w * h, Clash);
    cindex := 0;

    tx :float = EDGE_THRESHOLD / (scale * range);
    ty :float = EDGE_THRESHOLD / (scale * range);

    for y: 0..h - 1 {
        for x: 0..w - 1 {
            if (x > 0 && pixel_clash(pixel_at(x, y, w, bitmap),
                                     pixel_at(max(x - 1, 0), y, w, bitmap), tx)) ||
                (x < w - 1 && pixel_clash(pixel_at(x, y, w, bitmap),
                                          pixel_at(min(x + 1, w - 1), y, w, bitmap), tx)) ||
                (y > 0 && pixel_clash(pixel_at(x, y, w, bitmap),
                                      pixel_at(x, max(y - 1, 0), w, bitmap), ty)) ||
                (y < h - 1 && pixel_clash(pixel_at(x, y, w, bitmap),
                                          pixel_at(x, min(y + 1, h - 1), w, bitmap), ty))
                {
                    clashes[cindex].x = x;
                    clashes[cindex].y = y;
                    cindex += 1;
            }
        }
    }

    for i: 0..cindex - 1 {
        index := 3 * ((clashes[i].y * w) + clashes[i].x);
        med := median(bitmap[index], bitmap[index + 1], bitmap[index + 2]);
        bitmap[index + 0]= med;
        bitmap[index + 1]= med;
        bitmap[index + 2]= med;
    }

    result := Result.{
        glyph_idx = glyph_index,
        rgb = bitmap,
        width = w,
        height = h,
        y_offset = xx translate_y
    };

    return true, result;
}

#scope_file
pixel_at :: (x: int, y: int, w: int, arr: []float) -> Vector3 {
    return Vector3.{
        arr[3 * (y * w + x)],
        arr[(3 * (y * w + x)) + 1],
        arr[(3 * (y * w + x)) + 2]
    };
}

INF :float : -1.0e-14;
EDGE_THRESHOLD :: 0.02;

Signed_Distance :: struct {
    dist: float = INF;
    d:    float = 1;
}

// the possible types:
// STBTT_vmove  = start of a contour
// STBTT_vline  = linear segment
// STBTT_vcurve = quadratic segment
// STBTT_vcubic = cubic segment
Edge_Segment :: struct {
    color: Edge_Color;
    p:     [4]Vector2;
    type:  STBTT;
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

median :: (a: float, b: float, c: float) -> float {
    return max(min(a, b), min(max(a, b), c));
}

non_zero_sign :: (n: float) -> int {
    return 2 * cast(int)(n > 0) - 1;
}

cross :: (a: Vector2, b: Vector2) -> float {
    return a.x * b.y - a.y * b.x;
}

scale :: (v: Vector2, s: float) -> Vector2 {
    r: Vector2;
    r.x = v.x * s;
    r.y = v.y * s;

    return r;
}

// mul_inner is the dot product, use dot instead

// leng is provided by length in built-in Math module
// norm is provided by normalize in built-in Math module

// sub, Jai supports vector subtraction by default.
// Use a - b is enough

solve_quadratic :: (a: float, b: float, c: float) -> int, [2]float {
    x: [2]float;
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

solve_cubic_normed :: (a: float, b: float, c: float) -> int, [3]float {
    a2 := a * a;
    q  := (a2 - 3 * b) / 9;
    r  := (a * (2 * a2 - 9 * b) + 27 * c) / 54;
    r2 := r * r;
    q3 := q * q * q;
    A: float;
    B: float;

    x: [3]float;

    if r2 < q3 {
        t :float = r / sqrt(q3);
        if t < -1 {
            t = -1;
        } else if t > 1 {
            t = 1;
        }
        t = acos(t);
        a /= 3;
        q = -2 * sqrt(q);

        x[0] = q * cos(t / 3) - a;
        x[1] = q * cos((t + 2 * PI) / 3) - a;
        x[2] = q * cos((t - 2 * PI) / 3) - a;
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
        x[2] = 0.5 * sqrt(cast(float)3.0) * (A - B);
        if abs(x[2]) < 1.0e-14 {
            return 2, x;
        } else {
            return 1, x;
        }
    }

    return 0, x;
}

solve_cubic :: (a: float, b: float, c: float, d: float) -> int, [3]float {
    if abs(a) < 1.0e-14 {
        i, result := solve_quadratic(b, c, d);
        x: [3]float;
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
    a := e.p[1] - e.p[0];
    b := e.p[2] - e.p[1];
    return mix(a, b, param);
}

cubic_direction :: (e: Edge_Segment, param: float) -> Vector2 {
    a := e.p[1] - e.p[0];
    b := e.p[2] - e.p[1];
    c := mix(a, b, param);
    a =  e.p[3] - e.p[2];
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

point :: (e: Edge_Segment, param: float) -> Vector2 {
    if e.type == {
    case .vline;
        return linear_point(e, param);
    case .vcurve;
        return quadratic_point(e, param);
    case .vcubic;
        return cubic_point(e, param);
    }

    assert(false);
    return .{};
}

linear_dist :: (e: Edge_Segment, origin: Vector2) -> Signed_Distance, param:float {
    aq := origin - e.p[0];
    ab := e.p[1] - e.p[0];
    param := dot(aq, ab) / dot(ab, ab);
    // This is the original C
    // msdf_v2Sub(eq, e->p[*param > .5], origin);
    // I can simply cast the comparison, but I think using ifx is clearer.
    eq := e.p[ifx param > 0.5 then 1 else 0] - origin;

    endpoint_distance := length(eq);
    if param > 0 && param < 1 {
        ab_ortho := get_ortho(ab, false, false);
        ortho_dist := dot(ab_ortho, aq);
        if abs(ortho_dist) < endpoint_distance {
            return .{dist = ortho_dist, d = 0}, param;
        }
    }

    ab = normalize(ab);
    eq = normalize(eq);

    dist := non_zero_sign(cross(aq, ab)) * endpoint_distance;
    d    := abs(dot(ab, eq));
    return .{dist = dist, d = d}, param;
}

quadratic_dist :: (e: Edge_Segment, origin: Vector2) -> Signed_Distance, param:float {
    // This is the prime example of why I don't like short name, and
    // duplicated names in different scopes of different type. It just
    // adds so many confusions.
    // TODO: Fix the variable naming
    qa := e.p[0] - origin;
    ab := e.p[1] - e.p[0];
    br := Vector2.{
        x = e.p[0].x + e.p[2].x - e.p[1].x - e.p[1].x,
        y = e.p[0].y + e.p[2].y - e.p[1].y - e.p[1].y,
    };

    a := dot(br, br);
    b := 3 * dot(ab, br);
    c := 2 * dot(ab, ab) + dot(qa, br);
    d := dot(qa, ab);
    solutions, t := solve_cubic(a, b, c, d);

    min_distance := non_zero_sign(cross(ab, qa)) * length(qa);
    param := - dot(qa, ab) / dot(ab, ab);
    {
        a := e.p[2] - e.p[1];
        b := e.p[2] - origin;

        distance := non_zero_sign(cross(a, b)) * length(b);
        if abs(distance) < abs(min_distance) {
            min_distance = distance;

            a := origin - e.p[1];
            b := e.p[2] - e.p[1];
            param = dot(a, b) / dot(b, b);
        }
    }

    for i: 0..solutions - 1 {
        if t[i] > 0 && t[i] < 1 {
            end_point := Vector2.{
                x = e.p[0].x + 2 * t[i] * ab.x + t[i] * t[i] * br.x,
                y = e.p[0].x + 2 * t[i] * ab.y + t[i] * t[i] * br.y,
            };

            a := e.p[2] - e.p[0];
            b := end_point - origin;
            distance := non_zero_sign(cross(a, b)) * length(b);
            if abs(distance) <= abs(min_distance){
                min_distance = distance;
                param = t[i];
            }
        }
    }

    if param >= 0 && param <= 1 {
        return .{dist = min_distance, d = 0}, param;
    }

    ab = normalize(ab);
    qa = normalize(qa);
    aa := e.p[2] - e.p[1];
    aa = normalize(aa);
    bb := e.p[2] - origin;
    bb = normalize(bb);

    if param < 0.5 {
        return .{min_distance, abs(dot(ab, qa))}, param;
    } else {
        return .{min_distance, abs(dot(aa, bb))}, param;
    }
}

cubic_dist :: (e: Edge_Segment, origin: Vector2) -> Signed_Distance, param:float {
    // Another god damn disaster, typo may be here
    qa := e.p[0] - origin;
    ab := e.p[1] - e.p[0];
    br := Vector2.{
        e.p[2].x - e.p[1].x - ab.x,
        e.p[2].y - e.p[1].y - ab.y,
    };
    as := Vector2.{
        (e.p[3].x - e.p[2].x) - (e.p[2].x - e.p[1].x) - br.x,
        (e.p[3].y - e.p[2].y) - (e.p[2].y - e.p[1].y) - br.y,
    };

    ep_dir := direction(e, 0);

    // distance from a
    min_distance := non_zero_sign(cross(ep_dir, qa)) * length(qa);
    param := - dot(qa, ep_dir) / dot(ep_dir, ep_dir);
    {
        a := e.p[3] - origin;
        ep_dir = direction(e, 1);
        // distance from b
        distance := non_zero_sign(cross(ep_dir, a)) * length(a);
        if abs(distance) < abs(min_distance) {
            min_distance = distance;

            a.x = origin.x + ep_dir.x - e.p[3].x;
            a.y = origin.y + ep_dir.y - e.p[3].y;
            param = dot(a, ep_dir) / dot(ep_dir, ep_dir);
        }
    }

    search_starts :: 4;
    // Yes, including 4
    for i: 0..search_starts {
        t := cast(float) i / cast(float) search_starts;

        step := 0;
        while true {
            qpt := point(e, t);
            qpt = qpt - origin;
            d := direction(e, t);
            distance := non_zero_sign(cross(d, qpt)) * length(qpt);
            if abs(distance) < abs(min_distance) {
                min_distance = distance;
                param = t;
            }

            if step == search_starts {
                break;
            }

            d1 := Vector2.{
                3 * as.x * t * t + 6 * br.x * t + 3 * ab.x,
                3 * as.y * t * t + 6 * br.y * t + 3 * ab.y,
            };
            d2 := Vector2.{
                6 * as.x * t + 6 * br.x,
                6 * as.y * t + 6 * br.y,
            };

            t -= dot(qpt, d1) / (dot(d1, d1) + dot(qpt, d2));

            if t < 0 || t > 1 {
                break;
            }

            step += 1;
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
    a := e.p[3] - origin;
    a = normalize(a);

    if param < 0.5 {
        return .{min_distance, abs(dot(d0, qa))}, param;
    } else {
        return .{min_distance, abs(dot(d1, a))}, param;
    }
}

// Is this a cursed function, why it may not change a thing?
dist_to_pseudo :: (distance: *Signed_Distance, origin: Vector2, param: float, e: Edge_Segment) {
    if param < 0 {
        dir := direction(e, 0);
        dir = normalize(dir);
        aq := origin; // What is the point of this?
        p := point(e, 0);
        aq = origin - p;
        ts := dot(aq, dir);
        if ts < 0 {
            pseudo_dist := cross(aq, dir);
            if abs(pseudo_dist) <= abs(distance.dist) {
                distance.dist = pseudo_dist;
                distance.d = 0;
            }
        }
    } else if param > 1 {
        dir := direction(e, 1);
        dir = normalize(dir);
        bq := origin; // Also, what is the point?
        p := point(e, 1);
        bq = origin - p;
        ts := dot(bq, dir);
        if ts > 0 {
            pseudo_dist := cross(bq, dir);
            if abs(pseudo_dist) <= abs(distance.dist) {
                distance.dist = pseudo_dist;
                distance.d = 0;
            }
        }
    }
}

signed_compare :: (a: Signed_Distance, b: Signed_Distance) -> bool {
    return abs(a.dist) < abs(b.dist) || abs(a.dist) == abs(b.dist) && a.d < b.d;
}

is_corner :: (a: Vector2, b: Vector2, threshold: float) -> bool {
    return dot(a, b) <= 0 || abs(cross(a, b)) > threshold;
}

// What? Bitwise operation all the way?
switch_color :: (color: *Edge_Color, seed: *u64, banned: Edge_Color) {
    combined := color.* & banned;

    if combined == .RED || combined == .GREEN || combined == .BLUE {
        color.* = combined ^ .WHITE;
        return;
    }

    if color.* == .BLACK || color.* == .WHITE {
        start :[3]Edge_Color : .[.CYAN, .MAGENTA, .YELLOW];
        color.* = start[seed.* & 3];
        seed.* /= 3;
        return;
    }

    shifted := color.* << (1 + (seed.* & 1));
    color.* = (shifted | shifted >> 3) & .WHITE;
    seed.* >>= 1;
}

// e should not be taken as a pointer
linear_split :: (e: Edge_Segment, p1: *Edge_Segment, p2: *Edge_Segment, p3: *Edge_Segment) {
    p := point(e, 1.0 / 3.0);

    // We don't have to use memcpy all the way
    p1.p[0] = e.p[0];
    p1.p[1] = p;
    p1.color = e.color;

    p = point(e, 1.0 / 3.0);
    p2.p[0] = p;
    p = point(e, 2.0 / 3.0);
    p2.p[1] = p;
    p2.color = e.color;

    p = point(e, 2.0 / 3.0);
    p3.p[0] = p;
    p = point(e, 2.0 / 3.0);
    p3.p[1] = e.p[1];
    p3.color = e.color;
}

quadratic_split :: (e: Edge_Segment, p1: *Edge_Segment, p2: *Edge_Segment, p3: *Edge_Segment) {
    p, a, b: Vector2;

    p1.p[0] = e.p[0];
    p = mix(e.p[0], e.p[1], 1.0 / 3.0);
    p1.p[1] = p;
    p = point(e, 1.0 / 3.0);
    p1.p[2] = p;
    p1.color = e.color;

    p = point(e, 1.0 / 3.0);
    p2.p[0] = p;
    a = mix(e.p[0], e.p[1], 5.0 / 9.0);
    b = mix(e.p[1], e.p[2], 4.0 / 9.0);
    p = mix(a, b, 0.5);
    p2.p[1] = p;
    p = point(e, 2.0 / 3.0);
    p2.p[2] = p;
    p2.color = e.color;

    p = point(e, 2.0 / 3.0);
    p3.p[0] = p;
    p = mix(e.p[1], e.p[2], 2.0 / 3.0);
    p3.p[1] = p;
    p3.p[2] = e.p[2];
    p3.color = e.color;
}

cubic_split :: (e: Edge_Segment, p1: *Edge_Segment, p2: *Edge_Segment, p3: *Edge_Segment) {
    p, a, b, c, d: Vector2;

    p1.p[0] = e.p[0]; // p1 0
    if e.p[0] == e.p[1] {
        p1.p[1] = e.p[0]; // ? p1 1
    } else {
        p = mix(e.p[0], e.p[1], 1.0 / 3.0);
        p1.p[1] = p; // ? p1 1
    }

    a = mix(e.p[0], e.p[1], 1.0 / 3.0);
    b = mix(e.p[1], e.p[2], 1.0 / 3.0);
    p - mix(a, b, 1.0 / 3.0);
    p1.p[2] = p; // p1 2
    p = point(e, 1.0 / 3.0);
    p1.p[3] = p; // p1 3
    p1.color = e.color;

    p = point(e, 1.0 / 3.0); // TODO: What? duplicated?
    p2.p[0] = p; // p2 0
    a = mix(e.p[0], e.p[1], 1.0 / 3.0);
    b = mix(e.p[1], e.p[2], 1.0 / 3.0);
    c = mix(a, b, 1.0 / 3.0);
    a = mix(e.p[1], e.p[2], 1.0 / 3.0);
    b = mix(e.p[2], e.p[3], 1.0 / 3.0);
    d = mix(a, b, 1.0 / 3.0);
    p = mix(c, d, 2.0 / 3.0);
    p2.p[1] = p; // p2 1
    a = mix(e.p[0], e.p[1], 2.0 / 3.0);
    b = mix(e.p[1], e.p[2], 2.0 / 3.0);
    c = mix(a, b, 2.0 / 3.0);
    a = mix(e.p[1], e.p[2], 2.0 / 3.0);
    b = mix(e.p[2], e.p[3], 2.0 / 3.0);
    d = mix(a, b, 2.0 / 3.0);
    p = mix(c, d, 1.0 / 3.0);
    p2.p[2] = p; // p2 2
    p = point(e, 2.0 / 3.0);
    p2.p[3] = p; // p2 3
    p2.color = e.color;

    p = point(e, 2.0 / 3.0);
    p3.p[0] = p; // p3 0

    a = mix(e.p[1], e.p[2], 2.0 / 3.0);
    b = mix(e.p[2], e.p[3], 2.0 / 3.0);
    p = mix(a, b, 2.0 / 3.0);
    p3.p[1] = p; // p3 1

    if e.p[2] == e.p[3] {
        p3.p[2] = e.p[3]; // ? p3 2
    } else {
        p = mix(e.p[2], e.p[3], 2.0 / 3.0);
        p3.p[2] = p; // ? p3 2
    }

    p3.p[3] = e.p[3]; // p3 3
}

edge_split :: (e: Edge_Segment, p1: *Edge_Segment, p2: *Edge_Segment, p3: *Edge_Segment) {
    if e.type == {
    case .vline;
        linear_split(e, p1, p2, p3);
    case .vcurve;
        quadratic_split(e, p1, p2, p3);
    case .vcubic;
        cubic_split(e, p1, p2, p3);
    }
}

shoelace :: (a: Vector2, b: Vector2) -> float {
    return (b.x - a.x) * (a.y + b.y);
}

#import "stb_truetype";
#import "Math";
#import "Basic";
