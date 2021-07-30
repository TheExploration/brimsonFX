
/*
    Optical flow motion blur using color by Brimson
    Special Thanks to
    - MartinBFFan and Pao on Discord for reporting bugs
    - BSD for bug propaganda and helping to solve my issue
    - Lord of Lunacy, KingEric1992, and Marty McFly for power of 2 function

    Notes:  Blurred previous + current frames must be 32Float textures.
            This makes the optical flow not suffer from noise + banding

    LOD Compute  - [https://john-chapman.github.io/2019/03/29/convolution.html]
    Median3      - [https://github.com/GPUOpen-Effects/FidelityFX-CAS] [MIT]
    Noise        - [http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare]
    Optical Flow - [https://dspace.mit.edu/handle/1721.1/6337]
    Pi Constant  - [https://github.com/microsoft/DirectX-Graphics-Samples] [MIT]
    Vogel Disk   - [http://blog.marmakoide.org/?p=1]
*/

#define uOption(option, udata, utype, ucategory, ulabel, uvalue, umin, umax)    \
        uniform udata option <                                                  \
        ui_category = ucategory; ui_label = ulabel;                             \
        ui_type = utype; ui_min = umin; ui_max = umax;                          \
        > = uvalue

uOption(uSigma,  float, "slider", "Basic", "Sensitivity", 0.500, 0.000, 1.000);
uOption(uRadius, float, "slider", "Basic", "Prefilter",   8.000, 0.000, 16.00);

uOption(uBlend,  float, "slider", "Advanced", "Frame Blend", 0.100, 0.000, 1.000);
uOption(uSmooth, float, "slider", "Advanced", "Flow Smooth", 0.100, 0.000, 0.500);
uOption(uDetail, float, "slider", "Advanced", "Flow Mip",    4.000, 0.000, 8.000);
uOption(uDebug,  bool,  "radio",  "Advanced", "Debug",       false, 0, 0);

#define CONST_LOG2(x) (\
    (uint((x)  & 0xAAAAAAAA) != 0) | \
    (uint(((x) & 0xFFFF0000) != 0) << 4) | \
    (uint(((x) & 0xFF00FF00) != 0) << 3) | \
    (uint(((x) & 0xF0F0F0F0) != 0) << 2) | \
    (uint(((x) & 0xCCCCCCCC) != 0) << 1))

#define BIT2_LOG2(x)  ((x) | (x) >> 1)
#define BIT4_LOG2(x)  (BIT2_LOG2(x) | BIT2_LOG2(x) >> 2)
#define BIT8_LOG2(x)  (BIT4_LOG2(x) | BIT4_LOG2(x) >> 4)
#define BIT16_LOG2(x) (BIT8_LOG2(x) | BIT8_LOG2(x) >> 8)
#define LOG2(x)       (CONST_LOG2((BIT16_LOG2(x) >> 1) + 1))
#define RMAX(x, y)     x ^ ((x ^ y) & -(x < y)) // max(x, y)

#define DSIZE uint2(BUFFER_WIDTH / 2, BUFFER_HEIGHT / 2)
#define RSIZE LOG2(RMAX(DSIZE.x, DSIZE.y)) + 1

static const float Pi = 3.1415926535897f;
static const float Epsilon = 1e-7;
static const int uTaps = 14;

texture2D r_color  : COLOR;
texture2D r_buffer { Width = DSIZE.x; Height = DSIZE.y; MipLevels = RSIZE; Format = R8; };
texture2D r_pframe { Width = 256; Height = 256; Format = RGBA32F; MipLevels = 9; };
texture2D r_cframe { Width = 256; Height = 256; Format = R32F; };
texture2D r_cflow  { Width = 256; Height = 256; Format = RG32F; MipLevels = 9; };
texture2D r_pcolor { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };

sampler2D s_color  { Texture = r_color; SRGBTexture = TRUE; };
sampler2D s_buffer { Texture = r_buffer; AddressU = MIRROR; AddressV = MIRROR; };
sampler2D s_pframe { Texture = r_pframe; AddressU = MIRROR; AddressV = MIRROR; };
sampler2D s_cframe { Texture = r_cframe; AddressU = MIRROR; AddressV = MIRROR; };
sampler2D s_cflow  { Texture = r_cflow;  AddressU = MIRROR; AddressV = MIRROR; };
sampler2D s_pcolor { Texture = r_pcolor; SRGBTexture = TRUE; };

/* [ Vertex Shaders ] */

void v2f_core(  in uint id,
                inout float2 uv,
                inout float4 vpos)
{
    uv.x = (id == 2) ? 2.0 : 0.0;
    uv.y = (id == 1) ? 2.0 : 0.0;
    vpos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float2 Vogel2D(int uIndex, float2 uv, float2 pSize)
{
    const float  GoldenAngle = Pi * (3.0 - sqrt(5.0));
    const float2 Radius = (sqrt(uIndex + 0.5f) / sqrt(uTaps)) * pSize;
    const float  Theta = uIndex * GoldenAngle;

    float2 SineCosine;
    sincos(Theta, SineCosine.x, SineCosine.y);
    return Radius * SineCosine.yx + uv;
}

void vs_convert(    in uint id : SV_VERTEXID,
                    inout float4 vpos : SV_POSITION,
                    inout float2 uv : TEXCOORD0,
                    inout float4 ofs[7] : TEXCOORD1)
{
    // Calculate texel offset of the mipped texture
    const float cLOD = log2(max(DSIZE.x, DSIZE.y)) - log2(256);
    const float2 uSize = rcp(DSIZE.xy / exp2(cLOD)) * uRadius;
    v2f_core(id, uv, vpos);

    for(int i = 0; i < 7; i++)
    {
        ofs[i].xy = Vogel2D(i, uv, uSize);
        ofs[i].zw = Vogel2D(7 + i, uv, uSize);
    }
}

void vs_filter( in uint id : SV_VERTEXID,
                inout float4 vpos : SV_POSITION,
                inout float4 ofs[8] : TEXCOORD0)
{
    const float2 uSize = rcp(256) * uRadius;
    float2 uv;
    v2f_core(id, uv, vpos);

    for(int i = 0; i < 8; i++)
    {
        ofs[i].xy = Vogel2D(i, uv, uSize);
        ofs[i].zw = Vogel2D(8 + i, uv, uSize);
    }
}

void vs_common( in uint id : SV_VERTEXID,
                inout float4 vpos : SV_POSITION,
                inout float2 uv : TEXCOORD0)
{
    v2f_core(id, uv, vpos);
}

/* [ Pixel Shaders ] */

float urand(float2 vpos)
{
    const float3 value = float3(52.9829189, 0.06711056, 0.00583715);
    return frac(value.x * frac(dot(vpos.xy, value.yz)));
}

float4 ps_source(   float4 vpos : SV_POSITION,
                    float2 uv : TEXCOORD0) : SV_Target
{
    float3 uImage = tex2D(s_color, uv.xy).rgb;
    float luma = max(max(uImage.r, uImage.g), uImage.b);
    float output = luma * rsqrt(dot(uImage.rgb, uImage.rgb));
    return output;
}

float4 ps_convert(  float4 vpos : SV_POSITION,
                    float2 uv : TEXCOORD0,
                    float4 ofs[7] : TEXCOORD1) : SV_Target
{
    const int cTaps = 14;
    float uImage;
    float2 vofs[cTaps];

    for (int i = 0; i < 7; i++)
    {
        vofs[i] = ofs[i].xy;
        vofs[i + 7] = ofs[i].zw;
    }

    for (int j = 0; j < cTaps; j++)
    {
        float uColor = tex2D(s_buffer, vofs[j]).r;
        uImage = lerp(uImage, uColor, rcp(float(j) + 1));
    }

    float4 output;
    output.xy = tex2D(s_cflow, uv).rg; // Copy previous rendertarget from ps_flow()
    output.z  = tex2D(s_cframe, uv).r; // Copy previous rendertarget from ps_filter()
    output.w  = uImage; // Input downsampled current frame to scale and mip
    return output;
}

float4 ps_filter(   float4 vpos : SV_POSITION,
                    float4 ofs[8] : TEXCOORD0) : SV_Target
{
    const int cTaps = 16;
    const float uArea = Pi * (uRadius * uRadius) / uTaps;
    const float uBias = log2(sqrt(uArea));

    float uImage;
    float2 vofs[cTaps];

    for (int i = 0; i < 8; i++)
    {
        vofs[i] = ofs[i].xy;
        vofs[i + 8] = ofs[i].zw;
    }

    for (int j = 0; j < cTaps; j++)
    {
        float uColor = tex2Dlod(s_pframe, float4(vofs[j], 0.0, uBias)).w;
        uImage = lerp(uImage, uColor, rcp(float(j) + 1));
    }

    return uImage;
}

/*
    Possible improvements
    - Coarse to fine refinement (may have to use ddxy instead)
    - Better penalty function outside quadratic

    Idea:
    - Make derivatives pass with mipchain
    -- cddxy (RG32F)
    - Copy previous using ps_convert's 4th MRT (or pack with pflow)
    -- pddxy (also RG32F)
    - Use derivatives mipchain on pyramid

    Possible issues I need help on:
    - Scaling summed previous flow to next "upscaled" level
    - If previous frame does warp right in the flow pass with tex2Dlod()
    - If HS can work this way with 1 iteration
    - Resolution customization will have to go for now until this works
*/

float4 ps_flow( float4 vpos : SV_POSITION,
                float2 uv : TEXCOORD0) : SV_Target
{
    // Calculate optical flow
    float cLuma = tex2D(s_cframe, uv).r; // [0, 0]
    float pLuma = tex2D(s_pframe, uv).z; // [0, 0]

    float dFdt = cLuma - pLuma;
    float2 dFdc = float2(ddx(cLuma), ddy(cLuma));
    float2 dFdp = float2(ddx(pLuma), ddy(pLuma));

    float dBrightness = dot(dFdp, dFdc) + dFdt;
    const float dConstraint = rcp(2.0 * pow(uSigma, 2.0));
    float3 dSmoothness;
    dSmoothness.xy = dFdp.xy * dFdp.xy;
    dSmoothness.xy = log(1.0 + dSmoothness.xy * dConstraint);
    dSmoothness.z = dot(dSmoothness.xy, 1.0) + Epsilon;
    float2 cFlow = dFdc - (dFdp * dBrightness) / dSmoothness.z;

    // Smooth optical flow
    float2 sFlow = tex2D(s_pframe, uv).xy; // [0, 0]
    return lerp(cFlow, sFlow, uSmooth).xyxy;
}

// Median masking inspired by vs-mvtools
// https://github.com/dubhater/vapoursynth-mvtools

float4 Median3( float4 a, float4 b, float4 c)
{
    return max(min(a, b), min(max(a, b), c));
}

float4 ps_output(   float4 vpos : SV_POSITION,
                    float2 uv : TEXCOORD0) : SV_Target
{
    const float2 pSize = rcp(256.0);
    float2 pFlow = tex2Dlod(s_cflow, float4(uv, 0.0, uDetail)).xy;
    float4 pRef = tex2D(s_color, uv);
    float4 pSrc = tex2D(s_pcolor, uv);
    float4 pMCB = tex2D(s_color, uv - pFlow * pSize);
    float4 pMCF = tex2D(s_pcolor, uv + pFlow * pSize);
    float4 pAvg = lerp(pRef, pSrc, uBlend);
    return (uDebug) ? float4(pFlow, 1.0, 1.0) : Median3(pMCF, pMCB, pAvg);
}

float4 ps_previous( float4 vpos : SV_POSITION,
                    float2 uv : TEXCOORD0) : SV_Target
{
    return float4(tex2D(s_color, uv).rgb, 1.0);
}

technique cInterpolate
{
    pass cBlur
    {
        VertexShader = vs_common;
        PixelShader = ps_source;
        RenderTarget0 = r_buffer;
    }

    pass cCopyPrevious
    {
        VertexShader = vs_convert;
        PixelShader = ps_convert;
        RenderTarget0 = r_pframe;
    }

    pass cBlurCopyFrame
    {
        VertexShader = vs_filter;
        PixelShader = ps_filter;
        RenderTarget0 = r_cframe;
    }

    pass cOpticalFlow
    {
        VertexShader = vs_common;
        PixelShader = ps_flow;
        RenderTarget0 = r_cflow;
    }

    pass cFlowBlur
    {
        VertexShader = vs_common;
        PixelShader = ps_output;
        SRGBWriteEnable = TRUE;
    }

    pass cStorePrevious
    {
        VertexShader = vs_common;
        PixelShader = ps_previous;
        RenderTarget = r_pcolor;
        SRGBWriteEnable = TRUE;
    }
}