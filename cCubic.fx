
/*
    https://gist.github.com/TheRealMJP/c83b8c0f46b63f3a88a5986f4fa982b1

    MIT License

    Copyright (c) 2019 MJP

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

#include "ReShade.fxh"

texture t_Downscaled { Width = BUFFER_WIDTH / 2.0; Height = BUFFER_HEIGHT / 2.0; };

sampler s_Linear { Texture = ReShade::BackBufferTex; SRGBTexture = true; };
sampler s_Downscaled { Texture = t_Downscaled }

/*
    The following code is licensed under the MIT license: https://gist.github.com/TheRealMJP/bc503b0b87b643d3505d41eab8b332ae
    Samples a texture with Catmull-Rom filtering, using 9 texture fetches instead of 16.
    See http://vec3.ca/bicubic-filtering-in-fewer-taps/ for more details
*/

float4 PS_Empty(in float4 v : SV_POSITION, in float2 uv : TEXCOORD) : SV_Target
{
    return tex2D(s_Linear, uv);
}

float4 PS_SampleTextureCatmullRom(in float4 v : SV_POSITION, in float2 uv : TEXCOORD) : SV_Target
{
    const float2 texSize = BUFFER_SCREEN_SIZE / 2.0;

    /*
        We're going to sample a a 4x4 grid of texels surrounding the target UV coordinate. We'll do this by rounding
        down the sample location to get the exact center of our "starting" texel. The starting texel will be at
        location [1, 1] in the grid, where [0, 0] is the top left corner.
    */

    float2 samplePos = uv * texSize;
    float2 texPos1 = floor(samplePos - 0.5f) + 0.5f;

    /*
        Compute the fractional offset from our starting texel to our original sample location, which we'll
        feed into the Catmull-Rom spline function to get our filter weights.
    */

    float2 f = samplePos - texPos1;

    /*
        Compute the Catmull-Rom weights using the fractional offset that we calculated earlier.
        These equations are pre-expanded based on our knowledge of where the texels will be located,
        which lets us avoid having to evaluate a piece-wise function.
    */

    float2 w0 = f * (-0.5f + f * (1.0f - 0.5f * f));
    float2 w1 = 1.0f + f * f * (-2.5f + 1.5f * f);
    float2 w2 = f * (0.5f + f * (2.0f - 1.5f * f));
    float2 w3 = f * f * (-0.5f + 0.5f * f);

    /*
        Work out weighting factors and sampling offsets that will let us use bilinear filtering to
        simultaneously evaluate the middle 2 samples from the 4x4 grid.
    */

    float2 w12 = w1 + w2;
    float2 offset12 = w2 / (w1 + w2);

    // Compute the final UV coordinates we'll use for sampling the texture
    float2 texPos0 = texPos1 - 1;
    float2 texPos3 = texPos1 + 2;
    float2 texPos12 = texPos1 + offset12;

    texPos0 /= texSize;
    texPos3 /= texSize;
    texPos12 /= texSize;

    float4 result;
    result += tex2D(s_Downscaled, float2(texPos0.x,  texPos0.y)) * w0.x * w0.y;
    result += tex2D(s_Downscaled, float2(texPos12.x, texPos0.y)) * w12.x * w0.y;
    result += tex2D(s_Downscaled, float2(texPos3.x,  texPos0.y)) * w3.x * w0.y;

    result += tex2D(s_Downscaled, float2(texPos0.x,  texPos12.y)) * w0.x * w12.y;
    result += tex2D(s_Downscaled, float2(texPos12.x, texPos12.y)) * w12.x * w12.y;
    result += tex2D(s_Downscaled, float2(texPos3.x,  texPos12.y)) * w3.x * w12.y;

    result += tex2D(s_Downscaled, float2(texPos0.x,  texPos3.y)) * w0.x * w3.y;
    result += tex2D(s_Downscaled, float2(texPos12.x, texPos3.y)) * w12.x * w3.y;
    result += tex2D(s_Downscaled, float2(texPos3.x,  texPos3.y)) * w3.x * w3.y;

    return result;
}

technique Cubic
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Empty;
        RenderTarget = t_Downscaled;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SampleTextureCatmullRom;
        SRGBTexture = true;
    }
}