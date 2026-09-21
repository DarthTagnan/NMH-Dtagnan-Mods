#include "ReShade.fxh"

static const float NMH_BLOOM_THRESHOLD = 0.78;
static const float NMH_BLOOM_STRENGTH  = 0.10;
static const float NMH_BLOOM_RADIUS    = 2.5;

float3 NMH_ExtractBloom(float3 color) {
    float brightness = max(color.r, max(color.g, color.b));

    float contribution = saturate(
        (brightness - NMH_BLOOM_THRESHOLD) /
        (1.0 - NMH_BLOOM_THRESHOLD)
    );

    return color * contribution;
}

float4 NMH_BloomPS(
    float4 position : SV_Position,
    float2 texcoord : TEXCOORD
) : SV_Target {
    float4 original = tex2D(ReShade::BackBuffer, texcoord);

    float2 pixel = ReShade::PixelSize * NMH_BLOOM_RADIUS;
    float3 glow = 0.0;

    glow += NMH_ExtractBloom(
        tex2D(ReShade::BackBuffer, texcoord + float2( pixel.x, 0.0)).rgb
    );
    glow += NMH_ExtractBloom(
        tex2D(ReShade::BackBuffer, texcoord + float2(-pixel.x, 0.0)).rgb
    );
    glow += NMH_ExtractBloom(
        tex2D(ReShade::BackBuffer, texcoord + float2(0.0,  pixel.y)).rgb
    );
    glow += NMH_ExtractBloom(
        tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -pixel.y)).rgb
    );

    glow += NMH_ExtractBloom(
        tex2D(ReShade::BackBuffer, texcoord + pixel).rgb
    );
    glow += NMH_ExtractBloom(
        tex2D(ReShade::BackBuffer, texcoord - pixel).rgb
    );
    glow += NMH_ExtractBloom(
        tex2D(
            ReShade::BackBuffer,
            texcoord + float2(pixel.x, -pixel.y)
        ).rgb
    );
    glow += NMH_ExtractBloom(
        tex2D(
            ReShade::BackBuffer,
            texcoord + float2(-pixel.x, pixel.y)
        ).rgb
    );

    glow *= 0.125;

    original.rgb = saturate(
        original.rgb + glow * NMH_BLOOM_STRENGTH
    );

    return original;
}

technique NMH_Bloom {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = NMH_BloomPS;
    }
}
