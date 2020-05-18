///////////////////////////////////////////////////////////////////
// Simple depth-based fog powered with bloom to fake light diffusion.
// The bloom is borrowed from SweetFX's bloom by CeeJay.
//
// As Reshade 3 lets you tweak the parameters in-game, the mouse-oriented
// feature of the v2 Adaptive Fog is no longer needed: you can select the
// fog color in the reshade settings GUI instead.
//
///////////////////////////////////////////////////////////////////
// By Otis / Infuse Project
///////////////////////////////////////////////////////////////////

#include "ReShadeUI.fxh"
#include "Reshade.fxh"

uniform float3 SKY_COLOR <
	ui_type = "color";
	ui_label = "Sky Color";
    ui_category = "天球颜色获取";
> = float3(1.0, 0.0, 0.0);

#if SKYCOLOR_MODE == 2
uniform float SKY_COLOR_SAT <
	ui_type = "drag";
	ui_min = 0; ui_max = 5.0;
    ui_step = 0.01;
    ui_label = "Auto Sky Color Saturation";
    ui_category = "天球颜色获取";
> = 1.0;
#endif

uniform float SKY_COLOR_AMBIENT_MIX <
	ui_type = "drag";
	ui_min = 0; ui_max = 1.0;
    ui_step = 0.01;
    ui_label = "Sky Color Ambient Mix";
    ui_tooltip = "How much of the occluded ambient color is considered skycolor\n\nIf 0, Ambient Occlusion removes white ambient color,\nif 1, Ambient Occlusion only removes skycolor";
    ui_category = "天球颜色获取";
> = 0.2;

uniform float SKY_COLOR_AMT <
	ui_type = "drag";
	ui_min = 0; ui_max = 10.0;
    ui_step = 0.01;
    ui_label = "Sky Color Intensity";
    ui_category = "天球颜色获取";
> = 4.0;
//
uniform float3 FogColor < __UNIFORM_COLOR_FLOAT3
	ui_tooltip = "Color of the fog, in (red , green, blue)";
	ui_category = "雾";
> = float3(0.9,0.9,0.9);

uniform float MaxFogFactor < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.000; ui_max=1.000;
	ui_tooltip = "The maximum fog factor. 1.0 makes distant objects completely fogged out, a lower factor will shimmer them through the fog.";
	ui_category = "雾";
	ui_step = 0.001;
> = 0.8;

uniform float FogCurve < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.00; ui_max=175.00;
	ui_step = 0.01;
	ui_tooltip = "The curve how quickly distant objects get fogged. A low value will make the fog appear just slightly. A high value will make the fog kick in rather quickly. The max value in the rage makes it very hard in general to view any objects outside fog.";
	ui_category = "雾";
> = 1.5;

uniform float FogStart < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.000; ui_max=1.000;
	ui_step = 0.001;
	ui_tooltip = "Start of the fog. 0.0 is at the camera, 1.0 is at the horizon, 0.5 is halfway towards the horizon. Before this point no fog will appear.";
	ui_category = "雾";
> = 0.050;

uniform float BloomThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.00; ui_max=50.00;
	ui_step = 0.1;
	ui_tooltip = "Threshold for what is a bright light (that causes bloom) and what isn't.";
	ui_category = "雾";
> = 10.25;

uniform float BloomPower < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.000; ui_max=100.000;
	ui_step = 0.1;
	ui_tooltip = "Strength of the bloom";
	ui_category = "雾";
> = 10.0;

uniform float BloomWidth < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0000; ui_max=1.0000;
	ui_tooltip = "Width of the bloom";
	ui_category = "雾";
> = 0.2;

//////////////////////////////////////
// textures
//////////////////////////////////////
texture   Otis_BloomTarget 	{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;};	

//////////////////////////////////////
// samplers
//////////////////////////////////////
sampler2D Otis_BloomSampler { Texture = Otis_BloomTarget; };

// pixel shader which performs bloom, by CeeJay. 
void PS_Otis_AFG_PerformBloom(float4 position : SV_Position, float2 texcoord : TEXCOORD0, out float4 fragment: SV_Target0)
{
	float4 color = tex2D(ReShade::BackBuffer, texcoord);
	float3 BlurColor2 = 0;
	float3 Blurtemp = 0;
	float MaxDistance = 8*BloomWidth;
	float CurDistance = 0;
	float Samplecount = 25.0;
	float2 blurtempvalue = texcoord * ReShade::PixelSize * BloomWidth;
	float2 BloomSample = float2(2.5,-2.5);
	float2 BloomSampleValue;
	
	for(BloomSample.x = (2.5); BloomSample.x > -2.0; BloomSample.x = BloomSample.x - 1.0)
	{
		BloomSampleValue.x = BloomSample.x * blurtempvalue.x;
		float2 distancetemp = BloomSample.x * BloomSample.x * BloomWidth;
		
		for(BloomSample.y = (- 2.5); BloomSample.y < 2.0; BloomSample.y = BloomSample.y + 1.0)
		{
			distancetemp.y = BloomSample.y * BloomSample.y;
			CurDistance = (distancetemp.y * BloomWidth) + distancetemp.x;
			BloomSampleValue.y = BloomSample.y * blurtempvalue.y;
			Blurtemp.rgb = tex2D(ReShade::BackBuffer, float2(texcoord + BloomSampleValue)).rgb;
			BlurColor2.rgb += lerp(Blurtemp.rgb,color.rgb, sqrt(CurDistance / MaxDistance));
		}
	}
	BlurColor2.rgb = (BlurColor2.rgb / (Samplecount - (BloomPower - BloomThreshold*5)));
	float Bloomamount = (dot(color.rgb,float3(0.299f, 0.587f, 0.114f)));
	float3 BlurColor = BlurColor2.rgb * (BloomPower + 4.0);
	color.rgb = lerp(color.rgb,BlurColor.rgb, Bloomamount);	
	fragment = saturate(color);
}


void PS_Otis_AFG_BlendFogWithNormalBuffer(float4 vpos: SV_Position, float2 texcoord: TEXCOORD, out float4 fragment: SV_Target0)
{
	float depth = ReShade::GetLinearizedDepth(texcoord).r;
	float fogFactor = clamp(saturate(depth - FogStart) * FogCurve, 0.0, MaxFogFactor); 
	fragment = lerp(tex2D(ReShade::BackBuffer, texcoord), lerp(tex2D(Otis_BloomSampler, texcoord), float4(FogColor, 1.0), fogFactor), fogFactor);
}

technique SkyFog
{
	pass Otis_SFG_PassBloom0
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_AFG_PerformBloom;
		RenderTarget = Otis_BloomTarget;
	}
	
	pass Otis_SFG_PassBlend
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_AFG_BlendFogWithNormalBuffer;
	}
}
