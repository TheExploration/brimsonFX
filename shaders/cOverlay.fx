
/*
    Simple backbuffer overlay shader v0.1

    BSD 3-Clause License

    Copyright (c) 2022, Paul Dang
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

    3. Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived from
    this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
    FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

uniform float2 _TexScale <
    ui_label = "Scale";
    ui_category = "Texture";
    ui_type = "drag";
    ui_step = 0.001;
> = 1.0;

uniform float2 _TexOffset <
    ui_label = "Offset";
    ui_category = "Texture";
    ui_type = "drag";
    ui_step = 0.001;
> = float2(0.0, 0.0);

uniform float2 _MaskScale <
    ui_type = "drag";
    ui_label = "Scale";
    ui_category = "Mask";
    ui_min = 0.0;
> = float2(0.0, 0.0);

uniform float2 _MaskOffset <
    ui_type = "drag";
    ui_label = "Scale";
    ui_category = "Mask";
    ui_min = 0.0;
> = float2(0.0, 0.0);

texture2D RenderColor : COLOR;

sampler2D SampleColor
{
    Texture = RenderColor;
    AddressU = MIRROR;
    AddressV = MIRROR;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
    #if BUFFER_COLOR_BIT_DEPTH == 8
        SRGBTexture = TRUE;
    #endif
};

void OverlayVS(in uint ID : SV_VertexID, out float4 Position : SV_Position, out float4 TexCoord : TEXCOORD0)
{
    TexCoord = 0.0;
    TexCoord.x = (ID == 2) ? 2.0 : 0.0;
    TexCoord.y = (ID == 1) ? 2.0 : 0.0;
    Position = float4(TexCoord.xy * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);

    // Scale texture coordinates from [0, 1] to [-1, 1] range
    TexCoord.zw = TexCoord.xy * 2.0 - 1.0;
    // Scale and offset in [-1, 1] range
    TexCoord.zw = TexCoord.zw * _TexScale + _TexOffset;
    // Scale texture coordinates from [-1, 1] to [0, 1] range
    TexCoord.zw = TexCoord.zw * 0.5 + 0.5;
}

void OverlayPS(in float4 Position : SV_Position, in float4 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_Target0)
{
    float4 InputColor = tex2D(SampleColor, TexCoord.zw);

    // Output a rectangle
    float2 MaskCoord = TexCoord.xy;
    MaskCoord = MaskCoord * _MaskScale + MaskCoord;
    float2 Scale = -_MaskScale * 0.5 + 0.5;
    float2 Shaper = step(Scale, MaskCoord.xy) * step(Scale, 1.0 - MaskCoord.xy);
    float Crop = Shaper.x * Shaper.y;

    OutputColor0.rgb = InputColor.rgb;
    OutputColor0.a = Crop;
}

technique cOverlay
{
    pass
    {
        VertexShader = OverlayVS;
        PixelShader = OverlayPS;
        // Blend the rectangle with the backbuffer
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBWriteEnable = TRUE;
        #endif
    }
}