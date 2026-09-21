#include "ReShade.fxh"

static const float NMH_VIGNETTE_STRENGTH = 0.12;
static const float NMH_VIGNETTE_START    = 0.25;
static const float NMH_VIGNETTE_END      = 1.15;

float4 NMH_VignettePS(
    float4 position : SV_Position,
    float2 texcoord : TEXCOORD
) : SV_Target {
    float4 color = tex2D(ReShade::BackBuffer, texcoord);

    float2 centered = texcoord * 2.0 - 1.0;
    centered.x *= 0.78;

    float distanceFromCenter = dot(centered, centered);
    float vignette = smoothstep(
        NMH_VIGNETTE_START,
        NMH_VIGNETTE_END,
        distanceFromCenter
    );

    color.rgb *= 1.0 - vignette * NMH_VIGNETTE_STRENGTH;
    return color;
}

technique NMH_Vignette {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = NMH_VignettePS;
    }
}
