//
//  Shaders.metal
//  Moonlight
//
//  Metal shaders for YUV → RGB conversion.
//  Supports BT.601, BT.709, BT.2020 color spaces, 8-bit and 10-bit.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Full-screen triangle (no vertex buffer needed)
vertex VertexOut vertexPassthrough(uint vertexID [[vertex_id]]) {
    VertexOut out;

    // Generate a full-screen triangle from vertex ID
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

// BT.601 limited range (SDTV)
constant float3x3 bt601Matrix = float3x3(
    float3(1.164,  1.164, 1.164),
    float3(0.000, -0.392, 2.017),
    float3(1.596, -0.813, 0.000)
);

// BT.709 limited range (HDTV)
constant float3x3 bt709Matrix = float3x3(
    float3(1.164,  1.164, 1.164),
    float3(0.000, -0.213, 2.112),
    float3(1.793, -0.533, 0.000)
);

// BT.2020 limited range (UHDTV / HDR)
constant float3x3 bt2020Matrix = float3x3(
    float3(1.164,  1.164, 1.164),
    float3(0.000, -0.187, 2.142),
    float3(1.679, -0.650, 0.000)
);

// BT.601 full range
constant float3x3 bt601FullMatrix = float3x3(
    float3(1.000,  1.000, 1.000),
    float3(0.000, -0.344, 1.772),
    float3(1.402, -0.714, 0.000)
);

// BT.709 full range
constant float3x3 bt709FullMatrix = float3x3(
    float3(1.000,  1.000, 1.000),
    float3(0.000, -0.187, 1.856),
    float3(1.575, -0.468, 0.000)
);

// BT.2020 full range
constant float3x3 bt2020FullMatrix = float3x3(
    float3(1.000,  1.000, 1.000),
    float3(0.000, -0.165, 1.881),
    float3(1.475, -0.572, 0.000)
);

struct FragmentParams {
    int colorSpace;     // 601, 709, 2020
    int isFullRange;    // 0 = limited, 1 = full
    int is10Bit;        // 0 = 8-bit, 1 = 10-bit
};

fragment float4 fragmentYUVtoRGB(VertexOut in [[stage_in]],
                                  texture2d<float> lumaTexture [[texture(0)]],
                                  texture2d<float> chromaTexture [[texture(1)]],
                                  constant FragmentParams &params [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    float y = lumaTexture.sample(textureSampler, in.texCoord).r;
    float2 uv = chromaTexture.sample(textureSampler, in.texCoord).rg;

    // Offset Y and UV for limited/full range
    float3 yuv;
    if (params.isFullRange) {
        yuv = float3(y, uv.x - 0.5, uv.y - 0.5);
    } else {
        if (params.is10Bit) {
            yuv = float3(y - (64.0 / 1023.0), uv.x - 0.5, uv.y - 0.5);
        } else {
            yuv = float3(y - (16.0 / 255.0), uv.x - 0.5, uv.y - 0.5);
        }
    }

    float3 rgb;
    if (params.isFullRange) {
        if (params.colorSpace == 601) {
            rgb = bt601FullMatrix * yuv;
        } else if (params.colorSpace == 2020) {
            rgb = bt2020FullMatrix * yuv;
        } else {
            rgb = bt709FullMatrix * yuv;
        }
    } else {
        if (params.colorSpace == 601) {
            rgb = bt601Matrix * yuv;
        } else if (params.colorSpace == 2020) {
            rgb = bt2020Matrix * yuv;
        } else {
            rgb = bt709Matrix * yuv;
        }
    }

    return float4(saturate(rgb), 1.0);
}
