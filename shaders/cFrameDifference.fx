
uniform float _Blend <
    ui_type = "slider";
    ui_label = "Blending";
    ui_min = 0.0;
    ui_max = 1.0;
> = 0.5;

uniform float _Weight <
    ui_type = "slider";
    ui_label = "Thresholding";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.0;

uniform float _Scale <
    ui_type = "slider";
    ui_label = "Scaling";
    ui_min = 0.0;
    ui_max = 2.0;
> = 1.0;

uniform bool _NormalizeInput <
    ui_type = "radio";
    ui_label = "Scaling";
> = false;

texture2D _RenderColor : COLOR;

sampler2D _SampleColor
{
    Texture = _RenderColor;
    SRGBTexture = TRUE;
};

texture2D _RenderCurrent_FrameDifference
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};

sampler2D _SampleCurrent
{
    Texture = _RenderCurrent_FrameDifference;
    SRGBTexture = TRUE;
};

texture2D _RenderDifference
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R16F;
};

sampler2D _SampleDifference
{
    Texture = _RenderDifference;
};

texture2D _RenderPrevious_FrameDifference
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};

sampler2D _SamplePrevious
{
    Texture = _RenderPrevious_FrameDifference;
    SRGBTexture = TRUE;
};

/* [Vertex Shaders] */

void PostProcessVS(in uint ID : SV_VERTEXID, inout float4 Position : SV_POSITION, inout float2 TexCoord : TEXCOORD0)
{
    TexCoord.x = (ID == 2) ? 2.0 : 0.0;
    TexCoord.y = (ID == 1) ? 2.0 : 0.0;
    Position = TexCoord.xyxy * float4(2.0, -2.0, 0.0, 0.0) + float4(-1.0, 1.0, 0.0, 1.0);
}

/* [Pixel Shaders] */

void BlitPS0(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = tex2D(_SampleColor, TexCoord);
}

void DifferencePS(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_TARGET0)
{
    const float Weight = _Weight * 1e-2;
    float3 Current = tex2D(_SampleCurrent, TexCoord).rgb;
    float3 Previous = tex2D(_SamplePrevious, TexCoord).rgb;
    OutputColor0.rgb = (_NormalizeInput) ? normalize(Current) - normalize(Previous) : Current - Previous;
    OutputColor0.rgb *= rsqrt(dot(OutputColor0.rgb, OutputColor0.rgb) + Weight);
    OutputColor0.rgb = _Scale * dot(abs(OutputColor0.rgb), 1.0 / 3.0);
    OutputColor0.a = _Blend;
}

void OutputPS(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = tex2D(_SampleDifference, TexCoord).r;
}

void BlitPS1(float4 Position : SV_POSITION, float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = tex2D(_SampleCurrent, TexCoord);
}

technique cFrameDifference
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = BlitPS0;
        RenderTarget0 = _RenderCurrent_FrameDifference;
        SRGBWriteEnable = TRUE;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = DifferencePS;
        RenderTarget0 = _RenderDifference;
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = INVSRCALPHA;
        DestBlend = SRCALPHA;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = OutputPS;
        SRGBWriteEnable = TRUE;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = BlitPS1;
        RenderTarget0 = _RenderPrevious_FrameDifference;
        SRGBWriteEnable = TRUE;
    }
}