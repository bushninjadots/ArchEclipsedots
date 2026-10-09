#version 440

// The desktop spectrum: every look is one analytic pass. Levels arrive as packed
// mat4 uniforms, the palette as eight ramp stops, and each look reduces to a
// signed distance, so glow, reflection and peak caps cost instructions instead
// of an offscreen blur or six hundred rectangles.
//
// `along` runs 0..1 down the spectrum axis, `across` is px from the baseline,
// negative under it where the reflection lives. Polar looks work from `origin`.
//
// Integer maths is arithmetic only: qsb also emits a GLSL 120 translation, which
// has no bitwise operators and would compile clean then draw nothing.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;

    // 128 levels, 16 to a matrix. Qt fills matrix4x4 row major and GLSL indexes
    // columns, so element n reads m[n - 4*(n/4)][n/4].
    mat4 lv0; mat4 lv1; mat4 lv2; mat4 lv3;
    mat4 lv4; mat4 lv5; mat4 lv6; mat4 lv7;
    mat4 pk0; mat4 pk1; mat4 pk2; mat4 pk3;
    mat4 pk4; mat4 pk5; mat4 pk6; mat4 pk7;

    vec4 c0; vec4 c1; vec4 c2; vec4 c3;
    vec4 c4; vec4 c5; vec4 c6; vec4 c7;

    vec2 res;
    vec2 origin;

    float style;     // 0 bars 1 split 2 dots 3 segments 4 wave 5 ribbon
                     // 6 curtain 7 line 8 frame 9 radial 10 orb 11 spiral
                     // 12 aura
    float posMode;   // 0 bottom 1 top 2 center 3 left 4 right
    float bands;
    float maxLen;
    float minLen;
    float thickness;
    float shapeW;    // width of one band's shape, px
    float capR;
    float segN;
    float segGap;
    float gapPx;
    float glowAmt;
    float glowPx;
    float reflectPx;
    float pad;       // bloom room around the box, px
    float peakOn;
    float r0;
    float rMax;
    float spinRad;
    float energy;
    float fade;
    float aa;
    float auraSides; // bitmask 1 top 2 right 4 bottom 8 left (aura only)
    float auraGapT;  // px of top edge given to the bar reservation (aura only);
                     // 0 hugs the screen's very top
    vec4 pillRect;   // aura: navbar pill (x, y, w, h) in screen px
    float pillOn;    // 0 = no live pill (flat top at auraGapT), 1 = suspend
    float panelLx;   // aura: left panel inner edge, px (0 = screen edge)
    float panelRx;   // aura: right panel inner edge, px (cw = screen edge)
};

const float TAU = 6.28318530718;
const float PI = 3.14159265359;

float lvAt(int i) {
    int m = i / 16;
    int j = i - 16 * m;
    int r = j / 4;
    int c = j - 4 * r;
    if (m == 0) return lv0[c][r];
    if (m == 1) return lv1[c][r];
    if (m == 2) return lv2[c][r];
    if (m == 3) return lv3[c][r];
    if (m == 4) return lv4[c][r];
    if (m == 5) return lv5[c][r];
    if (m == 6) return lv6[c][r];
    return lv7[c][r];
}

float pkAt(int i) {
    int m = i / 16;
    int j = i - 16 * m;
    int r = j / 4;
    int c = j - 4 * r;
    if (m == 0) return pk0[c][r];
    if (m == 1) return pk1[c][r];
    if (m == 2) return pk2[c][r];
    if (m == 3) return pk3[c][r];
    if (m == 4) return pk4[c][r];
    if (m == 5) return pk5[c][r];
    if (m == 6) return pk6[c][r];
    return pk7[c][r];
}

int bandAt(float t) {
    return int(clamp(floor(t * bands), 0.0, bands - 1.0));
}

// Catmull-Rom, so the smooth looks read as one curve rather than a fan of steps.
float lvSmooth(float t) {
    float x = clamp(t, 0.0, 1.0) * (bands - 1.0);
    float i1 = floor(x);
    float f = x - i1;
    float p0 = lvAt(int(max(i1 - 1.0, 0.0)));
    float p1 = lvAt(int(i1));
    float p2 = lvAt(int(min(i1 + 1.0, bands - 1.0)));
    float p3 = lvAt(int(min(i1 + 2.0, bands - 1.0)));
    float f2 = f * f;
    float f3 = f2 * f;
    return max(0.0, 0.5 * ((2.0 * p1) + (-p0 + p2) * f
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3));
}

vec3 rampAt(float t) {
    float x = clamp(t, 0.0, 0.99999) * 7.0;
    float i = floor(x);
    float f = x - i;
    vec3 a = i < 0.5 ? c0.rgb : (i < 1.5 ? c1.rgb : (i < 2.5 ? c2.rgb : (i < 3.5 ? c3.rgb
           : (i < 4.5 ? c4.rgb : (i < 5.5 ? c5.rgb : (i < 6.5 ? c6.rgb : c7.rgb))))));
    vec3 b = i < 0.5 ? c1.rgb : (i < 1.5 ? c2.rgb : (i < 2.5 ? c3.rgb : (i < 3.5 ? c4.rgb
           : (i < 4.5 ? c5.rgb : (i < 5.5 ? c6.rgb : c7.rgb)))));
    return mix(a, b, f);
}

float roundBox(vec2 p, vec2 b, float r) {
    r = min(r, min(b.x, b.y));
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Quadratic smooth-min (Inigo Quilez): blends two distances, rounding their
// 90° crossing into an arc of radius ~r. Collapses to a plain min whenever
// the two distances differ by more than r — which is what lets the aura's
// disabled sides (+inf) opt their corners out of the rounding for free.
float smin(float a, float b, float r) {
    float h = clamp(0.5 + 0.5 * (b - a) / r, 0.0, 1.0);
    return mix(b, a, h) - r * h * (1.0 - h);
}

// Quintic ease (Perlin smootherstep): C2-continuous, so a curve built from it
// leaves its anchor and rejoins without a visible kink. Used for the top
// suspension so the band flows off the navbar rather than bending at a seam.
float smootherstep(float a, float b, float x) {
    float t = clamp((x - a) / max(1e-4, b - a), 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// One enabled aura side's contribution, as (inward ratio, blend weight, level,
// perimeter fraction). The ratio is 0 at the side's boundary and 1 at the
// crest, so sides can be combined in normalised space: the corner handoff in
// the aura branch smooth-mins these ratios instead of raw pixel distances,
// which is what lets adjacent sides merge into one continuous field. A
// disabled side returns +inf ratio and zero weight, so it drops out entirely.
vec4 auraSide(float d, float s, float onF, float perimA, float minL, float maxL) {
    if (onF < 0.5)
        return vec4(1e9, 0.0, 0.0, 0.0);
    float al = fract(s / perimA);
    float lv = lvSmooth(al);
    float ln = max(minL, maxL * lv);
    float r = max(0.0, d) / max(ln, 1.0);
    float w = exp(-min(r, 3.0) * 2.4);
    return vec4(r, w, lv, al);
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

// The scope keeps its trace in the level slots, centred on 0.5.
float scopeAt(float t) {
    return (lvSmooth(t) - 0.5) * 2.0;
}

float hash12(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    int st = int(style + 0.5);
    int pm = int(posMode + 0.5);

    float along;
    float across;
    float axisLen;
    // The pass is the look's box plus `pad` on every side for the bloom to fall
    // off in, so the geometry works in box-local pixels.
    vec2 cpx = px - vec2(pad);
    float cw = max(1.0, res.x - 2.0 * pad);
    float ch = max(1.0, res.y - 2.0 * pad);
    if (pm == 3) {
        along = cpx.y / ch;
        across = cpx.x;
        axisLen = ch;
    } else if (pm == 4) {
        along = cpx.y / ch;
        across = cw - cpx.x;
        axisLen = ch;
    } else if (pm == 1) {
        along = cpx.x / cw;
        across = cpx.y;
        axisLen = cw;
    } else {
        along = cpx.x / cw;
        across = ch - reflectPx - cpx.y;
        axisLen = cw;
    }

    bool polar = st >= 9 && st <= 11;
    bool frame = st == 8;
    bool aura = st == 12;
    bool centred = (pm == 2 && st != 6) || st == 1;
    float signedAcross = polar ? 0.0
        : ((pm == 3 || pm == 4) ? cpx.x - cw * 0.5 : ch * 0.5 - cpx.y);
    if (pm == 4) signedAcross = -signedAcross;
    if (centred) across = abs(signedAcross);

    float mirrorFade = 1.0;
    if (!polar && !frame && !aura && !centred && across < 0.0) {
        if (reflectPx <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }
        across = -across;
        mirrorFade = 0.42 * max(0.0, 1.0 - across / reflectPx);
    }

    float slot = axisLen / max(bands, 1.0);
    float barW = max(1.5, slot * thickness);
    float alongPx = along * axisLen;

    float sd = 1e9;
    float extraA = 0.0;   // accents: crests, stems, caps, rings
    float tRamp = along;
    float lift = 0.0;     // 0 at the root of the shape, 1 at its tip
    float hot = 0.0;      // how hard this band is hitting, for the tip highlight
    float fillA = 1.0;    // how solid the body reads; a rimmed look wants less

    if (st == 0 || st == 1) {
        int i = bandAt(along);
        float lvv = lvAt(i);
        float len = max(minLen, maxLen * lvv);
        float ci = (float(i) + 0.5) * slot;
        tRamp = float(i) / max(bands - 1.0, 1.0);
        hot = lvv;
        if (st == 1) {
            float arm = max(minLen, len * 0.5);
            float base = gapPx * 0.5;
            sd = roundBox(vec2(alongPx - ci, across - (base + arm * 0.5)),
                          vec2(barW * 0.5, arm * 0.5), capR);
            lift = clamp((across - base) / max(arm, 1.0), 0.0, 1.0);
        } else {
            sd = roundBox(vec2(alongPx - ci, across - len * 0.5),
                          vec2(barW * 0.5, len * 0.5), capR);
            lift = clamp(across / max(len, 1.0), 0.0, 1.0);
        }
        if (peakOn > 0.5) {
            float ph = maxLen * pkAt(i);
            float capH = max(2.0, min(capR * 1.1, barW * 0.34));
            float sdp = roundBox(vec2(alongPx - ci, across - (ph + capH * 1.6)),
                                 vec2(barW * 0.46, capH * 0.5), capH * 0.5);
            extraA += (1.0 - smoothstep(-aa, aa, sdp)) * 0.85;
        }
    } else if (st == 2) {
        // a disc on the band's tip over a hairline stem, so it still reads as a
        // spectrum and not as scattered pills.
        int i = bandAt(along);
        float lvv = lvAt(i);
        float len = max(minLen, maxLen * lvv);
        float ci = (float(i) + 0.5) * slot;
        float rad = max(1.2, barW * (0.30 + 0.28 * lvv));
        tRamp = float(i) / max(bands - 1.0, 1.0);
        hot = lvv;
        sd = length(vec2(alongPx - ci, across - len)) - rad;
        lift = 1.0;
        float stem = roundBox(vec2(alongPx - ci, across - len * 0.5),
                              vec2(max(0.6, barW * 0.07), len * 0.5), 0.0);
        extraA += (1.0 - smoothstep(-aa, aa, stem)) * 0.16;
    } else if (st == 3) {
        int i = bandAt(along);
        float lvv = lvAt(i);
        float len = max(minLen, maxLen * lvv);
        float ci = (float(i) + 0.5) * slot;
        float pitch = maxLen / max(segN, 1.0);
        float lit = ceil(len / max(pitch, 1.0));
        float cell = floor(across / max(pitch, 1.0));
        tRamp = float(i) / max(bands - 1.0, 1.0);
        if (cell >= 0.0 && cell < lit) {
            float ch = max(1.5, pitch - segGap);
            sd = roundBox(vec2(alongPx - ci, across - (cell + 0.5) * pitch),
                          vec2(barW * 0.5, ch * 0.5), min(capR, ch * 0.4));
            lift = lit > 1.0 ? cell / (lit - 1.0) : 1.0;
            // the topmost cell is the leading edge of the meter and runs hot.
            hot = lvv * (cell >= lit - 1.0 ? 1.0 : 0.25);
        }
        if (peakOn > 0.5) {
            float ph = maxLen * pkAt(i);
            float capH = max(2.0, pitch * 0.20);
            float sdp = roundBox(vec2(alongPx - ci, across - (ph + capH * 1.5)),
                                 vec2(barW * 0.46, capH * 0.5), capH * 0.5);
            extraA += (1.0 - smoothstep(-aa, aa, sdp)) * 0.85;
        }
    } else if (st == 4 || st == 6) {
        // wave fills up to the curve; curtain hangs from the baseline down to
        // it, so it reads as light spilling out from under the bar above.
        float lvv = lvSmooth(along);
        float h = max(minLen, maxLen * lvv);
        if (centred) h = max(minLen, h * 0.5);
        sd = across - h;
        hot = lvv;
        lift = st == 4 ? clamp(across / max(h, 1.0), 0.0, 1.0)
                       : 1.0 - clamp(across / max(h, 1.0), 0.0, 1.0);
        // a lit crest on the moving edge, and for the curtain a hairline sealing
        // it to the edge it hangs from.
        extraA += exp(-abs(sd) / max(1.5, aa * 2.5)) * 0.55;
        if (st == 6)
            extraA += (1.0 - smoothstep(-aa, aa, across - max(1.0, aa * 1.4))) * 0.5;
    } else if (st == 5) {
        // three translucent bands of light at different depths: an aurora, not
        // three stacked fills, so the wallpaper still shows between them.
        // Small phase offsets: shifting a layer far along the spectrum makes the
        // three disagree and spike, instead of drifting past each other.
        float a = 0.0;
        float front = maxLen * lvSmooth(along);
        for (int k = 0; k < 3; k++) {
            float h = maxLen * (1.0 - float(k) * 0.24) * lvSmooth(along + float(k) * 0.03);
            if (centred) h = h * 0.5;
            float bandW = max(1.5, maxLen * (0.055 - 0.010 * float(k)));
            a += (1.0 - smoothstep(-aa * 1.5, bandW * 1.1, max(abs(across - h) - bandW, 0.0)))
                 * (0.50 - 0.12 * float(k));
        }
        if (centred) front = front * 0.5;
        sd = abs(across - front) - max(1.5, maxLen * 0.055);
        extraA += a;
        hot = lvSmooth(along);
        lift = clamp(across / max(front, 1.0), 0.0, 1.0);
    } else if (st == 7) {
        // the scope: the live waveform, windowed at the ends so it melts into
        // the wallpaper instead of stopping dead.
        float amp = maxLen * 0.5;
        float base = centred ? 0.0 : amp * 1.05;
        float win = pow(sin(PI * clamp(along, 0.0, 1.0)), 0.45);
        float dt = 1.0 / max(axisLen * 0.25, 8.0);
        float y0 = base + scopeAt(along - dt) * amp * win;
        float y1 = base + scopeAt(along) * amp * win;
        float y2 = base + scopeAt(along + dt) * amp * win;
        float w = max(1.5, maxLen * 0.013);
        vec2 p = vec2(alongPx, centred ? signedAcross : across);
        sd = min(segDist(p, vec2(alongPx - dt * axisLen, y0), vec2(alongPx, y1)),
                 segDist(p, vec2(alongPx, y1), vec2(alongPx + dt * axisLen, y2))) - w;
        lift = 1.0;
        hot = abs(scopeAt(along));
        float bl = abs(p.y - base) - max(0.6, aa * 0.7);
        extraA += (1.0 - smoothstep(-aa, aa, bl)) * 0.16 * energy;
    } else if (st == 8) {
        // the frame: a full ring of bars around the whole screen's edge, packed
        // with a small gap and each grown inward to its own height, so it reads
        // as a bar spectrum wrapped around the display.
        float dL = cpx.x;
        float dR = cw - cpx.x;
        float dT = cpx.y;
        float dB = ch - cpx.y;
        float perim = 2.0 * (cw + ch);
        float ed;   // inward distance from the nearest edge
        float s;    // arc length clockwise from the top-left corner
        float mE = min(min(dL, dR), min(dT, dB));
        if (mE == dT)      { ed = dT; s = cpx.x; }
        else if (mE == dR) { ed = dR; s = cw + cpx.y; }
        else if (mE == dB) { ed = dB; s = cw + ch + (cw - cpx.x); }
        else               { ed = dL; s = 2.0 * cw + ch + (ch - cpx.y); }
        float al = s / perim;
        // Many bars, packed: each samples the smoothed spectrum at its own spot,
        // so the ring fills with bars of uneven height rather than sparse ticks.
        float ticks = max(bands, 1.0) * 3.0;
        float slotP = perim / ticks;
        float ti = floor(s / slotP);
        float ci = (ti + 0.5) * slotP;
        float tAl = (ti + 0.5) / ticks;
        float lvv = lvSmooth(tAl);
        float len = max(minLen, maxLen * lvv);
        float barWp = max(1.5, slotP * thickness);
        tRamp = tAl;
        hot = lvv;
        sd = roundBox(vec2(s - ci, ed - len * 0.5), vec2(barWp * 0.5, len * 0.5), capR);
        lift = clamp(ed / max(len, 1.0), 0.0, 1.0);
        if (peakOn > 0.5) {
            float ph = maxLen * pkAt(bandAt(tAl));
            float capH = max(2.0, min(capR * 1.1, barWp * 0.34));
            float sdp = roundBox(vec2(s - ci, ed - (ph + capH * 1.6)),
                                 vec2(barWp * 0.46, capH * 0.5), capH * 0.5);
            extraA += (1.0 - smoothstep(-aa, aa, sdp)) * 0.85;
        }
    } else if (st == 12) {
        // aura: a flowing reactive border hugging the screen edges (the iNiR
        // OrganicEdge "full frame" idea, drawn analytically). Each enabled
        // side contributes a NORMALISED inward ratio (0 at the edge, 1 at the
        // crest); the frame is the smooth-min of those ratios, so adjoining
        // sides hand off through one continuous field and a corner reads as a
        // single light going round the turn instead of four stripes ending at
        // a point. Level, depth and the perimeter/colour coordinate are all
        // blended with the same weights, so there is no step at the corner.
        //
        // The top boundary follows a suspension curve when a live pill is known:
        // at the screen corners, dipping to the pill underside under its span.
        // Anywhere else (no live pill, bar hidden, invalid bridge) it is flat at
        // `auraGapT`, exactly as before; nothing ever paints above it.
        float gT = max(0.0, auraGapT);    // flat-top fallback (bar hidden / no bridge)
        float yTop = gT;
        if (pillOn > 0.5) {
            // A wide, C2-continuous "curtain" off the bar: the top boundary
            // leaves the screen corners, sweeps up to the pill's underside and
            // eases back down with no kink, so the frame always reads as if it
            // grows out of the navbar. The ease scales with the screen width
            // (clamped), not the pill height, so it stays gentle even when the
            // search/control island makes the pill tall.
            float px0 = pillRect.x;
            float px1 = pillRect.x + pillRect.z;
            float pb = clamp(pillRect.y + pillRect.w, 0.0, ch);
            float m = clamp(0.18 * cw, 160.0, 360.0);
            float under = smootherstep(px0 - m, px0, cpx.x)
                        * (1.0 - smootherstep(px1, px1 + m, cpx.x));
            yTop = mix(0.0, pb, under);
        }
        // Panel inner edges are the left/right boundaries while a panel is out;
        // they ride the unfold live, so the band follows continuously. Crossing
        // edges (a panel wider than half, or stale geometry) fall back flat.
        float Lx = clamp(panelLx, 0.0, cw);
        float Rx = (panelRx > 0.0) ? clamp(panelRx, 0.0, cw) : cw;
        if (Lx > Rx) { Lx = 0.0; Rx = cw; }
        float Ty = yTop, By = ch;
        // Which sides are enabled, decoded from the bitmask.
        float onT = mod(auraSides, 2.0) >= 1.0 ? 1.0 : 0.0;
        float onR = mod(auraSides, 4.0) >= 2.0 ? 1.0 : 0.0;
        float onB = mod(auraSides, 8.0) >= 4.0 ? 1.0 : 0.0;
        float onL = mod(auraSides, 16.0) >= 8.0 ? 1.0 : 0.0;
        float gTw = max(1.0, ch - gT);          // usable height below the gap
        float perimA = 2.0 * (cw + gTw);
        if (cpx.y < yTop || cpx.x < Lx || cpx.x > Rx) {
            // Outside the frame box: above the (curved) top boundary — the
            // reserved bar strip — and the margins hidden behind an open panel.
            // Clipping these keeps the band sitting on the panel's inner edge
            // instead of filling the whole margin.
            sd = 1e9;
        } else {
            // Per-side inward distance (>=0 inside the frame box) and the
            // perimeter fraction the fragment projects onto that side.
            float dT = cpx.y - Ty, dR = Rx - cpx.x, dB = By - cpx.y, dL = cpx.x - Lx;
            float sT = cpx.x / max(cw, 1.0);
            float sR = cw + clamp(dT / max(gTw, 1.0), 0.0, 1.0) * gTw;
            float sB = cw + gTw + clamp((cw - cpx.x) / max(cw, 1.0), 0.0, 1.0) * cw;
            float sL = 2.0 * cw + gTw + clamp((By - cpx.y) / max(gTw, 1.0), 0.0, 1.0) * gTw;
            vec4 aT = auraSide(dT, sT * cw, onT, perimA, minLen, maxLen);
            vec4 aR = auraSide(dR, sR, onR, perimA, minLen, maxLen);
            vec4 aB = auraSide(dB, sB, onB, perimA, minLen, maxLen);
            vec4 aL = auraSide(dL, sL, onL, perimA, minLen, maxLen);
            // Smooth-min the enabled ratios: adjacent sides merge through an
            // arc, and because a disabled side is +inf it simply drops out and
            // its neighbour ends square (smin returns the finite value).
            float kR = 0.35;   // corner handoff, in ratio units (~0.35*depth px)
            float fr = 1e9;
            fr = smin(fr, aT.x, kR);
            fr = smin(fr, aR.x, kR);
            fr = smin(fr, aB.x, kR);
            fr = smin(fr, aL.x, kR);
            // Blend level/depth across the corner (nearer sides weigh more), so
            // the crest height flows instead of stepping at the diagonal.
            float wsum = max(1e-4, aT.y + aR.y + aB.y + aL.y);
            float blv = (aT.y * aT.z + aR.y * aR.z + aB.y * aB.z + aL.y * aL.z) / wsum;
            float blen = max(minLen, maxLen * blv);
            // The frame boundary is ratio == 1, i.e. depth = len. Scaling back
            // to px keeps the body/crest maths identical to the other looks.
            sd = (fr - 1.0) * blen;
            // Perimeter coordinate as a weighted phase average: two sides that
            // meet at a corner point the same way, so the palette sweeps one
            // continuous path (no colour seam where the loop wraps).
            vec2 phv = vec2(0.0);
            phv += vec2(cos(aT.w * TAU), sin(aT.w * TAU)) * aT.y;
            phv += vec2(cos(aR.w * TAU), sin(aR.w * TAU)) * aR.y;
            phv += vec2(cos(aB.w * TAU), sin(aB.w * TAU)) * aB.y;
            phv += vec2(cos(aL.w * TAU), sin(aL.w * TAU)) * aL.y;
            float alA = atan(phv.y, phv.x) / TAU;
            if (alA < 0.0)
                alA += 1.0;
            tRamp = alA;
            hot = blv;
            // Distance to the nearest ENABLED boundary, for the root lift and
            // the resting rail (a min of two side distances forms a connected
            // right angle at the corner).
            float dmin = 1e9;
            if (onT > 0.5) dmin = min(dmin, dT);
            if (onR > 0.5) dmin = min(dmin, dR);
            if (onB > 0.5) dmin = min(dmin, dB);
            if (onL > 0.5) dmin = min(dmin, dL);
            // the body is a wash of light, not paint: quiet bands leave the
            // wallpaper readable, loud ones push further in and fill more.
            fillA = (0.05 + 0.40 * blv);
            lift = clamp(dmin / max(blen, 1.0), 0.0, 1.0);
            // the crest itself: a lit line riding the level curve, hotter on
            // louder bands, so the border reads as energy rather than geometry.
            float crestA = abs(sd) - max(1.2, aa * 1.6);
            extraA += (1.0 - smoothstep(-aa, aa, crestA)) * (0.30 + 0.50 * blv);
            // the resting rail: a 1.5px hairline at the very edge while the
            // band under it is quiet, melting away as that band's crest
            // arrives. Because it rides the min side distance it walks the
            // corner too, so silence rests as one connected outline.
            float railA = abs(dmin - 1.5) - max(0.8, aa * 0.8);
            extraA += (1.0 - smoothstep(-aa, aa, railA)) * 0.10
                      * (1.0 - clamp(blv * 3.0, 0.0, 1.0));
        }
    } else if (st == 9) {
        vec2 q = px - origin;
        float d = length(q);
        float a01 = fract((atan(q.y, q.x) + spinRad + PI * 0.5) / TAU + 1.0);
        int i = bandAt(a01);
        float lvv = lvAt(i);
        float len = max(minLen, rMax * lvv);
        float ac = (float(i) + 0.5) / max(bands, 1.0);
        float off = (a01 - ac) - floor((a01 - ac) + 0.5);
        tRamp = a01;
        hot = lvv;
        // the angular offset becomes an arc length at this radius, so a bar
        // keeps its width whatever the ring size.
        sd = roundBox(vec2(off * TAU * max(d, 1.0), d - (r0 + len * 0.5)),
                      vec2(max(1.0, shapeW * 0.5), len * 0.5), capR);
        lift = clamp((d - r0) / max(len, 1.0), 0.0, 1.0);
        // the ring the bars stand on, breathing with the bass so the centre is
        // never a dead hole.
        float ringW = max(1.2, shapeW * 0.22);
        float ring = abs(d - r0 * (1.0 + 0.08 * energy)) - ringW;
        extraA += (1.0 - smoothstep(-aa, aa, ring)) * 0.45;
    } else if (st == 10) {
        vec2 q = px - origin;
        float d = length(q);
        float a01 = fract((atan(q.y, q.x) + spinRad + PI * 0.5) / TAU + 1.0);
        // folded around the vertical axis so both seams meet, and averaged over
        // five angles: a bass-heavy spectrum wrapped raw reads as a flower.
        float fold = a01 < 0.5 ? a01 * 2.0 : (1.0 - a01) * 2.0;
        float w = 2.0 / max(bands, 8.0);
        float lvl = (lvSmooth(fold - w) + lvSmooth(fold - w * 0.5) + lvSmooth(fold)
                   + lvSmooth(fold + w * 0.5) + lvSmooth(fold + w)) * 0.2;
        float rr = r0 + rMax * lvl;
        // A glass sphere, not a disc of colour: the body is barely there, the
        // wobbling rim carries the shape, and two ripples inside give it depth so
        // the wallpaper reads through the middle.
        sd = d - rr;
        lift = clamp(d / max(rr, 1.0), 0.0, 1.0);
        hot = lvl;
        fillA = 0.05 + 0.25 * lift;
        tRamp = 0.28 + 0.50 * lift;
        float rim = abs(sd) - max(1.3, aa * 1.5);
        extraA += (1.0 - smoothstep(-aa, aa, rim)) * 0.95;
        extraA += exp(-max(abs(sd), 0.0) / max(rMax * 0.22, 2.0)) * 0.22;
        for (int rg = 1; rg < 3; rg++) {
            float rr2 = rr * (0.34 + 0.24 * float(rg)) * (1.0 + 0.06 * energy);
            float ripple = abs(d - rr2) - max(1.0, aa);
            extraA += (1.0 - smoothstep(-aa, aa, ripple)) * (0.30 - 0.08 * float(rg));
        }
        extraA += exp(-d / max(r0 * 0.30, 2.0)) * (0.10 + 0.25 * energy);
    } else {
        vec2 q = px - origin;
        float d = length(q);
        float a01 = fract((atan(q.y, q.x) + spinRad + PI * 0.5) / TAU + 1.0);
        float turns = 1.5;
        float k = rMax / (turns * TAU);
        float best = 1e9;
        float bestT = 0.0;
        float bestL = 0.0;
        for (int n = 0; n < 2; n++) {
            float th = (a01 + float(n)) * TAU;
            if (th <= turns * TAU) {
                float t = th / (turns * TAU);
                float lvv = lvAt(bandAt(t));
                // the arm tapers in at both ends, so it reads as drawn rather
                // than cut off.
                float taper = smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.90, 1.0, t));
                float w = max(1.5, rMax * 0.13 * (0.35 + 0.65 * lvv) * max(taper, 0.06));
                float dd = abs(d - (r0 + k * th)) - w * 0.5;
                if (dd < best) {
                    best = dd;
                    bestT = t;
                    bestL = lvv;
                }
            }
        }
        sd = best;
        tRamp = bestT;
        hot = bestL;
        lift = clamp((d - r0) / max(rMax, 1.0), 0.0, 1.0);
    }

    float body = 1.0 - smoothstep(-aa, aa, sd);
    // Roots read as light rather than paint: the shape fades toward where it
    // grows from, and only the tip carries full weight.
    float cover = clamp(body * fillA * mix(0.66, 1.0, lift) + extraA, 0.0, 1.0);

    // Two-term bloom outside the shape: a tight bright core and a wide soft
    // skirt. It must not reach inside, or a filled look (the orb, the wave)
    // takes a flat wash of light across its whole body and turns milky.
    float g = max(sd, 0.0);
    float halo = glowAmt > 0.0
        ? (exp(-g / max(glowPx * 0.5, 0.8)) * 0.42 + exp(-g / max(glowPx * 3.0, 3.0)) * 0.16)
          * glowAmt * (0.35 + 0.65 * energy) * (1.0 - body)
        : 0.0;

    float a = clamp(cover + halo, 0.0, 1.0) * fade * mirrorFade * qt_Opacity;
    // Edge looks melt into the wallpaper at both ends instead of being cut off;
    // the frame and the aura wrap, so they have no ends to fade.
    if (!polar && !frame && !aura)
        a *= smoothstep(0.0, 0.035, along) * (1.0 - smoothstep(0.965, 1.0, along));
    if (a <= 0.002) {
        fragColor = vec4(0.0);
        return;
    }

    vec3 col = rampAt(tRamp);
    // A loud band's tip runs hot, which is what makes a spectrum look lit. Kept
    // gentle: a hard push to white drains the accent the rest of the shell uses.
    col = mix(col, min(col * 1.22 + 0.10, vec3(1.0)),
              smoothstep(0.62, 1.0, lift) * clamp(hot, 0.0, 1.0) * 0.55);
    if (mirrorFade < 1.0) col *= 0.85;
    if (st == 1 && signedAcross < 0.0) col *= 0.62;
    // A touch of noise keeps the wide soft skirts from banding.
    a = clamp(a + (hash12(px) - 0.5) * 0.006, 0.0, 1.0);
    fragColor = vec4(col * a, a);
}
