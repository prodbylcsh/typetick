/// Source of the RealityKit surface shader (dust, smudges, micro detail, clear
/// coat). It is compiled at runtime by the system Metal compiler, so building
/// the package does not need Xcode's separately downloaded Metal toolchain.
/// `Shaders/Surface.metal` is the same code, kept for editing with syntax
/// highlighting; it is excluded from the build.
enum SurfaceShaderSource {
    static let source = #"""
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Procedural wear for every part of the machine, evaluated in object space so
// it sticks to the part while it moves:
//   custom.x  dust that settles on upward facing surfaces
//   custom.y  smudges / fingerprints (roughness + slight darkening)
//   custom.z  micro surface variation (roughness breakup + micro normal)
//   custom.w  clear coat amount (enamel, bakelite, lacquer)

static float hash31(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static float vnoise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(i + float3(0, 0, 0)), hash31(i + float3(1, 0, 0)), f.x),
                   mix(hash31(i + float3(0, 1, 0)), hash31(i + float3(1, 1, 0)), f.x), f.y),
               mix(mix(hash31(i + float3(0, 0, 1)), hash31(i + float3(1, 0, 1)), f.x),
                   mix(hash31(i + float3(0, 1, 1)), hash31(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

static float fbm(float3 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += vnoise(p) * a;
        p = p * 2.03 + float3(1.7, 9.2, 3.1);
        a *= 0.5;
    }
    return s / 0.9375;
}

[[visible]]
void typetickSurface(realitykit::surface_parameters params)
{
    constexpr sampler samp(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
    auto geo = params.geometry();
    auto mat = params.material_constants();
    auto tex = params.textures();

    float2 uv = geo.uv0();
    uv.y = 1.0 - uv.y;

    half3 base = half3(mat.base_color_tint()) * tex.base_color().sample(samp, uv).rgb;
    float rough = float(mat.roughness_scale()) * float(tex.roughness().sample(samp, uv).r);
    float metal = float(mat.metallic_scale()) * float(tex.metallic().sample(samp, uv).r);

    float4 custom = params.uniforms().custom_parameter();
    float3 p = geo.model_position() * 160.0;     // ~6 mm features
    float3 nW = normalize(geo.normal());

    float broad = fbm(p * 0.35);
    float fine = fbm(p * 4.0);

    // dust: only on faces that look up, patchy, heavier in sheltered (low frequency) areas
    float up = smoothstep(0.45, 0.95, nW.y);
    float dust = saturate(custom.x * up * smoothstep(0.38, 0.75, broad + 0.25 * fine));

    // smudges: soft blobs that change roughness, like fingers on chrome and keys
    float sm = smoothstep(0.58, 0.82, fbm(p * 0.22 + 31.0));
    float smudge = custom.y * sm;

    rough = rough + (fine - 0.5) * 0.10 * custom.z + smudge * 0.22;
    base = base * half(1.0 - smudge * 0.12);
    base = mix(base, half3(0.47, 0.45, 0.42), half(dust * 0.85));
    rough = mix(rough, 0.92, dust);
    metal = mix(metal, 0.0, dust);

    // micro normal: tiny tilt from the fine noise (orange peel / brushing / grain)
    float e = 0.35 * custom.z;
    float3 nT = normalize(float3((fbm(p * 6.0 + 3.1) - 0.5) * e, (fbm(p * 6.0 + 7.7) - 0.5) * e, 1.0));

    auto surface = params.surface();
    surface.set_base_color(base);
    surface.set_roughness(half(clamp(rough, 0.03, 1.0)));
    surface.set_metallic(half(saturate(metal)));
    surface.set_normal(nT);
    surface.set_ambient_occlusion(half(1.0));
    surface.set_specular(half(0.5));
    surface.set_clearcoat(half(custom.w * (1.0 - dust)));
    surface.set_clearcoat_roughness(half(0.04 + smudge * 0.25));
}
"""#
}
