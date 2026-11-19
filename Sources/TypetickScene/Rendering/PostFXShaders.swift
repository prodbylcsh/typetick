/// Metal source of the post-processing chain. Compiled at runtime with
/// `makeLibrary(source:)`, so it works no matter how the package is built.
enum PostFXShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 position [[position]]; float2 uv; };

vertex VOut vs_fullscreen(uint vid [[vertex_id]]) {
    // one oversized triangle covering the screen
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

constexpr sampler sLinear(filter::linear, address::clamp_to_edge);
constexpr sampler sPoint(filter::nearest, address::clamp_to_edge);

inline float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
inline float ign(float2 px) { return fract(52.9829189 * fract(dot(px, float2(0.06711056, 0.00583715)))); }

// ---------------------------------------------------------------- ambient occlusion

struct AOUniforms {
    float4x4 invProj;
    float4x4 proj;
    float4 params;   // radius (m), power, bias (m), reverseZ (1/0)
    float4 texel;    // depth texel size xy, output size zw
};

inline float3 viewPos(float2 uv, float d, float4x4 invProj) {
    float4 ndc = float4(uv.x * 2.0 - 1.0, (1.0 - uv.y) * 2.0 - 1.0, d, 1.0);
    float4 v = invProj * ndc;
    return v.xyz / v.w;
}

inline bool isSky(float d, float reverseZ) { return reverseZ > 0.5 ? d <= 0.0000001 : d >= 0.9999999; }

fragment half fs_ssao(VOut in [[stage_in]], depth2d<float> depth [[texture(0)]],
                      constant AOUniforms& u [[buffer(0)]], constant float4* kernel [[buffer(1)]]) {
    float d = depth.sample(sPoint, in.uv);
    if (isSky(d, u.params.w)) return 1.0h;
    float3 p = viewPos(in.uv, d, u.invProj);
    float2 t = u.texel.xy;
    float3 px = viewPos(in.uv + float2(t.x, 0), depth.sample(sPoint, in.uv + float2(t.x, 0)), u.invProj);
    float3 py = viewPos(in.uv + float2(0, t.y), depth.sample(sPoint, in.uv + float2(0, t.y)), u.invProj);
    float3 nx = viewPos(in.uv - float2(t.x, 0), depth.sample(sPoint, in.uv - float2(t.x, 0)), u.invProj);
    float3 ny = viewPos(in.uv - float2(0, t.y), depth.sample(sPoint, in.uv - float2(0, t.y)), u.invProj);
    // pick the smaller differences so silhouettes do not smear normals
    float3 dx = (abs(px.z - p.z) < abs(nx.z - p.z)) ? (px - p) : (p - nx);
    float3 dy = (abs(py.z - p.z) < abs(ny.z - p.z)) ? (py - p) : (p - ny);
    float3 n = normalize(cross(dx, dy));
    if (dot(n, -p) < 0.0) n = -n;
    float angle = ign(in.position.xy) * 6.2831853;
    float3 rnd = float3(cos(angle), sin(angle), 0.0);
    float3 tg = normalize(rnd - n * dot(rnd, n));
    float3 bt = cross(n, tg);
    float3x3 tbn = float3x3(tg, bt, n);
    float radius = u.params.x;
    float occ = 0.0;
    const int N = 16;
    for (int i = 0; i < N; i++) {
        float3 s = p + (tbn * kernel[i].xyz) * radius;
        float4 clip = u.proj * float4(s, 1.0);
        float2 suv = clip.xy / clip.w * float2(0.5, -0.5) + 0.5;
        if (any(suv < 0.0) || any(suv > 1.0)) continue;
        float sd = depth.sample(sPoint, suv);
        float3 sp = viewPos(suv, sd, u.invProj);
        float range = smoothstep(0.0, 1.0, radius / max(abs(p.z - sp.z), 1e-5));
        occ += (sp.z >= s.z + u.params.z ? 1.0 : 0.0) * range;
    }
    float ao = 1.0 - occ / float(N);
    return half(pow(saturate(ao), u.params.y));
}

struct BlurUniforms { float4 dir; float4 params; }; // dir.xy texel step; params.x depth sharpness

fragment half fs_aoblur(VOut in [[stage_in]], texture2d<half> ao [[texture(0)]], depth2d<float> depth [[texture(1)]],
                        constant BlurUniforms& u [[buffer(0)]]) {
    float dc = depth.sample(sPoint, in.uv);
    float sum = 0.0, wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        float2 uv = in.uv + u.dir.xy * float(i);
        float w = exp(-float(i * i) / 8.0);
        float dd = depth.sample(sPoint, uv);
        w *= exp(-abs(dd - dc) * u.params.x);
        sum += float(ao.sample(sLinear, uv).r) * w;
        wsum += w;
    }
    return half(sum / max(wsum, 1e-5));
}

// ---------------------------------------------------------------- bloom (dual filter)

struct BloomUniforms { float4 params; float4 texel; }; // params: threshold, knee, -, -; texel: source texel xy

fragment half4 fs_bright(VOut in [[stage_in]], texture2d<half> src [[texture(0)]], constant BloomUniforms& u [[buffer(0)]]) {
    float2 t = u.texel.xy;
    float3 c = float3(src.sample(sLinear, in.uv + float2(-t.x, -t.y)).rgb + src.sample(sLinear, in.uv + float2(t.x, -t.y)).rgb +
                      src.sample(sLinear, in.uv + float2(-t.x, t.y)).rgb + src.sample(sLinear, in.uv + float2(t.x, t.y)).rgb) * 0.25;
    float l = luma(c);
    float knee = u.params.y;
    float soft = clamp(l - u.params.x + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contrib = max(soft, l - u.params.x) / max(l, 1e-4);
    return half4(half3(c * contrib), 1.0h);
}

fragment half4 fs_down(VOut in [[stage_in]], texture2d<half> src [[texture(0)]], constant BloomUniforms& u [[buffer(0)]]) {
    float2 t = u.texel.xy;
    float3 c = float3(src.sample(sLinear, in.uv).rgb) * 4.0;
    c += float3(src.sample(sLinear, in.uv + float2(-t.x, -t.y)).rgb);
    c += float3(src.sample(sLinear, in.uv + float2(t.x, -t.y)).rgb);
    c += float3(src.sample(sLinear, in.uv + float2(-t.x, t.y)).rgb);
    c += float3(src.sample(sLinear, in.uv + float2(t.x, t.y)).rgb);
    return half4(half3(c / 8.0), 1.0h);
}

fragment half4 fs_up(VOut in [[stage_in]], texture2d<half> src [[texture(0)]], constant BloomUniforms& u [[buffer(0)]]) {
    float2 t = u.texel.xy;
    float3 c = float3(0.0);
    c += float3(src.sample(sLinear, in.uv + float2(-t.x * 2, 0)).rgb);
    c += float3(src.sample(sLinear, in.uv + float2(-t.x, t.y)).rgb) * 2.0;
    c += float3(src.sample(sLinear, in.uv + float2(0, t.y * 2)).rgb);
    c += float3(src.sample(sLinear, in.uv + float2(t.x, t.y)).rgb) * 2.0;
    c += float3(src.sample(sLinear, in.uv + float2(t.x * 2, 0)).rgb);
    c += float3(src.sample(sLinear, in.uv + float2(t.x, -t.y)).rgb) * 2.0;
    c += float3(src.sample(sLinear, in.uv + float2(0, -t.y * 2)).rgb);
    c += float3(src.sample(sLinear, in.uv + float2(-t.x, -t.y)).rgb) * 2.0;
    return half4(half3(c / 12.0), 1.0h);
}

// ---------------------------------------------------------------- light shafts

struct ShaftUniforms { float4 light; float4 params; }; // light.xy screen uv of the lamp; params: density, decay, weight, samples

fragment half4 fs_shafts(VOut in [[stage_in]], texture2d<half> bright [[texture(0)]], constant ShaftUniforms& u [[buffer(0)]]) {
    float2 uv = in.uv;
    float2 delta = (uv - u.light.xy) * (u.params.x / u.params.w);
    float illum = 1.0;
    float3 acc = float3(0.0);
    float jitter = ign(in.position.xy);
    uv -= delta * jitter;
    for (int i = 0; i < int(u.params.w); i++) {
        uv -= delta;
        float3 s = float3(bright.sample(sLinear, uv).rgb);
        acc += s * illum * u.params.z;
        illum *= u.params.y;
    }
    return half4(half3(acc), 1.0h);
}

// ---------------------------------------------------------------- composite + grade

struct CompositeUniforms {
    float4 fx;      // aoStrength, bloom, shafts, chromatic
    float4 grade;   // exposure (stops), contrast, saturation, toning
    float4 film;    // vignette, grain, time, aspect
    float4 shadowTint;
    float4 highlightTint;
    float4 lampColor;
};

fragment half4 fs_composite(VOut in [[stage_in]],
                            texture2d<half> src [[texture(0)]],
                            texture2d<half> ao [[texture(1)]],
                            texture2d<half> bloom [[texture(2)]],
                            texture2d<half> shafts [[texture(3)]],
                            constant CompositeUniforms& u [[buffer(0)]]) {
    float2 uv = in.uv;
    float2 dir = uv - 0.5;
    float ca = u.fx.w * dot(dir, dir);
    float3 c;
    c.r = src.sample(sLinear, uv - dir * ca).r;
    c.g = src.sample(sLinear, uv).g;
    c.b = src.sample(sLinear, uv + dir * ca).b;
    float a = float(ao.sample(sLinear, uv).r);
    c *= mix(1.0, a, u.fx.x);
    c += float3(bloom.sample(sLinear, uv).rgb) * u.fx.y;
    c += float3(shafts.sample(sLinear, uv).rgb) * u.fx.z * u.lampColor.rgb;

    c *= exp2(u.grade.x);
    float l = luma(c);
    c = mix(float3(l), c, u.grade.z);
    float shadowMask = 1.0 - smoothstep(0.0, 0.45, l);
    float highMask = smoothstep(0.45, 1.0, l);
    c = mix(c, c * u.shadowTint.rgb, shadowMask * u.grade.w);
    c = mix(c, c * u.highlightTint.rgb, highMask * u.grade.w);
    // filmic shoulder for highlights pushed by bloom, then a gentle S-curve
    c = c / (1.0 + max(c - 0.8, float3(0.0)) * 0.9);
    float3 cc = saturate(c);
    c = mix(c, cc * cc * (3.0 - 2.0 * cc), u.grade.y);

    float2 vd = dir * float2(u.film.w, 1.0);
    float vig = smoothstep(0.95, 0.2, length(vd));
    c *= mix(1.0, vig, u.film.x);

    float g = hash12(in.position.xy + fract(u.film.z * 7.13) * 917.0) - 0.5;
    c += g * u.film.y * (1.0 - 0.6 * luma(saturate(c)));
    return half4(half3(max(c, float3(0.0))), 1.0h);
}

// ---------------------------------------------------------------- FXAA + light sharpening

struct FXAAUniforms { float4 texel; float4 params; }; // params.x sharpen

fragment half4 fs_fxaa(VOut in [[stage_in]], texture2d<half> t [[texture(0)]], constant FXAAUniforms& u [[buffer(0)]]) {
    const float3 L = float3(0.299, 0.587, 0.114);
    float2 px = u.texel.xy;
    float2 uv = in.uv;
    float3 rgbNW = float3(t.sample(sLinear, uv + float2(-1, -1) * px).rgb);
    float3 rgbNE = float3(t.sample(sLinear, uv + float2(1, -1) * px).rgb);
    float3 rgbSW = float3(t.sample(sLinear, uv + float2(-1, 1) * px).rgb);
    float3 rgbSE = float3(t.sample(sLinear, uv + float2(1, 1) * px).rgb);
    float3 rgbM = float3(t.sample(sLinear, uv).rgb);
    float lNW = dot(rgbNW, L), lNE = dot(rgbNE, L), lSW = dot(rgbSW, L), lSE = dot(rgbSE, L), lM = dot(rgbM, L);
    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));
    float2 dir = float2(-((lNW + lNE) - (lSW + lSE)), ((lNW + lSW) - (lNE + lSE)));
    float reduce = max((lNW + lNE + lSW + lSE) * (0.25 / 8.0), 1.0 / 128.0);
    float rcpMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + reduce);
    dir = clamp(dir * rcpMin, float2(-8.0), float2(8.0)) * px;
    float3 rgbA = 0.5 * (float3(t.sample(sLinear, uv + dir * (1.0 / 3.0 - 0.5)).rgb) + float3(t.sample(sLinear, uv + dir * (2.0 / 3.0 - 0.5)).rgb));
    float3 rgbB = rgbA * 0.5 + 0.25 * (float3(t.sample(sLinear, uv + dir * -0.5).rgb) + float3(t.sample(sLinear, uv + dir * 0.5).rgb));
    float lB = dot(rgbB, L);
    float3 aa = (lB < lMin || lB > lMax) ? rgbA : rgbB;
    // contrast adaptive sharpening (very light) to keep type and edges crisp
    float3 blur = (rgbNW + rgbNE + rgbSW + rgbSE) * 0.25;
    float edge = saturate((lMax - lMin) * 4.0);
    float3 sharp = aa + (aa - blur) * u.params.x * (1.0 - edge);
    return half4(half3(max(sharp, float3(0.0))), 1.0h);
}

fragment half4 fs_copy(VOut in [[stage_in]], texture2d<half> t [[texture(0)]]) {
    return t.sample(sLinear, in.uv);
}
"""#
}
