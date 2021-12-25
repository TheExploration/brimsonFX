
/*
    Optical flow motion blur

    Special Thanks
        MartinBFFan and Pao on Discord for reporting bugs
        BSD for bug propaganda and helping to solve my issue

    Sources
        Angle-Retaining Chromaticity
            Title = "ARC: Angle-Retaining Chromaticity diagram for color constancy error analysis"
            Authors = Marco Buzzelli and Simone Bianco and Raimondo Schettini
            Year = 2020
            Link = http://www.ivl.disco.unimib.it/activities/arc/
*/

uniform float _Constraint <
    ui_type = "slider";
    ui_label = "Flow Smoothness";
    ui_tooltip = "Higher = Smoother flow";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.0;

uniform float _Scale <
    ui_type = "slider";
    ui_label = "Flow Scale";
    ui_tooltip = "Higher = More motion blur";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.0;

uniform float _Detail <
    ui_type = "slider";
    ui_label = "Mipmap Bias";
    ui_tooltip = "Higher = Less spatial noise";
    ui_min = 0.0;
    ui_max = 7.0;
> = 1.0;

uniform float _Blend <
    ui_type = "slider";
    ui_label = "Temporal Blending";
    ui_tooltip = "Higher = Less temporal noise";
    ui_min = 0.0;
    ui_max = 0.5;
> = 0.25;

uniform bool _FrameRateScaling <
    ui_type = "radio";
    ui_label = "Frame-Rate Scaling";
    ui_tooltip = "Enables frame-rate scaling";
> = false;

uniform float _TargetFrameRate <
    ui_type = "drag";
    ui_label = "Target Frame-Rate";
    ui_tooltip = "Targeted frame-rate";
> = 60.00;

uniform float _FrameTime < source = "frametime"; >;

#define HALF_SIZE uint2(BUFFER_WIDTH / 2, BUFFER_HEIGHT / 2)
#define BUFFER_SIZE uint2(128, 128)

texture2D _RenderColor : COLOR;

sampler2D _SampleColor
{
    Texture = _RenderColor;
    #if BUFFER_COLOR_BIT_DEPTH == 8
        SRGBTexture = TRUE;
    #endif
};

texture2D _RenderBuffer
{
    Width = HALF_SIZE.x;
    Height = HALF_SIZE.y;
    Format = RG16F;
    MipLevels = 8;
};

sampler2D _SampleBuffer
{
    Texture = _RenderBuffer;
    AddressU = MIRROR;
    AddressV = MIRROR;
};

texture2D _RenderData0
{
    Width = BUFFER_SIZE.x;
    Height = BUFFER_SIZE.y;
    Format = RG16F;
    MipLevels = 8;
};

sampler2D _SampleData0
{
    Texture = _RenderData0;
    AddressU = MIRROR;
    AddressV = MIRROR;
};

texture2D _RenderData1
{
    Width = BUFFER_SIZE.x;
    Height = BUFFER_SIZE.y;
    Format = RGBA16F;
    MipLevels = 8;
};

sampler2D _SampleData1
{
    Texture = _RenderData1;
    AddressU = MIRROR;
    AddressV = MIRROR;
};

texture2D _RenderData2
{
    Width = BUFFER_SIZE.x;
    Height = BUFFER_SIZE.y;
    Format = RG16F;
    MipLevels = 8;
};

sampler2D _SampleData2
{
    Texture = _RenderData2;
    AddressU = MIRROR;
    AddressV = MIRROR;
};

texture2D _RenderOpticalFlow_MotionBlur
{
    Width = BUFFER_SIZE.x;
    Height = BUFFER_SIZE.y;
    Format = RG16F;
};

sampler2D _SampleOpticalFlow
{
    Texture = _RenderOpticalFlow_MotionBlur;
    AddressU = MIRROR;
    AddressV = MIRROR;
};

/* [Vertex Shaders] */

void PostProcessVS(in uint ID : SV_VERTEXID, inout float4 Position : SV_POSITION, inout float2 TexCoord : TEXCOORD0)
{
    TexCoord.x = (ID == 2) ? 2.0 : 0.0;
    TexCoord.y = (ID == 1) ? 2.0 : 0.0;
    Position = float4(TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

static const float KernelSize = 14;

float GaussianWeight(const int Position)
{
    const float Sigma = KernelSize / 3.0;
    const float Pi = 3.1415926535897932384626433832795f;
    float Output = rsqrt(2.0 * Pi * (Sigma * Sigma));
    return Output * exp(-(Position * Position) / (2.0 * (Sigma * Sigma)));
}

void OutputOffsets(in float2 TexCoord, inout float4 Offsets[7], float2 Direction)
{
    int OutputIndex = 0;
    float PixelIndex = 1.0;

    while(OutputIndex < 7)
    {
        float Offset1 = PixelIndex;
        float Offset2 = PixelIndex + 1.0;
        float Weight1 = GaussianWeight(Offset1);
        float Weight2 = GaussianWeight(Offset2);
        float WeightL = Weight1 + Weight2;
        float Offset = ((Offset1 * Weight1) + (Offset2 * Weight2)) / WeightL;
        Offsets[OutputIndex] = TexCoord.xyxy + float2(Offset, -Offset).xxyy * Direction.xyxy;

        OutputIndex += 1;
        PixelIndex += 2.0;
    }
}

void HorizontalBlurVS(in uint ID : SV_VERTEXID, inout float4 Position : SV_POSITION, inout float2 TexCoord : TEXCOORD0, inout float4 Offsets[7] : TEXCOORD1)
{
    PostProcessVS(ID, Position, TexCoord);
    OutputOffsets(TexCoord, Offsets, float2(1.0 / BUFFER_SIZE.x, 0.0));
}

void VerticalBlurVS(in uint ID : SV_VERTEXID, inout float4 Position : SV_POSITION, inout float2 TexCoord : TEXCOORD0, inout float4 Offsets[7] : TEXCOORD1)
{
    PostProcessVS(ID, Position, TexCoord);
    OutputOffsets(TexCoord, Offsets, float2(0.0, 1.0 / BUFFER_SIZE.y));
}

void DerivativesVS(in uint ID : SV_VERTEXID, inout float4 Position : SV_POSITION, inout float4 TexCoord : TEXCOORD0)
{
    const float2 PixelSize = 0.5 / BUFFER_SIZE;
    const float4 PixelOffset = float4(PixelSize, -PixelSize);
    float2 TexCoord0 = 0.0;
    PostProcessVS(ID, Position, TexCoord0);
    TexCoord = TexCoord0.xyxy + PixelOffset;
}

/* [ Pixel Shaders ] */

float4 GaussianBlur(sampler2D Source, float2 TexCoord, float4 Offsets[7])
{
    float Total = GaussianWeight(0.0);
    float4 Output = tex2D(Source, TexCoord) * GaussianWeight(0.0);

    int Index = 0;
    float PixelIndex = 1.0;

    while(Index < 7)
    {
        float Offset1 = PixelIndex;
        float Offset2 = PixelIndex + 1.0;
        float Weight1 = GaussianWeight(Offset1);
        float Weight2 = GaussianWeight(Offset2);
        float WeightL = Weight1 + Weight2;
        Output += tex2D(Source, Offsets[Index].xy) * WeightL;
        Output += tex2D(Source, Offsets[Index].zw) * WeightL;
        Total += 2.0 * WeightL;
        Index += 1.0;
        PixelIndex += 2.0;
    }

    return Output / Total;
}

void CopyPS0(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float2 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = tex2D(_SampleData0, TexCoord).rg;
}

void NormalizePS(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float2 OutputColor0 : SV_TARGET0)
{
    float3 Color = max(tex2D(_SampleColor, TexCoord).rgb, 1e-7);

    // Angle-Retaining Chromaticity (Optimized for GPU)
    float2 AlphaA;
    AlphaA.x = dot(Color.gb, float2(sqrt(3.0), -sqrt(3.0)));
    AlphaA.y = dot(Color, float3(2.0, -1.0, -1.0));
    float AlphaR = acos(dot(Color, 1.0) / (sqrt(3.0) * length(Color)));
    float AlphaC = AlphaR * rsqrt(dot(AlphaA, AlphaA));
    float2 Alpha = AlphaC * AlphaA.yx;

    float2 AlphaMin, AlphaMax;
    AlphaMin.y = -(sqrt(3.0) / 2.0) * acos(rsqrt(3.0));
    AlphaMax.y = (sqrt(3.0) / 2.0) * acos(rsqrt(3.0));
    AlphaMin.x = -acos(sqrt(2.0 / 3.0));
    AlphaMax.x = AlphaMin.x + (AlphaMax.y - AlphaMin.y);
    Alpha.xy = (Alpha.xy - AlphaMin.xy) / (AlphaMax.xy - AlphaMin.xy);
    OutputColor0 = Alpha.xy;
}

void CopyPS1(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float2 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = tex2D(_SampleBuffer, TexCoord).rg;
}

void HorizontalBlurPS0(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = GaussianBlur(_SampleData0, TexCoord, Offsets).xyz;
    OutputColor0.a = 1.0;
}

void VerticalBlurPS0(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = GaussianBlur(_SampleData1, TexCoord, Offsets);
}

void DerivativesPS(float4 Position : SV_POSITION, float4 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_TARGET0)
{
    float2 Sample0 = tex2D(_SampleData0, TexCoord.zy).xy; // (-x, +y)
    float2 Sample1 = tex2D(_SampleData0, TexCoord.xy).xy; // (+x, +y)
    float2 Sample2 = tex2D(_SampleData0, TexCoord.zw).xy; // (-x, -y)
    float2 Sample3 = tex2D(_SampleData0, TexCoord.xw).xy; // (+x, -y)
    OutputColor0.xz = (Sample3 + Sample1) - (Sample2 + Sample0);
    OutputColor0.yw = (Sample2 + Sample3) - (Sample0 + Sample1);
    OutputColor0 *= 4.0;
}

void OpticalFlowPS(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_TARGET0)
{
    float2 RedBlack;
    RedBlack.x = frac(dot(Position.xy, 0.5)) * 2.0;
    RedBlack.y = 1.0 - RedBlack.x;
    const float MaxLevel = 6.5;
    float4 OpticalFlow;
    float2 Smoothness;
    float2 Value;

    [unroll] for(float Level = MaxLevel; Level > 0.0; Level--)
    {
        const float Lambda = max(ldexp(_Constraint * 1e-3, Level - MaxLevel), 1e-7);

        // .xy = Normalized Red Channel (x, y)
        // .zw = Normalized Green Channel (x, y)
        float4 SampleIxy = tex2Dlod(_SampleData1, float4(TexCoord, 0.0, Level)).xyzw;
        float4 RedIxy = SampleIxy * RedBlack.x;
        float4 BlackIxy = SampleIxy * RedBlack.y;

        // .xy = Current frame (r, g)
        // .zw = Previous frame (r, g)
        float4 SampleFrames;
        SampleFrames.xy = tex2Dlod(_SampleData0, float4(TexCoord, 0.0, Level)).rg;
        SampleFrames.zw = tex2Dlod(_SampleData2, float4(TexCoord, 0.0, Level)).rg;
        float2 Iz = SampleFrames.xy - SampleFrames.zw;

        // Calculate red points
        Value.r = dot(RedIxy.xy, OpticalFlow.xy);
        Value.g = dot(RedIxy.zw, OpticalFlow.zw);
        Value.rg = (Iz.xy * RedBlack.xx) + Value.rg;
        Smoothness.r = dot(RedIxy.xy, RedIxy.xy) + Lambda;
        Smoothness.g = dot(RedIxy.zw, RedIxy.zw) + Lambda;
        OpticalFlow -= (RedIxy.xyzw * (Value.rrgg / Smoothness.rrgg));

        // Calculate black points
        Value.r = dot(BlackIxy.xy, OpticalFlow.xy);
        Value.g = dot(BlackIxy.zw, OpticalFlow.zw);
        Value.rg = (Iz.xy * RedBlack.yy) + Value.rg;
        Smoothness.r = dot(BlackIxy.xy, BlackIxy.xy) + Lambda;
        Smoothness.g = dot(BlackIxy.zw, BlackIxy.zw) + Lambda;
        OpticalFlow -= (BlackIxy.xyzw * (Value.rrgg / Smoothness.rrgg));
    }

    OutputColor0.xy = OpticalFlow.xy + OpticalFlow.zw;
    OutputColor0.ba = _Blend;
}

void HorizontalBlurPS1(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = GaussianBlur(_SampleOpticalFlow, TexCoord, Offsets);
}

void VerticalBlurPS1(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = GaussianBlur(_SampleData1, TexCoord, Offsets);
}

void OutputPS(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target)
{
    const int Samples = 4;
    float Noise = frac(52.9829189 * frac(dot(Position.xy, float2(0.06711056, 0.00583715))));
    float FrameTimeRatio = _TargetFrameRate / (1e+3 / _FrameTime);
    float2 Velocity = (tex2Dlod(_SampleData2, float4(TexCoord, 0.0, _Detail)).xy / BUFFER_SIZE) * _Scale;
    Velocity /= (_FrameRateScaling) ? FrameTimeRatio : 1.0;

    for(int k = 0; k < Samples; ++k)
    {
        float2 Offset = Velocity * (Noise + k);
        OutputColor0 += tex2D(_SampleColor, (TexCoord + Offset));
        OutputColor0 += tex2D(_SampleColor, (TexCoord - Offset));
    }

    OutputColor0 /= (Samples * 2.0);
}

technique cMotionBlur
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = CopyPS0;
        RenderTarget0 = _RenderData2;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = NormalizePS;
        RenderTarget0 = _RenderBuffer;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = CopyPS1;
        RenderTarget0 = _RenderData0;
    }


    pass
    {
        VertexShader = HorizontalBlurVS;
        PixelShader = HorizontalBlurPS0;
        RenderTarget0 = _RenderData1;
    }

    pass
    {
        VertexShader = VerticalBlurVS;
        PixelShader = VerticalBlurPS0;
        RenderTarget0 = _RenderData0;
    }

    pass
    {
        VertexShader = DerivativesVS;
        PixelShader = DerivativesPS;
        RenderTarget0 = _RenderData1;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = OpticalFlowPS;
        RenderTarget0 = _RenderOpticalFlow_MotionBlur;
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = INVSRCALPHA;
        DestBlend = SRCALPHA;
    }

    pass
    {
        VertexShader = HorizontalBlurVS;
        PixelShader = HorizontalBlurPS1;
        RenderTarget0 = _RenderData1;
    }

    pass
    {
        VertexShader = VerticalBlurVS;
        PixelShader = VerticalBlurPS1;
        RenderTarget0 = _RenderData2;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = OutputPS;
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBWriteEnable = TRUE;
        #endif
    }
}
