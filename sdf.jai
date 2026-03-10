// This is a direct copy of stbtt_GetGlyphSDF
generate_glyph_sdf :: (info: *stbtt_fontinfo, scale: float, glyph: s32, padding: s32, onedge_value: u8, pixel_dist_scale: float) -> success:bool, width:s32, height:s32, xoff:s32, yoff:s32, data:[]u8 {
    if scale == 0 return false, 0, 0, 0, 0, {};

    scale_x := scale;
    scale_y := scale;

    ix0, iy0, ix1, iy1: s32;
    width, height: s32;
    data: []u8;

    stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale, scale, 0, 0, *ix0, *iy0, *ix1, *iy1);

    if ix0 == ix1 || iy0 == iy1 {
        return false, 0, 0, 0, 0, {};
    }

    ix0 -= padding;
    iy0 -= padding;
    ix1 += padding;
    iy1 += padding;

    width = ix1 - ix0;
    height = iy1 - iy0;

    scale_y = -scale_y;

    {
        eps: float = 1.0 / 1024;
        eps2 := eps * eps;

        verts: []stbtt_vertex;
        verts.count = xx stbtt_GetGlyphShape(info, glyph, *verts.data);
        defer stbtt_FreeShape(info, verts.data);
        data = NewArray(width * height, u8);
        precompute := NewArray(verts.count, float);
        defer array_free(precompute);

        j := verts.count - 1;
        for i: 0..verts.count - 1 {
            if verts[i].type == xx STBTT.vline {
                x0 := verts[i].x * scale_x;
                y0 := verts[i].y * scale_y;
                x1 := verts[j].x * scale_x;
                y1 := verts[j].y * scale_y;
                dist := sqrt(cast(float)((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)));
                precompute[i] = ifx dist < eps then 0.0 else 1.0 / dist;
            } else if verts[i].type == xx STBTT.vcurve {
                x2 := verts[j].x  * scale_x;
                y2 := verts[j].y  * scale_y;
                x1 := verts[i].cx * scale_x;
                y1 := verts[i].cy * scale_y;
                x0 := verts[i].x  * scale_x;
                y0 := verts[i].y  * scale_y;

                bx := x0 - 2 * x1 + x2;
                by := y0 - 2 * y1 + y2;
                len2 := bx * bx + by * by;
                if len2 >= eps2 {
                    precompute[i] = 1.0 / cast(float) len2;
                } else {
                    precompute[i] = 0.0;
                }
            } else {
                precompute[i] = 0.0;
            }

            j = i;
        }

        for y: iy0..iy1 - 1 {
            for x: ix0..ix1 - 1 {
                val: float;
                min_dist: float = 999999.0;
                sx := cast(float) x + 0.5;
                sy := cast(float) y + 0.5;
                x_gspace := sx / scale_x;
                y_gspace := sy / scale_y;
                winding := compute_crossings_x(x_gspace, y_gspace, verts);

                for i: 0..verts.count - 1 {
                    x0 := verts[i].x * scale_x;
                    y0 := verts[i].y * scale_y;

                    if verts[i].type == xx STBTT.vline && precompute[i] != 0.0 {
                        x1 := verts[i - 1].x * scale_x;
                        y1 := verts[i - 1].y * scale_y;

                        dist, dist2: float;
                        dist2 = (x0 - sx) * (x0 - sx) + (y0 - sy)* (y0 - sy);
                        if dist2 < min_dist * min_dist {
                            min_dist = sqrt(dist2);
                        }

                        dist = abs((x1 - x0) * (y0 - sy) - (y1 - y0) * (x0 - sx)) * precompute[i];
                        assert(i != 0);
                        if dist < min_dist {
                            // check position along line
                            // x' = x0 + t*(x1-x0), y' = y0 + t*(y1-y0)
                            // minimize (x'-sx)*(x'-sx)+(y'-sy)*(y'-sy)
                            dx := x1 - x0;
                            dy := y1 - y0;
                            px := x0 - sx;
                            py := y0 - sy;
                            // minimize (px+t*dx)^2 + (py+t*dy)^2 = px*px + 2*px*dx*t + t^2*dx*dx + py*py + 2*py*dy*t + t^2*dy*dy
                            // derivative: 2*px*dx + 2*py*dy + (2*dx*dx+2*dy*dy)*t, set to 0 and solve
                            t := -(px * dx + py * dy) / (dx * dx + dy * dy);
                            if t >= 0.0 && t <= 1.0 {
                                min_dist = dist;
                            }
                        } else if verts[i].type == xx STBTT.vcurve {
                            x2 := verts[i - 1].x *  scale_x;
                            y2 := verts[i - 1].y *  scale_y;
                            x1 := verts[i    ].cx * scale_x;
                            y1 := verts[i    ].cy * scale_y;
                            box_x0 := min(x0, x1, x2);
                            box_y0 := min(y0, y1, y2);
                            box_x1 := max(x0, x1, x2);
                            box_y1 := max(y0, y1, y2);
                            // coarse culling against bbox to avoid computing cubic unnecessarily
                            if sx > box_x0 - min_dist && sx < box_x1 + min_dist && sy > box_y0 - min_dist && sy < box_y1 + min_dist {
                                num :s32 = 0;
                                ax := x1 - x0;
                                ay := y1 - y0;
                                bx := x0 - 2 * x1 + x2;
                                by := y0 - 2 * y1 + y2;
                                mx := x0 - sx;
                                my := y0 - sy;
                                res: [3]float;
                                // Avoid colliding with it, so it becomes itt
                                px, py, t, itt, dist2: float;
                                a_inv := precompute[i];
                                if a_inv == 0.0 {
                                    // if a_inv is 0, it's 2nd degree
                                    // so use quadratic formula
                                    a := 3.0 * (ax * bx + ay * by);
                                    b := 2.0 * (ax * ax + ay * ay) + (mx * bx + my * by);
                                    c := mx * ax + my * ay;
                                    if abs(a) < eps2 {
                                        // if a is 0, it's linear
                                        if abs(b) >= eps2 {
                                            res[num] = -c / b;
                                            num += 1;
                                        }
                                    } else {
                                        discriminant := b * b - 4 * a * c;
                                        if discriminant < 0 {
                                            num = 0;
                                        } else {
                                            root := sqrt(discriminant);
                                            res[0] = (-b - root) / (2 * a);
                                            res[1] = (-b + root) / (2 * a);
                                            num = 2; // don't bother distinguishing 1-solution case, as code below will still work
                                        }
                                    }
                                } else {
                                    b := 3.0 * (ax * bx + ay * by) * a_inv; // could precompute this as it doesn't depend on sample point
                                    c := (2 * (ax * ax + ay * ay) + (mx * bx + my * by)) * a_inv;
                                    d := (mx * ax + my * ay) * a_inv;
                                    num, res = solve_cubic(b, c, d);
                                }

                                dist2 = (x0 - sx) * (x0 - sx) + (y0 - sy) * (y0 - sy);
                                if dist2 < min_dist * min_dist {
                                    min_dist = sqrt(dist2);
                                }

                                if num >= 1 && res[0] >= 0.0 && res[0] <= 1.0 {
                                    t = res[0];
                                    itt = 1.0 - t;
                                    px = itt * itt * x0 + 2 * t * itt * x1 + t * t * x2;
                                    py = itt * itt * y0 + 2 * t * itt * y1 + t * t * y2;
                                    dist2 = (px - sx) * (px - sx) + (py - sy) * (py - sy);
                                    if dist2 < min_dist * min_dist {
                                        min_dist = sqrt(dist2);
                                    }
                                }

                                // WTF, it is the same as above, except for t = res[1]
                                if num >= 2 && res[1] >= 0.0 && res[1] <= 1.0 {
                                    t = res[1];
                                    itt = 1.0 - t;
                                    px = itt * itt * x0 + 2 * t * itt * x1 + t * t * x2;
                                    py = itt * itt * y0 + 2 * t * itt * y1 + t * t * y2;
                                    dist2 = (px - sx) * (px - sx) + (py - sy) * (py - sy);
                                    if dist2 < min_dist * min_dist {
                                        min_dist = sqrt(dist2);
                                    }
                                }

                                // WTF, again?
                                if num >= 3 && res[2] >= 0.0 && res[2] <= 1.0 {
                                    t = res[2];
                                    itt = 1.0 - t;
                                    px = itt * itt * x0 + 2 * t * itt * x1 + t * t * x2;
                                    py = itt * itt * y0 + 2 * t * itt * y1 + t * t * y2;
                                    dist2 = (px - sx) * (px - sx) + (py - sy) * (py - sy);
                                    if dist2 < min_dist * min_dist {
                                        min_dist = sqrt(dist2);
                                    }
                                }
                            }
                        }
                    }
                }
                if winding == 0 {
                    min_dist = -min_dist; // if outside the shape, value is negative
                    val = onedge_value + pixel_dist_scale * min_dist;
                    if val < 0 {
                        val = 0;
                    } else if val > 255 {
                        val = 255;
                    }
                    data[(y - iy0) * width + (x - ix0)] = xx val;
                }
            }
        }
    }

    return true, width, height, ix0, iy0, data;
}

generate_codepoint_sdf :: (info: *stbtt_fontinfo, scale: float, codepoint: s32, padding: s32, onedge_value: u8, pixel_dist_scale: float) -> success:bool, width:s32, height:s32, xoff:s32, yoff:s32, []u8 {
    glyph := stbtt_FindGlyphIndex(info, codepoint);
    success, width, height, xoff, yoff, data := generate_glyph_sdf(info, scale, glyph, padding, onedge_value, pixel_dist_scale);

    return success, width, height, xoff, yoff, data;
}

#scope_file
compute_crossings_x :: (x: float, y: float, verts: []stbtt_vertex) -> s32 {
    orig := Vector2.{0, 0};
    ray  := Vector2.{1, 0};
    winding :s32 = 0;

    y_frac := fmod_cycling(y, 1.0); // TODO: Does this equal to fmod in C?
    if y < 0 { // This check turns to fmod
        y_frac = y_frac - 1.0;
    }

    if y_frac < 0.01 {
        y += 0.01;
    } else if y_frac > 0.99 {
        y -= 0.01;
    }

    orig.x = x;
    orig.y = y;

    // test a ray from (-infinity,y) to (x,y)
    for i: 0..verts.count - 1 {
        // Don't really understand this part
        if verts[i].type == xx STBTT.vline {
            x0 :float = cast(float) verts[i - 1].x;
            y0 :float = cast(float) verts[i - 1].y;
            x1 :float = cast(float) verts[i    ].x;
            y1 :float = cast(float) verts[i    ].y;
            if y > min(y0, y1) && y < max(y0, y1) && x > min(x0, x1) {
                x_inter := (y - y0) / (y1 - y0) * (x1 - x0) + x0;
                if x_inter < x {
                    winding += xx ifx y0 < y1 then 1 else -1;
                }
            }
        }

        if verts[i].type == xx STBTT.vcurve {
            x0 :float = cast(float) verts[i - 1].x;
            y0 :float = cast(float) verts[i - 1].y;
            x1 :float = cast(float) verts[i    ].cx;
            y1 :float = cast(float) verts[i    ].cy;
            x2 :float = cast(float) verts[i    ].x;
            y2 :float = cast(float) verts[i    ].y;

            ax := min(x0, x1, x2);
            ay := min(y0, y1, y2);
            by := max(y0, y1, y2);
            if y > ay && y < by && x > ax {
                q0 := Vector2.{x0, y0};
                q1 := Vector2.{x1, y1};
                q2 := Vector2.{x2, y2};

                // This reduce the curve into a line, same code as the above
                // TODO: refractor it into a macro?
                if q0 == q1 || q1 == q2 {
                    x0 = cast(float) verts[i - 1].x;
                    y0 = cast(float) verts[i - 1].y;
                    x1 = cast(float) verts[i    ].x;
                    y1 = cast(float) verts[i    ].y;
                    if y > min(y0, y1) && y < max(y0, y1) && x > min(x0, x1) {
                        x_inter := (y - y0) / (y1 - y0) * (x1 - x0) + x0;
                        if x_inter < x {
                            winding += xx ifx y0 < y1 then 1 else -1;
                        }
                    }
                } else {
                    num_hits, hits := ray_intersect_bezier(orig, ray, q0, q1, q2);
                    if num_hits >= 1 {
                        if hits[0].x < 0 {
                            winding += xx ifx hits[0].y < 0 then -1 else 1;
                        }
                    }
                    if num_hits >= 2 {
                        if hits[1].x < 0 {
                            winding += xx ifx hits[1].y < 0 then -1 else 1;
                        }
                    }
                }
            }
        }
    }

    return winding;
}

ray_intersect_bezier :: (orig: Vector2, ray: Vector2, q0: Vector2, q1: Vector2, q2: Vector2) -> hit_count:s32, hits:[2]Vector2 {
    q0perp := cross(ray, q0); // Yes, the order is flipped
    q1perp := cross(ray, q1);
    q2perp := cross(ray, q2);
    roperp := cross(ray, orig);

    a := q0perp - 2*q1perp + q2perp;
    b := q1perp - q0perp;
    c := q0perp - roperp;
    s0, s1: float;

    num_s :s32 = 0;
    hits: [2]Vector2;

    if a != 0.0 {
        discr := b * b - a * c;
        if discr > 0.0 {
            rcpna := -1 / a;
            d := sqrt(discr);
            s0 = (b + d) * rcpna;
            s1 = (b - d) * rcpna;
            if s0 >= 0.0 && s0 <= 1.0 {
                num_s = 1;
            }
            if d > 0.0 && s1 >= 0.0 && s1 <= 1.0 {
                if num_s == 0 s0 = s1;
                num_s += 1;
            }
        }
    } else {
        // 2*b*s + c = 0
        // s = -c / (2*b)
        s0 = c / (-2 * b);
        if s0 >= 0.0 && s0 <= 1.0 {
            num_s = 1;
        }
    }

    if num_s == 0 {
        return 0, hits;
    } else {
        rcp_len2 := 1.0 / (ray.x * ray.x + ray.y * ray.y);
        rayn_x := ray.x * rcp_len2;
        rayn_y := ray.y * rcp_len2;

        q0d :=   q0.x * rayn_x +   q0.y * rayn_y;
        q1d :=   q1.x * rayn_x +   q1.y * rayn_y;
        q2d :=   q2.x * rayn_x +   q2.y * rayn_y;
        rod := orig.x * rayn_x + orig.y * rayn_y;

        q10d := q1d - q0d;
        q20d := q2d - q0d;
        q0rd := q0d - rod;

        hits[0].x = q0rd + s0 * (2.0 - 2.0 * s0) * q10d + s0 * s0 * q20d;
        hits[0].y = a * s0 + b;

        if num_s > 1 {
            hits[1].x = q0rd + s1 * (2.0 - 2.0 * s1) * q10d + s1 * s1 * q20d;
            hits[1].y = a * s1 + b;
            return 2, hits;
        } else {
            return 1, hits;
        }
    }
}

cross :: (a: Vector2, b: Vector2) -> float {
    return a.x * b.y - a.y * b.x;
}

cuberoot :: (x: float) -> float {
    if x < 0 {
        return - pow(-x, 1.0 / 3.0);
    } else {
        return pow(x, 1.0 / 3.0);
    }
}

solve_cubic :: (a: float, b: float, c: float) -> s32, [3]float {
    r: [3] float;

    s  :float = -a / 3.0;
    p  :float = b - a * a / 3.0;
    q  :float = a * (2 * a * a - 9 * b) / 27 + c;
    p3 :float = p * p * p;
    d  :float = q * q + 4 * p3 / 27;
    if d >= 0 {
        z :float = sqrt(d);
        u :float = (-q + z) / 2.0;
        v :float = (-q - z) / 2.0;
        u = cuberoot(u);
        v = cuberoot(v);
        r[0] = s + u + v;
        return 1, r;
    } else {
        u :float = sqrt(-p / 3);
        v :float = acos(-sqrt(-27.0 / p3) * q / 2) / 3; // p3 must be negative, since d is negative
        m :float = cos(v);
        n :float = cos(v - PI / 2.0) * cast(float)1.732050808; // sqrt of 3?
        r[0] = s + u * 2 * m;
        r[1] = s - u * (m + n);
        r[2] = s - u * (m - n);

        return 3, r;
    }
}

#import "Basic";
#import "File";
#import "Math";
#import "stb_truetype";
