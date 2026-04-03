symmetrical_trichotomy :: (position: s64, n: s64) -> s64 {
    return cast(s64) (3.0+2.875*cast(float)position/cast(float)(n-1)-1.4375+0.5) - 3;
}

seed_extract_2 :: (seed: *u64) -> s32 {
    v: s32 = cast(s32)(seed.*) & 1;
    seed.* >>= 1;
    return v;
}

seed_extract_3 :: (seed: *u64) -> s32 {
    v: s32 = cast(s32)(seed.* % 3);
    seed.* /= 3;
    return v;
}

init_color :: (seed: *u64) -> Edge_Segment.Color {
    colors: [3]Edge_Segment.Color = .[.CYAN, .MAGENTA, .YELLOW];
    return colors[seed_extract_3(seed)];
}

switch_color :: (color: *Edge_Segment.Color, seed: *u64) {
    shifted := cast(Edge_Segment.Color)(color.* << (1+seed_extract_2(seed)));
    color.* = (shifted|shifted>>3)&.WHITE;
}

switch_color :: (color: *Edge_Segment.Color, seed: *u64, banned: Edge_Segment.Color) {
    combined := color.* & banned;
    if combined == .RED || combined == .GREEN || combined == .BLUE {
        color.* = combined ^ .WHITE;
    } else {
        switch_color(color, seed);
    }
}

calculate_edge_colors :: (contours: []Contour, angle_threshold: float = 3.0) {
    seed: u64;
    cross_threshold := sin(angle_threshold);
    color := init_color(*seed);
    log("init color: %", color);

    corners: [..]s32;
    for * contour: contours {
        if contour.edges.count == 0 continue;
        { // Identify corners
            array_reset_keeping_memory(*corners);
            prev_direction := direction(peek(contour.edges), 1);

            for edge, index: contour.edges {
                if is_corner(normalize(prev_direction), normalize(direction(edge, 0)), cross_threshold) {
                    array_add(*corners, xx index);
                }
                prev_direction = direction(edge, 1);
            }
        }

        log("corners.count: %", corners.count);

        if corners.count == 0 {
            // Smooth contour
            switch_color(*color, *seed);
            for * edge: contour.edges {
                edge.color = color;
            }
        } else if corners.count == 1 {
            colors: [3]Edge_Segment.Color;
            switch_color(*color, *seed);
            colors[0] = color;
            colors[1] = .WHITE;
            switch_color(*color, *seed);
            colors[2] = color;
            corner := corners[0];
            if contour.edges.count >= 3 {
                m := cast(s32)contour.edges.count;
                for i: 0..m - 1 {
                    contour.edges[(corner+i)%m].color = colors[1+symmetrical_trichotomy(i, m)];
                }
            } else if contour.edges.count >= 1 {
                // Less than three edge segments for three colors => edges must be split

                // This part is partially rewritten to fit what I
                // usually in Jai, since we are not using any pointer
                // magic but simple struct passing around, we have to
                // keep track of how many parts we operating instead
                // of the original way of checking NULL.
                parts: [6]Edge_Segment;
                part_count: s64;
                parts[0+3*corner], parts[1+3*corner], parts[2+3*corner] = edge_split(contour.edges[0]);
                if contour.edges.count >= 2 {
                    parts[3-3*corner], parts[4-3*corner], parts[5-3*corner] = edge_split(contour.edges[1]);
                    parts[0].color = colors[0];
                    parts[1].color = colors[0];
                    parts[2].color = colors[1];
                    parts[3].color = colors[1];
                    parts[4].color = colors[2];
                    parts[5].color = colors[2];
                } else {
                    parts[0].color = colors[0];
                    parts[1].color = colors[1];
                    parts[2].color = colors[2];
                }
                // TODO: This should do the same
                array_free(contour.edges);
                contour.edges = array_copy(array_view(parts, part_count));
            }
        } else {
            // Multiple corners
            corner_count := corners.count;
            spline := 0;
            start := corners[0];
            m := contour.edges.count;
            // switch_color(*color, *seed);
            initial_color := color;
            log("initial color: %", initial_color);
            for i: 0..m - 1 {
                index := (start+i)%m;
                if spline+1 < corner_count && corners[spline+1] == index {
                    spline += 1;
                    switch_color(*color, *seed, cast(Edge_Segment.Color)(spline == corner_count-1)*initial_color);
                }

                log("setting edge % to color %", index, color);
                contour.edges[index].color = color;
            }
        }
    }
}
