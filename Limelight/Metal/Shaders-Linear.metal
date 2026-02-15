//
//  Shaders-Linear.metal
//  Moonlight
//
//  Linear color space variant for HDR content.
//  Uses PQ (SMPTE ST 2084) transfer function for HDR tone mapping.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOutLinear {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOutLinear vertexPassthroughLinear(uint vertexID [[vertex_id]]) {
    VertexOutLinear out;

    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    float2 texCoords[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// BT.2020 non-constant luminance matrix (limited range)
constant float3x3 bt2020NCLMatrix = float3x3(
    float3(1.164,  1.164, 1.164),
    float3(0.000, -0.187, 2.142),
    float3(1.679, -0.650, 0.000)
);

// PQ constants (SMPTE ST 2084)
constant float pq_m1 = 0.1593017578125;
constant float pq_m2 = 78.84375;
constant float pq_c1 = 0.8359375;
constant float pq_c2 = 18.8515625;
constant float pq_c3 = 18.6875;

float3 pqToLinear(float3 pq) {
    float3 p = pow(max(pq, 0.0), 1.0 / pq_m2);
    float3 num = max(p - pq_c1, 0.0);
    float3 den = pq_c2 - pq_c3 * p;
    // 10000 nits normalization
    return pow(num / den, 1.0 / pq_m1) * 10000.0;
}

// Simple Reinhard tone mapping for HDR → SDR display
float3 reinhardTonemap(float3 color, float maxNits) {
    // Normalize to 0-1 range based on max display nits
    float3 normalized = color / maxNits;
    return normalized / (1.0 + normalized);
}

struct LinearFragmentParams {
    int colorSpace;
    int isFullRange;
    int is10Bit;
    float maxDisplayNits;  // Target display max brightness
};

fragment float4 fragmentYUVtoRGBLinear(VertexOutLinear in [[stage_in]],
                                        texture2d<float> lumaTexture [[texture(0)]],
                                        texture2d<float> chromaTexture [[texture(1)]],
                                        constant LinearFragmentParams &params [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    float y = lumaTexture.sample(textureSampler, in.texCoord).r;
    float2 uv = chromaTexture.sample(textureSampler, in.texCoord).rg;

    float3 yuv;
    if (params.is10Bit) {
        yuv = float3(y - (64.0 / 1023.0), uv.x - 0.5, uv.y - 0.5);
    } else {
        yuv = float3(y - (16.0 / 255.0), uv.x - 0.5, uv.y - 0.5);
    }

    float3 rgb = bt2020NCLMatrix * yuv;
    rgb = saturate(rgb);

    // Apply PQ EOTF to get linear light values (in nits)
    float3 linearLight = pqToLinear(rgb);

    // Tone map to display range
    float maxNits = params.maxDisplayNits > 0.0 ? params.maxDisplayNits : 1000.0;
    float3 tonemapped = reinhardTonemap(linearLight, maxNits);

    return float4(tonemapped, 1.0);
}
