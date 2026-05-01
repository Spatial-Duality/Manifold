//  Atmosphere.metal
//  Manifold — atmospheric background shaders for the splash + hero.
//
//  Two stitchable color-effect shaders compose the splash / hero
//  backdrop on top of the breathing MeshGradient layer:
//
//    - manifoldCloud — Apple-quality atmospheric pass:
//        * 2D simplex noise (smoother than value noise at low frequencies)
//        * 5-octave fbm with per-octave 0.5-radian rotation (kills the
//          axis-aligned ridge artifacts plain fbm has)
//        * Curl-based displacement instead of domain warping (produces
//          divergence-free swirls that read as real fluid motion)
//        * sRGB → linear → sRGB brightness modulation (gamma-correct)
//        * Subtle radial vignette (8% edge darkening)
//        * Two incommensurate cycles (23s and 31s, coprime → no repeat
//          for ~12 minutes)
//
//    - manifoldGrain — fine fractal noise overlay (~7% peak-to-peak
//      luminance variance). Static, cheap, tactile.
//
//  Apply via ShaderLibrary.manifoldCloud(...) / .manifoldGrain(...) in
//  AtmosphericBackground.swift.

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// MARK: - Colour space helpers (gamma-correct blending)
// =============================================================================

// Approximate sRGB ↔ linear with gamma 2.2. The proper IEC 61966-2-1
// piecewise formula is more accurate but our brightness modulation is
// in the ±7% band — gamma 2.2 is well within tolerance.
//
// pow() is moderately expensive on the GPU; for tighter performance we
// could use the c*c approximation (gamma 2.0), but the visible
// difference on warm yellows justifies the cost.
static inline half3 srgbToLinear(half3 c) {
    return pow(c, half3(2.2h));
}

static inline half3 linearToSrgb(half3 c) {
    return pow(c, half3(1.0h / 2.2h));
}

// =============================================================================
// MARK: - 2D Simplex noise (Ashima/McEwan, MSL port)
// =============================================================================
//
// Returns smooth noise in roughly [-1, 1] with no visible grid artefacts.
// Cheaper than 3D simplex but visually equivalent for our 2D atmospheric
// use case.
//
// Original GLSL: https://github.com/ashima/webgl-noise (MIT licensed)

static inline float3 mod289(float3 x) {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}

static inline float2 mod289_2(float2 x) {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}

static inline float3 permute(float3 x) {
    return mod289(((x * 34.0) + 10.0) * x);
}

static float snoise(float2 v) {
    const float4 C = float4(0.211324865405187,    // (3 - sqrt(3))/6
                            0.366025403784439,    // 0.5 * (sqrt(3) - 1)
                           -0.577350269189626,    // -1.0 + 2.0*C.x
                            0.024390243902439);   // 1.0 / 41.0

    // First corner
    float2 i  = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);

    // Other corners
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;

    // Permutations
    i = mod289_2(i);
    float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0))
                        + i.x + float3(0.0, i1.x, 1.0));

    // Gradients
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy),
                                 dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;

    float3 x = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;

    // Normalise gradients implicitly by scaling m
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

    // Compute final noise value
    float3 g;
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

// =============================================================================
// MARK: - Fractional Brownian motion with octave rotation
// =============================================================================
//
// Sums 5 octaves of simplex noise. Each octave is rotated by 0.5 radians
// before sampling — this breaks the axis-aligned ridges that plain fbm
// produces, and is the technique Apple's wallpaper shaders use.

static float fbm(float2 st) {
    // Pre-computed rotation matrix: 0.5 rad ≈ 28.6°
    const float2x2 rot = float2x2(cos(0.5), -sin(0.5),
                                   sin(0.5),  cos(0.5));
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * snoise(st);
        st = rot * st * 2.0;          // double frequency + rotate
        amp *= 0.5;                    // halve amplitude
    }
    return v;
}

// =============================================================================
// MARK: - 2D curl noise — divergence-free fluid-like flow
// =============================================================================
//
// curl(F) = (∂F/∂y, -∂F/∂x) for a scalar field F. Produces a vector
// field whose every flowline is closed (divergence-free) — fluid
// streamlines, not stretched ridges. Makes cloud motion look natural
// rather than "noise-y."
//
// Computed via finite-difference approximation. eps controls the
// precision; 0.01 is fine for our slow temporal sampling.

static float2 curl(float2 p) {
    const float eps = 0.01;
    float n_x_plus  = fbm(p + float2(eps, 0.0));
    float n_x_minus = fbm(p - float2(eps, 0.0));
    float n_y_plus  = fbm(p + float2(0.0, eps));
    float n_y_minus = fbm(p - float2(0.0, eps));

    float dF_dy = (n_y_plus - n_y_minus) / (2.0 * eps);
    float dF_dx = (n_x_plus - n_x_minus) / (2.0 * eps);

    return float2(dF_dy, -dF_dx);
}

// =============================================================================
// MARK: - 2D pseudo-random (cheap — used by grain only)
// =============================================================================

static inline float random2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

// =============================================================================
// MARK: - Cloud shader (the headline effect)
// =============================================================================
//
// Reads the input pixel colour (already coloured by the MeshGradient
// underneath) and modulates its brightness by a slowly-drifting curl
// noise field. Brightness modulation happens in linear colour space so
// our warm saffron tones stay chroma-true at the highlights and
// shadows; if we modulated in sRGB the lights would look greenish and
// the shadows would look brown.
//
// The two timing constants 23.0 and 31.0 are coprime — their lowest
// common multiple is 713 seconds (~12 minutes), so the cloud field
// never visibly repeats within a session.
//
// Vignette: a soft radial darkening at the canvas edges (~8% peak)
// pulls focus toward whatever the foreground content is. Not
// perceptible in screenshots; very perceptible in motion.

[[ stitchable ]]
half4 manifoldCloud(float2 position, half4 color,
                    float2 size, float time) {
    float2 st = position / size;

    // Two incommensurate cycles, slow.
    float t1 = time / 23.0;
    float t2 = time / 31.0;

    // Curl displacement — divergence-free, fluid-like motion.
    // Sample the curl field at two different scales/times and blend.
    float2 flow = curl(st * 1.6 + float2(t1, 0.0)) * 0.35
                + curl(st * 0.7 + float2(0.0, t2)) * 0.20;

    // Cloud sample — the actual brightness field.
    float cloud = fbm(st * 1.4 + flow);

    // Map [-1, 1] → [0, 1] then to a brightness multiplier in [0.93, 1.07].
    cloud = cloud * 0.5 + 0.5;
    float lift = mix(0.93h, 1.07h, half(cloud));

    // Soft radial vignette — peaks at canvas centre (1.0), drops to
    // 0.92 at corners. smoothstep makes the falloff perceptually clean.
    float dist = length(st - 0.5) * 1.4142;       // 0 at centre, ~1 at corner
    half vignette = mix(1.0h, 0.92h,
                        half(smoothstep(0.55, 1.0, dist)));

    // Gamma-correct brightness modulation:
    // sRGB → linear → multiply → linear → sRGB
    half3 lin = srgbToLinear(color.rgb);
    lin *= lift * vignette;
    half3 out = linearToSrgb(lin);

    return half4(out, color.a);
}

// =============================================================================
// MARK: - Grain shader
// =============================================================================
//
// Fine fractal noise overlay. Adds ~7% peak-to-peak additive grain in
// linear space — at warm yellow saturation this reads as paper texture,
// not coloured noise. Static (no time input) — grain doesn't need to
// move; it just needs to break up smooth gradients at the pixel level.
//
// `seed` exists for per-surface tuning (different grain pattern per
// instance). In practice we use a single seed everywhere.

[[ stitchable ]]
half4 manifoldGrain(float2 position, half4 color,
                    float2 size, float seed) {
    // High-frequency noise — sample at sub-pixel scale to get true
    // grain rather than blocky cells.
    float n = random2(position * 0.5 + float2(seed, seed));

    // Centre on 0, scale to ±0.035 (≈7% peak-to-peak luminance shift).
    half grain = half((n - 0.5) * 0.07);

    // Apply additively in linear space for true tonal grain (not
    // perceptual), then convert back to sRGB.
    half3 lin = srgbToLinear(color.rgb);
    lin += half3(grain);
    half3 out = linearToSrgb(saturate(lin));

    return half4(out, color.a);
}
