// Retrowave / Synthwave animated background shader
// Renders a neon perspective grid on the lower half and a retro sun with
// scanlines on the upper half, fully driven by TIME so the animation loops
// seamlessly.  All colours are exposed as uniforms so the background can be
// swapped or tinted at runtime without touching this file.

shader_type canvas_item;

// --- Colour palette ----------------------------------------------------------
uniform vec4 sky_top        : source_color = vec4(0.05, 0.01, 0.12, 1.0);  // deep violet night
uniform vec4 sky_horizon    : source_color = vec4(0.55, 0.05, 0.35, 1.0);  // hot magenta horizon
uniform vec4 sun_outer      : source_color = vec4(1.00, 0.40, 0.10, 1.0);  // warm orange rim
uniform vec4 sun_inner      : source_color = vec4(1.00, 0.85, 0.20, 1.0);  // bright yellow core
uniform vec4 grid_color     : source_color = vec4(0.90, 0.05, 0.80, 1.0);  // neon magenta grid
uniform vec4 grid_glow      : source_color = vec4(0.30, 0.00, 0.60, 1.0);  // purple glow
uniform vec4 ground_dark    : source_color = vec4(0.03, 0.00, 0.10, 1.0);  // near-black ground

// --- Parameters --------------------------------------------------------------
uniform float grid_speed    : hint_range(0.0, 3.0) = 0.5;   // grid scroll speed
uniform float grid_density  : hint_range(1.0, 20.0) = 8.0;  // vertical grid lines count
uniform float grid_line_w   : hint_range(0.005, 0.08) = 0.025; // line half-width in UV
uniform float sun_radius    : hint_range(0.05, 0.5) = 0.22; // sun radius (fraction of height)
uniform float sun_y         : hint_range(0.3, 0.7) = 0.50;  // sun centre Y (0=bottom,1=top)
uniform float scanline_count: hint_range(3.0, 20.0) = 8.0;  // number of dark bands on sun
uniform float horizon_y     : hint_range(0.3, 0.7) = 0.50;  // where sky meets ground

// --- Helpers -----------------------------------------------------------------

// Smooth antialiased step centred at 'edge' with half-width 'w'.
float soft_edge(float val, float edge, float w) {
    return 1.0 - smoothstep(edge - w, edge + w, val);
}

// Draw one horizontal scanline band with given thickness.
float scanline(float y, float band_height, float gap_frac) {
    float t = mod(y, band_height);
    return smoothstep(band_height * gap_frac, band_height * gap_frac * 0.5, t);
}

void fragment() {
    vec2 uv = UV;  // (0,0) = top-left, (1,1) = bottom-right

    // Flip so y=0 is bottom, y=1 is top (more intuitive for geometry).
    float yf = 1.0 - uv.y;
    float xf = uv.x;

    // -------------------------------------------------------------------------
    // SKY (upper half: yf > horizon_y)
    // -------------------------------------------------------------------------

    // Gradient from horizon colour upward to deep-space violet.
    float sky_t = clamp((yf - horizon_y) / (1.0 - horizon_y), 0.0, 1.0);
    vec4 sky_col = mix(sky_horizon, sky_top, sky_t * sky_t);

    // --- Sun disc with scanlines ---
    float cx = 0.5;                  // sun centred horizontally
    float cy = sun_y;                // sun centre in yf space
    vec2  sun_delta = vec2((xf - cx) * 1.0, yf - cy);
    float sun_dist  = length(sun_delta);

    // Radial gradient inside the disc.
    float sun_alpha = smoothstep(sun_radius, sun_radius * 0.5, sun_dist);
    vec4  sun_col   = mix(sun_outer, sun_inner, smoothstep(sun_radius * 0.9, 0.0, sun_dist));

    // Horizontal scanline bands that darken the lower portion of the sun,
    // giving the classic 1980s "striped retro sun" look.  The bands are in
    // screen space so they do NOT move with the sun.
    float band_h = sun_radius / scanline_count;
    float scan   = scanline(yf, band_h, 0.55);
    // Only apply scanlines inside the lower half of the disc.
    float lower  = smoothstep(cy + sun_radius * 0.05, cy - sun_radius * 0.05, yf);
    sun_col     *= mix(1.0, scan * 0.45 + 0.55, lower);

    // Blend sun into sky.
    vec4 upper_col = mix(sky_col, sun_col, sun_alpha);

    // -------------------------------------------------------------------------
    // GROUND (lower half: yf < horizon_y)
    // -------------------------------------------------------------------------

    // How far below the horizon are we?  0 = at horizon, 1 = at screen bottom.
    float ground_t = clamp((horizon_y - yf) / horizon_y, 0.0, 1.0);

    // Dark ground base colour, slightly lighter near the horizon (atmospheric haze).
    vec4 ground_col = mix(sky_horizon * 0.35, ground_dark, ground_t * ground_t);

    // --- Perspective grid ---
    // We use a standard perspective projection: for a point at distance d from
    // the viewer, the projected y shrinks as 1/d.  Here yf=horizon_y is the
    // vanishing point, so d ∝ 1/(horizon_y - yf).
    // To avoid division by zero we clamp the denominator.
    float eps     = 0.001;
    float d       = 1.0 / max(horizon_y - yf, eps);   // perspective depth

    // Perspective UV: vertical lines converge to the vanishing point.
    float pu_x = (xf - 0.5) * d;
    // Vertical (depth) coordinate scrolls over time.
    float pu_y = d - TIME * grid_speed;

    // --- Vertical grid lines ---
    float vline_uv  = pu_x * grid_density;
    float vline_f   = fract(vline_uv + 0.5) - 0.5;   // centred in [-0.5, 0.5]
    // Line thickness narrows with distance (perspective foreshortening).
    float vthick    = grid_line_w * min(d * 0.1, 1.2);
    float vline     = smoothstep(vthick, vthick * 0.4, abs(vline_f));

    // --- Horizontal grid lines ---
    float hline_uv  = pu_y * 0.5;                     // depth-scaled horizontal lines
    float hline_f   = fract(hline_uv + 0.5) - 0.5;
    float hthick    = grid_line_w * min(d * 0.08, 1.0);
    float hline     = smoothstep(hthick, hthick * 0.4, abs(hline_f));

    // Combine both axes.
    float grid_val  = max(vline, hline);

    // Fade the grid: brightest near horizon, darkest at bottom.
    float grid_fade = 1.0 - ground_t * 0.85;
    grid_val       *= grid_fade;

    // Glow: a soft bloom around the grid lines.
    float glow_vl   = smoothstep(vthick * 3.0, vthick * 0.5, abs(vline_f)) * grid_fade * 0.5;
    float glow_hl   = smoothstep(hthick * 3.0, hthick * 0.5, abs(hline_f)) * grid_fade * 0.5;
    float glow_val  = max(glow_vl, glow_hl);

    vec4 lower_col  = mix(ground_col, grid_glow,  glow_val);
    lower_col       = mix(lower_col,  grid_color, grid_val);

    // -------------------------------------------------------------------------
    // Composite: blend sky and ground at the horizon line.
    // -------------------------------------------------------------------------
    float horizon_mask = smoothstep(horizon_y - 0.01, horizon_y + 0.01, yf);
    vec4 final_col = mix(lower_col, upper_col, horizon_mask);

    // Slight vignette at the screen edges to focus attention on the grid.
    float vignette = smoothstep(0.0, 0.35, xf) * smoothstep(1.0, 0.65, xf)
                   * smoothstep(0.0, 0.15, yf) * smoothstep(1.0, 0.85, yf);
    final_col.rgb *= mix(0.55, 1.0, vignette);

    COLOR = final_col;
}
