#version 440
// The shell frame: a band round the whole screen whose inner line is a rounded
// rectangle, with the navbar pill and the side panels melted into it. Modelled
// on iNiR's Iris field (modules/iris/field/IrisField.frag, GPL-3.0): the band is
// the complement of the screen's inner rounded box, each body is a rounded box,
// and a polynomial smooth union between band and body draws the fillet, so the
// pill reads as grown out of the frame rather than sitting on it.
//
// The bodies are painted here too (Bar.qml's pill Rectangles are transparent
// in frame mode), so the whole shell is one silhouette with one edge.
//
// Rebuild: /usr/lib/qt6/bin/qsb --qt6 -o frame.frag.qsb frame.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // x, y: the surface in px. z: the band. w: the band's inner corner radius.
    vec4 field;
    vec4 tint;
    // How far the band's inner line swells with the music on each side
    // (left, top, right, bottom), and x of waveClock: the travelling phase.
    vec4 edgeWave;
    vec4 waveClock;
    // Up to three bodies: centre.xy, half.xy in px; their corner radii
    // (top-left, top-right, bottom-right, bottom-left); fillet depth in x of fuse.
    vec4 shape0; vec4 radii0;
    vec4 shape1; vec4 radii1;
    vec4 shape2; vec4 radii2;
    vec4 fuse;
    // x: music level, y: light opacity, z: light width px.
    vec4 light;
    vec4 ink;
    // Interior rectangle nothing reaches (l, t, r, b): those pixels skip the pass.
    vec4 quiet;
    // With the music, the bodies themselves swell into the frame: x is that
    // swell in px (level * reach), y the top band's reach in px under the pill.
    vec4 organic;
    // The border: an outer stroke round the band and every body. Two stops
    // swept round the screen centre; x of borderInfo its width px, y the
    // sweep's phase.
    vec4 borderA;
    vec4 borderB;
    vec4 borderInfo;
} u;

const float FAR = 1e8;

float roundedBox(vec2 p, vec2 centre, vec2 halfSize, vec4 radii) {
    vec2 d = p - centre;
    // y runs down: d.y > 0 is the bottom half.
    float r = d.y > 0.0 ? (d.x > 0.0 ? radii.z : radii.w) : (d.x > 0.0 ? radii.y : radii.x);
    r = min(r, min(halfSize.x, halfSize.y));
    vec2 q = abs(d) - (halfSize - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float smoothUnion(float a, float b, float k) {
    if (k <= 0.001)
        return min(a, b);
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float body(vec2 p, vec4 s, vec4 r) {
    if (s.z <= 0.0 || s.w <= 0.0)
        return FAR;
    return roundedBox(p, s.xy, s.zw, r);
}

// A slow travelling ripple, so a swelling body bulges in soft lobes that move
// along its edge rather than growing as a uniform rectangle.
float ripple(vec2 p, float t) {
    return 0.50 + 0.22 * sin(p.x * 0.019 + t * 1.3) + 0.16 * sin(p.y * 0.017 - t * 1.1)
         + 0.12 * sin((p.x - p.y) * 0.041 + t * 2.1);
}

void main() {
    vec2 size = max(u.field.xy, vec2(1.0));
    vec2 p = qt_TexCoord0 * size;
    float bw = u.borderInfo.x;
    if (p.x > u.quiet.x + bw && p.y > u.quiet.y + bw && p.x < u.quiet.z - bw && p.y < u.quiet.w - bw) {
        fragColor = vec4(0.0);
        return;
    }

    // The band: everything outside the inner rounded rectangle, whose sides
    // breathe inward with the music along two travelling sines (iNiR's swell).
    float t = u.waveClock.x;
    float alongY = 0.60 + 0.24 * sin(p.y * 0.011 + t) + 0.16 * sin(p.y * 0.027 - t * 1.4);
    float alongX = 0.60 + 0.24 * sin(p.x * 0.009 - t) + 0.16 * sin(p.x * 0.023 + t * 1.2);
    // The top band rises toward the pill: its swell is strongest under the
    // pill's shoulders and falls off along the edge.
    float pillPull = 0.0;
    if (u.shape0.z > 0.0) {
        float dx = (p.x - u.shape0.x) / (u.shape0.z + 260.0);
        pillPull = exp(-dx * dx);
    }
    float topWave = u.edgeWave.y + u.organic.y * pillPull;
    vec2 lo = vec2(u.field.z + u.edgeWave.x * alongY, u.field.z + topWave * alongX);
    vec2 hi = size - vec2(u.field.z + u.edgeWave.z * alongY, u.field.z + u.edgeWave.w * alongX);
    float r = u.field.w;
    float frame = -roundedBox(p, (lo + hi) * 0.5, max((hi - lo) * 0.5, vec2(0.0)), vec4(r));

    float b0 = body(p, u.shape0, u.radii0);
    float b1 = body(p, u.shape1, u.radii1);
    float b2 = body(p, u.shape2, u.radii2);
    // The bodies as laid out ...
    // ... and as the music swells them: lobes travel along their edges, and the
    // fillet into the frame deepens with the level, so the pill and panels read
    // as one soft mass breathing out of the band.
    float swell = u.organic.x * ripple(p, t);
    float k = u.fuse.x + u.organic.x * 1.4;
    float united = frame;
    if (b0 < FAR) united = min(united, smoothUnion(frame, b0 - swell, k));
    if (b1 < FAR) united = min(united, smoothUnion(frame, b1 - swell, k));
    if (b2 < FAR) united = min(united, smoothUnion(frame, b2 - swell, k));

    // One silhouette, one edge: the band, the fillets and the bodies are all
    // painted here (Bar.qml's pill backgrounds go transparent in frame mode),
    // so there is no seam where two anti-aliased edges would meet.
    float coverage = 1.0 - smoothstep(-0.7, 0.7, united);
    float a = coverage * u.tint.a * u.qt_Opacity;
    vec3 colour = u.tint.rgb * a;
    float alpha = a;

    // The etched light: a fine line just inside the joined contour that
    // brightens with the music (iNiR's "etched" frame appearance).
    if (u.light.x > 0.001) {
        float inside = max(0.0, -united);
        float width = max(1.0, u.light.z);
        float etched = 1.0 - smoothstep(0.0, width, abs(inside - 1.25));
        float l = coverage * etched * u.light.x * u.light.y * u.ink.a * u.qt_Opacity;
        colour = u.ink.rgb * l + colour * (1.0 - l);
        alpha = l + alpha * (1.0 - l);
    }
    // Outer stroke just outside the joined silhouette, so it borders the band,
    // the fillets and the pills alike and never lands under a pill's content.
    if (bw > 0.0) {
        float outside = smoothstep(-0.7, 0.7, united);
        float within = 1.0 - smoothstep(bw - 0.7, bw + 0.7, united);
        vec2 c = size * 0.5;
        float ang = atan(p.y - c.y, p.x - c.x);
        float g = 0.5 + 0.5 * sin(ang * 2.0 - u.borderInfo.y);
        vec4 bc = mix(u.borderA, u.borderB, g);
        float s = outside * within * bc.a * u.qt_Opacity;
        colour = bc.rgb * s + colour * (1.0 - s);
        alpha = s + alpha * (1.0 - s);
    }
    fragColor = vec4(colour, alpha);
}
