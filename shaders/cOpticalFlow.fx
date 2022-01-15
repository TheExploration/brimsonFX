
/*
    Optical flow motion blur

    MIT License

    Copyright (c) 2022 brimson

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

namespace OpticalFlow
{
    uniform float _Blend <
        ui_type = "slider";
        ui_label = "Blending";
        ui_min = 0.0;
        ui_max = 1.0;
    > = 0.25;

    uniform float _Constraint <
        ui_type = "drag";
        ui_label = "Constraint";
        ui_tooltip = "Higher = Smoother flow";
    > = 1.0;

    uniform float _Detail <
        ui_type = "drag";
        ui_label = "Mipmap Bias";
        ui_tooltip = "Higher = Less spatial noise";
    > = 0.0;

    uniform bool _Normal <
        ui_label = "Lines Normal Direction";
        ui_tooltip = "Normal to velocity direction";
        ui_type = "radio";
    > = true;

    #define SCREEN_SIZE uint2(BUFFER_WIDTH / 2, BUFFER_HEIGHT / 2)
    #define PIXEL_SIZE uint2(1 / SCREEN_SIZE)

    #ifndef RENDER_VELOCITY_STREAMS
        #define RENDER_VELOCITY_STREAMS 1
    #endif

    #ifndef VERTEX_SPACING
        #define VERTEX_SPACING 10
    #endif

    #define LINES_X uint(BUFFER_WIDTH / VERTEX_SPACING)
    #define LINES_Y uint(BUFFER_HEIGHT / VERTEX_SPACING)
    #define NUM_LINES (LINES_X * LINES_Y)
    #define SPACE_X (BUFFER_WIDTH / LINES_X)
    #define SPACE_Y (BUFFER_HEIGHT / LINES_Y)
    #define VELOCITY_SCALE (SPACE_X + SPACE_Y) * 1

    texture2D _RenderColor : COLOR;

    sampler2D _SampleColor
    {
        Texture = _RenderColor;
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBTexture = TRUE;
        #endif
    };

    texture2D _RenderData0
    {
        Width = SCREEN_SIZE.x;
        Height = SCREEN_SIZE.y;
        Format = RG16F;
        MipLevels = 8;
    };

    sampler2D _SampleData0
    {
        Texture = _RenderData0;
    };

    texture2D _RenderData1
    {
        Width = SCREEN_SIZE.x;
        Height = SCREEN_SIZE.y;
        Format = RGBA16F;
        MipLevels = 8;
    };

    sampler2D _SampleData1
    {
        Texture = _RenderData1;
    };

    texture2D _RenderData2
    {
        Width = SCREEN_SIZE.x;
        Height = SCREEN_SIZE.y;
        Format = RG16F;
        MipLevels = 8;
    };

    sampler2D _SampleData2
    {
        Texture = _RenderData2;
    };

    texture2D _RenderOpticalFlow
    {
        Width = SCREEN_SIZE.x;
        Height = SCREEN_SIZE.y;
        Format = RG16F;
    };

    sampler2D _SampleOpticalFlow
    {
        Texture = _RenderOpticalFlow;
    };

    // Vertex shaders
    // Shaders: https://github.com/diwi/PixelFlow/blob/master/src/com/thomasdiewald/pixelflow/glsl/OpticalFlow/renderVelocityStreams.vert
    // Uniforms: https://github.com/diwi/PixelFlow/blob/master/src/com/thomasdiewald/pixelflow/java/imageprocessing/DwOpticalFlow.java#L230

    static const float SampleOffsets[8] =
    {
        0.0,
        1.4850044983805901,
        3.4650570548417856,
        5.4452207648927855,
        7.425557483188341,
        9.406126897065857,
        11.386985823860664,
        13.368187582263898
    };

    void BlurOffsets(in float2 TexCoord, in float2 PixelSize, out float4 Offsets[7])
    {
        int OffsetIndex = 0;
        int SampleIndex = 1;

        while(OffsetIndex < 7)
        {
            Offsets[OffsetIndex].xy = TexCoord.xy - (SampleOffsets[SampleIndex] * PixelSize.xy);
            Offsets[OffsetIndex].zw = TexCoord.xy + (SampleOffsets[SampleIndex] * PixelSize.xy);
            OffsetIndex = OffsetIndex + 1;
            SampleIndex = SampleIndex + 1;
        }
    }

    void PostProcessVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float2 TexCoord : TEXCOORD0)
    {
        TexCoord.x = (ID == 2) ? 2.0 : 0.0;
        TexCoord.y = (ID == 1) ? 2.0 : 0.0;
        Position = TexCoord.xyxy * float4(2.0, -2.0, 0.0, 0.0) + float4(-1.0, 1.0, 0.0, 1.0);
    }

    void HorizontalBlurVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float2 TexCoord : TEXCOORD0, out float4 Offsets[7] : TEXCOORD1)
    {
        PostProcessVS(ID, Position, TexCoord);
        BlurOffsets(TexCoord, float2(1.0 / SCREEN_SIZE.x, 0.0), Offsets);
    }

    void VerticalBlurVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float2 TexCoord : TEXCOORD0, out float4 Offsets[7] : TEXCOORD1)
    {
        PostProcessVS(ID, Position, TexCoord);
        BlurOffsets(TexCoord, float2(0.0, 1.0 / SCREEN_SIZE.y), Offsets);
    }

    void DerivativesVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float4 Offsets : TEXCOORD0)
    {
        const float2 PixelSize = 0.5 / SCREEN_SIZE.xy;
        const float4 PixelOffset = float4(PixelSize, -PixelSize);
        float2 TexCoord0;
        PostProcessVS(ID, Position, TexCoord0);
        Offsets = TexCoord0.xyxy + PixelOffset;
    }

    void VelocityStreamsVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float2 Velocity : TEXCOORD0)
    {
        int LineID = ID / 2; // Line Index
        int VertexID = ID % 2; // Vertex Index within the line (0 = start, 1 = end)

        // Get Row (x) and Column (y) position
        int Row = LineID / LINES_X;
        int Column = LineID - LINES_X * Row;

        // Compute origin (line-start)
        const float2 Spacing = float2(SPACE_X, SPACE_Y);
        float2 Offset = Spacing * 0.5;
        float2 Origin = Offset + float2(Column, Row) * Spacing;

        // Get velocity from texture at origin location
        const float2 PixelSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
        float2 VelocityCoord;
        VelocityCoord.xy = Origin.xy * PixelSize.xy;
        VelocityCoord.y = 1.0 - VelocityCoord.y;
        Velocity = tex2Dlod(_SampleData2, float4(VelocityCoord, 0.0, _Detail)).xy;

        // Scale velocity
        float2 Direction = Velocity * VELOCITY_SCALE;

        float Length = length(Direction + 1e-5);
        Direction = Direction / sqrt(Length * 0.1);

        // Color for fragmentshader
        Velocity = Direction * 0.2;

        // Compute current vertex position (based on VertexID)
        float2 VertexPosition = 0.0;

        if(_Normal)
        {
            // Lines: Normal to velocity direction
            Direction *= 0.5;
            float2 DirectionNormal = float2(Direction.y, -Direction.x);
            VertexPosition = Origin + Direction - DirectionNormal + DirectionNormal * VertexID * 2;
        }
        else
        {
            // Lines: Velocity direction
            VertexPosition = Origin + Direction * VertexID;
        }

        // Finish vertex position
        float2 VertexPositionNormal = (VertexPosition + 0.5) * PixelSize; // [0, 1]
        Position = float4(VertexPositionNormal * 2.0 - 1.0, 0.0, 1.0); // ndc: [-1, +1]
    }

    // Pixel shaders
    // VelocityStreams: https://github.com/diwi/PixelFlow/blob/master/src/com/thomasdiewald/pixelflow/glsl/OpticalFlow/renderVelocityStreams.frag

    static const float SampleWeights[8] =
    {
        0.07978845608028654,
        0.15186256685575583,
        0.12458323113065647,
        0.08723135590047126,
        0.05212966006304008,
        0.02658822496281644,
        0.011573824628214867,
        0.004299684163333117
    };

    float4 GaussianBlur(sampler2D Source, float2 TexCoord, float4 Offsets[7])
    {
        float TotalSampleWeights = SampleWeights[0];
        float4 OutputColor = tex2D(Source, TexCoord) * SampleWeights[0];

        int SampleIndex = 0;
        int WeightIndex = 1;

        while(SampleIndex < 7)
        {
            OutputColor += (tex2D(Source, Offsets[SampleIndex].xy) * SampleWeights[WeightIndex]);
            OutputColor += (tex2D(Source, Offsets[SampleIndex].zw) * SampleWeights[WeightIndex]);
            TotalSampleWeights += (SampleWeights[WeightIndex] * 2.0);
            SampleIndex = SampleIndex + 1;
            WeightIndex = WeightIndex + 1;
        }

        return OutputColor / TotalSampleWeights;
    }

    void CopyPS(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float2 OutputColor0 : SV_Target0)
    {
        OutputColor0 = tex2D(_SampleData0, TexCoord).rg;
    }

    void BlitPS(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float2 OutputColor0 : SV_Target0)
    {
        float3 Color = tex2D(_SampleColor, TexCoord).rgb;
        OutputColor0 = saturate(Color.xy / dot(Color, 1.0));
    }

    void HorizontalBlurPS0(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, in float4 Offsets[7] : TEXCOORD1, out float4 OutputColor0 : SV_Target0)
    {
        OutputColor0 = GaussianBlur(_SampleData0, TexCoord, Offsets);
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

    /*
        Horn Schunck
            http://6.869.csail.mit.edu/fa12/lectures/lecture16/MotionEstimation1.pdf
            - Use Gauss-Seidel at slide 52
            - Use additional constraint (normalized RG)

        Pyramid
            https://www.cs.auckland.ac.nz/~rklette/CCV-CIMAT/pdfs/B08-HornSchunck.pdf
            - Use a regular image pyramid for input frames I(., .,t)
            - Processing starts at a selected level (of lower resolution)
            - Obtained results are used for initializing optic flow values at a
            lower level (of higher resolution)
            - Repeat until full resolution level of original frames is reached
    */

    void OpticalFlowPS(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
    {
        const float2 PixelSize = 2.0 / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        const float MaxLevel = 6.5;
        float4 OpticalFlow;
        float2 Smooth;
        float3 Data;

        [unroll] for(float Level = MaxLevel; Level > 0.0; Level--)
        {
            const float Alpha = max(ldexp(_Constraint * 1e-5, Level - MaxLevel), 1e-7);

            // .xy = Normalized Red Channel (x, y)
            // .zw = Normalized Green Channel (x, y)
            float4 SampleI = tex2Dlod(_SampleData1, float4(TexCoord, 0.0, Level)).xyzw;

            // .xy = Current frame (r, g)
            // .zw = Previous frame (r, g)
            float4 SampleFrames;
            SampleFrames.xy = tex2Dlod(_SampleData0, float4(TexCoord, 0.0, Level)).rg;
            SampleFrames.zw = tex2Dlod(_SampleData2, float4(TexCoord + (OpticalFlow.xy * PixelSize), 0.0, Level)).rg;
            float2 Iz = SampleFrames.xy - SampleFrames.zw;

            Smooth.x = dot(SampleI.xz, SampleI.xz) + Alpha;
            Smooth.y = dot(SampleI.yw, SampleI.yw) + Alpha;
            Data.x = dot(SampleI.xz, Iz.rg);
            Data.y = dot(SampleI.yw, Iz.rg);
            Data.z = dot(SampleI.xz, SampleI.yw);
            OpticalFlow.x = ((Alpha * OpticalFlow.x) - (OpticalFlow.y * Data.z) - Data.x) / Smooth.x;
            OpticalFlow.y = ((Alpha * OpticalFlow.y) - (OpticalFlow.x * Data.z) - Data.y) / Smooth.y;
        }

        OutputColor0.xy = OpticalFlow.xy;
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

    void VelocityShadingPS(in float4 Position : SV_Position, in float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target)
    {
        float2 Velocity = tex2Dlod(_SampleData2, float4(TexCoord, 0.0, _Detail)).xy;
        float VelocityLength = saturate(rsqrt(dot(Velocity, Velocity)));
        OutputColor0.rg = (Velocity * VelocityLength) * 0.5 + 0.5;
        OutputColor0.b = -dot(OutputColor0.rg, 1.0) * 0.5 + 1.0;
        OutputColor0.a = 1.0;
    }

    void VelocityStreamsPS(in float4 Position : SV_Position, in float2 Velocity : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
    {
        float Length = length(Velocity) * VELOCITY_SCALE * 0.05;
        OutputColor0.rg = (Velocity.xy / Length) * 0.5 + 0.5;
        OutputColor0.b = -dot(OutputColor0.rg, 1.0) * 0.5 + 1.0;
        OutputColor0.a = 1.0;
    }

    technique cOpticalFlow
    {
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = CopyPS;
            RenderTarget0 = _RenderData2;
        }

        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = BlitPS;
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

        #if RENDER_VELOCITY_STREAMS
            pass
            {
                PrimitiveTopology = LINELIST;
                VertexCount = NUM_LINES * 2;
                VertexShader = VelocityStreamsVS;
                PixelShader = VelocityStreamsPS;
                ClearRenderTargets = FALSE;
                BlendEnable = TRUE;
                BlendOp = ADD;
                SrcBlend = SRCALPHA;
                DestBlend = INVSRCALPHA;
                SrcBlendAlpha = ONE;
                DestBlendAlpha = ONE;
            }
        #else
            pass
            {
                VertexShader = PostProcessVS;
                PixelShader = VelocityShadingPS;
            }
        #endif
    }
}
