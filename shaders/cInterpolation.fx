
/*
    Quasi frame-rate interpolation shader
        Note: Make better masking
*/

namespace Interpolation
{
    uniform float _Blend <
        ui_type = "slider";
        ui_label = "Temporal Blending";
        ui_tooltip = "Higher = Less temporal noise";
        ui_min = 0.0;
        ui_max = 1.0;
    > = 0.25;

    uniform float _Constraint <
        ui_type = "slider";
        ui_label = "Constraint";
        ui_tooltip = "Higher = Smoother flow";
    > = 0.5;

    uniform float _Detail <
        ui_type = "slider";
        ui_label = "Mipmap Bias";
        ui_tooltip = "Higher = Less spatial noise";
        ui_max = 7.0;
    > = 0.0;

    #define BUFFER_SIZE uint2(128, 128)

    texture2D _RenderColor : COLOR;

    sampler2D _SampleColor
    {
        Texture = _RenderColor;
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBTexture = TRUE;
        #endif
    };

    texture2D _RenderFrame0
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
        MipLevels = 8;
    };

    sampler2D _SampleFrame0
    {
        Texture = _RenderFrame0;
        AddressU = MIRROR;
        AddressV = MIRROR;
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBTexture = TRUE;
        #endif
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

    texture2D _RenderOpticalFlow
    {
        Width = BUFFER_SIZE.x;
        Height = BUFFER_SIZE.y;
        Format = RG16F;
    };

    sampler2D _SampleOpticalFlow
    {
        Texture = _RenderOpticalFlow;
        AddressU = MIRROR;
        AddressV = MIRROR;
    };

    texture2D _RenderFrame1
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };

    sampler2D _SampleFrame1
    {
        Texture = _RenderFrame1;
        AddressU = MIRROR;
        AddressV = MIRROR;
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBTexture = TRUE;
        #endif
    };

    /* [Vertex Shaders] */

    void PostProcessVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float2 TexCoord : TEXCOORD0)
    {
        TexCoord.x = (ID == 2) ? 2.0 : 0.0;
        TexCoord.y = (ID == 1) ? 2.0 : 0.0;
        Position = float4(TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

    static const float KernelSize = 14;

    float GaussianWeight(const int PixelPosition)
    {
        const float Sigma = KernelSize / 3.0;
        const float Pi = 3.1415926535897932384626433832795f;
        float Output = rsqrt(2.0 * Pi * (Sigma * Sigma));
        return Output * exp(-(PixelPosition * PixelPosition) / (2.0 * (Sigma * Sigma)));
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

    void HorizontalBlurVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float2 TexCoord : TEXCOORD0, out float4 Offsets[7] : TEXCOORD1)
    {
        PostProcessVS(ID, Position, TexCoord);
        OutputOffsets(TexCoord, Offsets, float2(1.0 / BUFFER_SIZE.x, 0.0));
    }

    void VerticalBlurVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float2 TexCoord : TEXCOORD0, out float4 Offsets[7] : TEXCOORD1)
    {
        PostProcessVS(ID, Position, TexCoord);
        OutputOffsets(TexCoord, Offsets, float2(0.0, 1.0 / BUFFER_SIZE.y));
    }

    void DerivativesVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float4 TexCoord : TEXCOORD0)
    {
        const float2 PixelSize = 0.5 / BUFFER_SIZE;
        const float4 PixelOffset = float4(PixelSize, -PixelSize);
        float2 TexCoord0 = 0.0;
        PostProcessVS(ID, Position, TexCoord0);
        TexCoord = TexCoord0.xyxy + PixelOffset;
    }

    /* [Pixel Shaders] */

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

    void CopyPS0(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float2 OutputColor0 : SV_Target0)
    {
        OutputColor0 = tex2D(_SampleData0, TexCoord).rg;
    }

    void CopyPS1(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
    {
        OutputColor0 = tex2D(_SampleColor, TexCoord);
    }

    void NormalizePS(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float2 OutputColor0 : SV_Target0)
    {
        float3 Color = tex2D(_SampleFrame0, TexCoord).rgb;
        OutputColor0 = saturate(Color.xy / dot(Color, 1.0));
    }

    void HorizontalBlurPS0(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, in float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_Target0)
    {
        OutputColor0 = GaussianBlur(_SampleData0, TexCoord, Offsets).xyz;
        OutputColor0.a = 1.0;
    }

    void VerticalBlurPS0(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, in float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_Target0)
    {
        OutputColor0 = GaussianBlur(_SampleData1, TexCoord, Offsets);
    }

    void DerivativesPS(in float4 Position : SV_Position, in float4 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
    {
        float2 Sample0 = tex2D(_SampleData0, TexCoord.zy).xy; // (-x, +y)
        float2 Sample1 = tex2D(_SampleData0, TexCoord.xy).xy; // (+x, +y)
        float2 Sample2 = tex2D(_SampleData0, TexCoord.zw).xy; // (-x, -y)
        float2 Sample3 = tex2D(_SampleData0, TexCoord.xw).xy; // (+x, -y)
        OutputColor0.xz = (Sample3 + Sample1) - (Sample2 + Sample0);
        OutputColor0.yw = (Sample2 + Sample3) - (Sample0 + Sample1);
        OutputColor0 *= 4.0;
    }

    void OpticalFlowPS(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
    {
        const float MaxLevel = 6.5;
        float4 OpticalFlow;
        float2 Smoothness;
        float2 Value;

        [unroll] for(float Level = MaxLevel; Level > 0.0; Level--)
        {
            const float Lambda = max(ldexp(_Constraint * 1e-5, Level - MaxLevel), 1e-7);

            // .xy = Normalized Red Channel (x, y)
            // .zw = Normalized Green Channel (x, y)
            float4 SampleIxy = tex2Dlod(_SampleData1, float4(TexCoord, 0.0, Level)).xyzw;

            // .xy = Current frame (r, g)
            // .zw = Previous frame (r, g)
            float4 SampleFrames;
            SampleFrames.xy = tex2Dlod(_SampleData0, float4(TexCoord, 0.0, Level)).rg;
            SampleFrames.zw = tex2Dlod(_SampleData2, float4(TexCoord, 0.0, Level)).rg;
            float2 Iz = SampleFrames.xy - SampleFrames.zw;

            Smoothness.r = dot(SampleIxy.xy, SampleIxy.xy) + Lambda;
            Smoothness.g = dot(SampleIxy.zw, SampleIxy.zw) + Lambda;
            Smoothness.rg = 1.0 / Smoothness.rg;

            Value.r = dot(SampleIxy.xy, OpticalFlow.xy) + Iz.r;
            Value.g = dot(SampleIxy.zw, OpticalFlow.zw) + Iz.g;
            OpticalFlow.xz = OpticalFlow.xz - (SampleIxy.xz * (Value.rg * Smoothness.rg));

            Value.r = dot(SampleIxy.xy, OpticalFlow.xy) + Iz.r;
            Value.g = dot(SampleIxy.zw, OpticalFlow.zw) + Iz.g;
            OpticalFlow.yw = OpticalFlow.yw - (SampleIxy.yw * (Value.rg * Smoothness.rg));
        }

        OutputColor0.xy = OpticalFlow.xy + OpticalFlow.zw;
        OutputColor0.ba = _Blend;
    }

    void HorizontalBlurPS1(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, in float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_Target0)
    {
        OutputColor0 = GaussianBlur(_SampleOpticalFlow, TexCoord, Offsets);
    }

    void VerticalBlurPS1(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, in float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_Target0)
    {
        OutputColor0 = GaussianBlur(_SampleData1, TexCoord, Offsets);
    }

    float4 Med3(float4 x, float4 y, float4 z)
    {
        return max(min(x, y), min(max(x, y), z));
    }

    void InterpolatePS(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
    {
        float2 MotionVectors = tex2Dlod(_SampleData2, float4(TexCoord, 0.0, _Detail)).xy / BUFFER_SIZE;
        float4 FrameF = tex2D(_SampleFrame1, TexCoord + MotionVectors);
        float4 FrameB = tex2D(_SampleFrame0, TexCoord - MotionVectors);
        float4 FrameP = tex2D(_SampleFrame1, TexCoord);
        float4 FrameC = tex2D(_SampleFrame0, TexCoord);
        float4 FrameA = lerp(FrameC, FrameP, 64.0 / 256.0);
        OutputColor0 = Med3(FrameA, FrameF, FrameB);
    }

    void CopyPS2(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
    {
        OutputColor0 = tex2D(_SampleFrame0, TexCoord);
    }

    technique cInterpolation
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
            PixelShader = CopyPS1;
            RenderTarget0 = _RenderFrame0;
            #if BUFFER_COLOR_BIT_DEPTH == 8
                SRGBWriteEnable = TRUE;
            #endif
        }

        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = NormalizePS;
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
            RenderTarget0 = _RenderOpticalFlow;
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
            PixelShader = InterpolatePS;
            SRGBWriteEnable = TRUE;
        }

        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = CopyPS2;
            RenderTarget = _RenderFrame1;
            #if BUFFER_COLOR_BIT_DEPTH == 8
                SRGBWriteEnable = TRUE;
            #endif
        }
    }
}