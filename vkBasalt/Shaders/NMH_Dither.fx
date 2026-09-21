#include "ReShade.fxh"

static const float NMH_DITHER_STRENGTH = 0.50 / 255.0;

float NMH_Hash(float2 position) {
    return frac(
        sin(dot(position, float2(12.9898, 78.233))) *
        43758.5453
    );
}

float4 NMH_DitherPS(
    float4 position : SV_Position,
    float2 texcoord : TEXCOORD
) : SV_Target {
    float4 color = tex2D(ReShade::BackBuffer, texcoord);

    float noise = NMH_Hash(floor(position.xy)) - 0.5;
    color.rgb = saturate(
        color.rgb + noise * NMH_DITHER_STRENGTH
    );

    return color;
}

technique NMH_Dither {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = NMH_DitherPS;
    }
}
