/*
	SSAO by Constantine 'MadCake' Rudenko
 	
		based on HBAO (Horizon Based Ambient Occlusion)
		https://developer.download.nvidia.com/presentations/2008/SIGGRAPH/HBAO_SIG08b.pdf

	License: https://creativecommons.org/licenses/by/4.0/
	CC BY 4.0
	
	You are free to:

	Share — copy and redistribute the material in any medium or format
		
	Adapt — remix, transform, and build upon the material
	for any purpose, even commercially.

	The licensor cannot revoke these freedoms as long as you follow the license terms.
		
	Under the following terms:

	Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. 
	You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.

	No additional restrictions — You may not apply legal terms or technological measures 
	that legally restrict others from doing anything the license permits.
*/

#include "ReShadeUI.fxh"

uniform float Strength < __UNIFORM_DRAG_FLOAT1
	ui_min = 0.0; ui_max = 16.0; ui_step = 0.1;
	ui_tooltip = "Strength of the effect (recommended 1.0 to 2.0)";
	ui_label = "Strength";
> = 2.0;

uniform int SampleDistance < __UNIFORM_SLIDER_INT1
	ui_min = 1; ui_max = 64;
	ui_tooltip = "Sampling disk radius (in pixels)\nrecommended: 32";
	ui_label = "Sampling disk radius";
> = 32.0;

uniform int Quality <
	ui_type = "combo";
	ui_label = "Total number of samples";
	ui_tooltip = "Higher numbers yield better quality at the cost of performance\nrecommended: 8";
	ui_items = "Samples: 4\0Samples: 8\0Samples: 16\0Samples: 24\0Samples: 32\0Samples: 36\0Samples: 48\0Samples: 64\0";
> = 1;

uniform float StartFade < __UNIFORM_DRAG_FLOAT1
	ui_min = 0.0; ui_max = 300.0; ui_step = 0.1;
	ui_tooltip = "AO starts fading when Z difference is greater than this\nmust be bigger than \"Z difference end fade\"\nrecommended: 0.4";
	ui_label = "Z difference start fade";
> = 0.4;

uniform float EndFade < __UNIFORM_DRAG_FLOAT1
	ui_min = 0.0; ui_max = 300.0; ui_step = 0.1;
	ui_tooltip = "AO completely fades when Z difference is greater than this\nmust be bigger than \"Z difference start fade\"\nrecommended: 0.6";
	ui_label = "Z difference end fade";
> = 0.6;

uniform float NormalBias < __UNIFORM_DRAG_FLOAT1
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.025;
	ui_tooltip = "prevents self occlusion (recommended 0.1)";
	ui_label = "Normal bias";
> = 0.1;

uniform int DebugEnabled <
        ui_type = "combo";
        ui_label = "Enable Debug View";
        ui_items = "Disabled\0Blurred\0Before Blur\0";
> = 0;

uniform int Bilateral <
        ui_type = "combo";
        ui_label = "Fake bilateral filter";
        ui_items = "Don't use (cheaper)\0Vertical first\0Horizontal first\0";
> = 0;

uniform int BlurRadius < __UNIFORM_SLIDER_INT1
	ui_min = 1.0; ui_max = 32.0;
	ui_tooltip = "Blur radius (in pixels)\nrecommended: 3 or 4";
	ui_label = "Blur radius";
> = 4.0;

uniform float BlurQuality < __UNIFORM_DRAG_FLOAT1
		ui_min = 0.5; ui_max = 1.0; ui_step = 0.1;
		ui_label = "Blur Quality";
		ui_tooltip = "Blur quality (recommended 0.6)";
> = 0.6;

uniform float Gamma < __UNIFORM_DRAG_FLOAT1
		ui_min = 1.0; ui_max = 4.0; ui_step = 0.1;
		ui_label = "Gamma";
        ui_tooltip = "Recommended 2.2\n(assuming the texture is stored with gamma applied)";
> = 2.2;

uniform float NormalPower < __UNIFORM_DRAG_FLOAT1
		ui_min = 0.5; ui_max = 8.0; ui_step = 0.1;
		ui_label = "Normal power";
        ui_tooltip = "Acts like softer version of normal bias without a threshold\nrecommended: 1.4";
> = 1.4;

uniform int FOV < __UNIFORM_DRAG_FLOAT1
		ui_min = 40; ui_max = 180; ui_step = 1.0;
		ui_label = "FOV";
        ui_tooltip = "Leaving it at 90 regardless of your actual FOV provides accetable results";
> = 90;

uniform float DepthShrink < __UNIFORM_DRAG_FLOAT1
		ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
		ui_label = "Depth shrink";
        ui_tooltip = "Higher values cause AO to become finer on distant objects\nrecommended: 0.65";
> = 0.65;


// DepthStartFade does not change much visually

/*
uniform float DepthStartFade < __UNIFORM_DRAG_FLOAT1
		ui_min = 0.0; ui_max = 4000.0; ui_step = 1.0;
		ui_label = "Depth start fade";
        ui_tooltip = "Start fading AO at this Z value";
> = 0.0;
*/

uniform int DepthEndFade < __UNIFORM_DRAG_FLOAT1
		ui_min = 0; ui_max = 4000;
		ui_label = "Depth end fade";
        ui_tooltip = "AO completely fades at this Z value\nrecommended: 1000";
> = 1000;


#include "ReShade.fxh"

texture2D AOTex	{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = R8; MipLevels = 1;};
texture2D AOTex2	{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = R8; MipLevels = 1;};
texture2D NormalTex	{ Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RGBA8; MipLevels = 1;};

sampler2D sAOTex { Texture = AOTex; };
sampler2D sAOTex2 { Texture = AOTex2; };
sampler2D sNormalTex { Texture = NormalTex; };

float GetTrueDepth(float2 coords)
{
	return ReShade::GetLinearizedDepth(coords) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE;
}

float3 GetPosition(float2 coords)
{
	float2 fov;
	fov.x = FOV / 180.0 * 3.1415;
	fov.y = fov.x / BUFFER_ASPECT_RATIO; 
	float3 pos;
	pos.z = GetTrueDepth(coords.xy);
	coords.y = 1.0 - coords.y;
	pos.xy = coords.xy * 2.0 - 1.0;
	float2 h;
	h.x	= 1.0 / tan(fov.x * 0.5);
	h.y = 1.0 / tan(fov.y * 0.5);
	pos.xy /= h / pos.z;
	return pos;
}

float3 GetNormalFromDepth(float2 coords) 
{
	float3 centerPos = GetPosition(coords);
	
	float2 offx = float2(BUFFER_PIXEL_SIZE.x, 0);
	float2 offy = float2(0, BUFFER_PIXEL_SIZE.y);
	
	float3 ddx1 = GetPosition(coords + offx) - centerPos;
	float3 ddx2 = centerPos - GetPosition(coords - offx);

	float3 ddy1 = GetPosition(coords + offy) - centerPos;
	float3 ddy2 = centerPos - GetPosition(coords - offy);
	
	ddx1 = ddx1 + ddx2;
	ddy1 = ddy1 + ddy2;

	float3 normal = cross(ddx1, ddy1);
	
	return normalize(normal);
}

float4 GetNormalFromTexture(float2 coords)
{
	float4 normal = tex2D(sNormalTex, coords);
	normal.xyz = normal.xyz * 2.0 - float3(1,1,1);
	return normal;
}

float rand2D(float2 uv){
	uv = frac(uv);
	float x = frac(cos(uv.x*64)*256);
	float y = frac(cos(uv.y*137)*241);
	float z = x+y;
	return frac(cos((z)*107)*269);
}

float3 CalculateNormalsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	return GetNormalFromDepth(texcoord) * 0.5 + 0.5;
}

float3 BlurAOFirstPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	int debugEnabled = clamp(DebugEnabled, 0, 2);
	
	[branch]
	if (debugEnabled == 2)
	{
		return tex2D(sAOTex, texcoord).r;
	}

	float normal_bias = clamp(NormalBias, 0.0, 1.0);

	float range = clamp(BlurRadius, 1, 32);
	float fade_range = EndFade - StartFade;

	float tmp = 1.0 / (range * range);
	float gauss = 1.0;
	float helper = exp(tmp * 0.5);
	float helper2 = exp(tmp);
	float sum = tex2D(sAOTex, texcoord).r;
	float sumCoef = 1.0;
	
	float blurQuality = clamp(BlurQuality, 0.0, 1.0);
	range *= 3.0 * blurQuality;
	
	float2 off = float2(BUFFER_PIXEL_SIZE.x, 0);
	
	float4 my_normal;
	
	[branch]
	if (Bilateral)
	{
		my_normal = GetNormalFromTexture(texcoord);
	}
	
	[branch]
	if (Bilateral == 2)
	{
		off = float2(0, BUFFER_PIXEL_SIZE.y);
	}
	
	float weights[32];
	weights[0] = 1;
	
	[unroll]
	for (int i = 1; i < 32; i++)
	{
		gauss = gauss / helper;
		helper = helper * helper2;
		weights[i] = gauss;
	}
	
	[loop]
	for(int k = 1; k < range; k++)
	{
		float weight = weights[abs(k)];
		
		if (Bilateral)
		{
			float4 normal = GetNormalFromTexture(texcoord + off * k);
			weight *= saturate((dot(my_normal.xyz, normal.xyz) - normal_bias) / (1.0 - normal_bias));
			float zdiff = abs(my_normal.w - normal.w);
			[flatten]
			if (zdiff >= StartFade)
			{
				weight *= saturate(1.0 - (zdiff - StartFade) / fade_range);
			}
			weight *= abs(my_normal.z - normal.z);
			sum += tex2D(sAOTex, texcoord + off * k).r * weight;
			sumCoef += weight;
		}
		else
		{
			sum += tex2D(sAOTex, texcoord + off * k).r * weight;
			sumCoef += weight;
		}
	}
	
	[loop]
	for(int k = 1; k < range; k++)
	{
		float weight = weights[abs(k)];
		
		[branch]
		if (Bilateral)
		{
			float4 normal = GetNormalFromTexture(texcoord - off * k);
			weight *= max(0.0, dot(my_normal.xyz, normal.xyz));
			float zdiff = abs(my_normal.w - normal.w);
			[flatten]
			if (zdiff >= StartFade)
			{
				weight *= saturate(1.0 - (zdiff - StartFade) / fade_range);
			}
			sum += tex2D(sAOTex, texcoord - off * k).r * weight;
			sumCoef += weight;
		}
		else
		{
			sum += tex2D(sAOTex, texcoord - off * k).r * weight;
			sumCoef += weight;
		}
	}
	
	return sum / sumCoef;
}


float3 BlurAOSecondPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	int debugEnabled = clamp(DebugEnabled, 0, 2);
	
	[branch]
	if (debugEnabled == 2)
	{
		return tex2D(sAOTex2, texcoord).r;
	}

	float normal_bias = clamp(NormalBias, 0.0, 1.0);

	float range = clamp(BlurRadius, 1, 32);
	float fade_range = EndFade - StartFade;

	float tmp = 1.0 / (range * range);
	float gauss = 1.0;
	float helper = exp(tmp * 0.5);
	float helper2 = exp(tmp);
	float sum = tex2D(sAOTex, texcoord).r;
	float sumCoef = 1.0;
	
	float blurQuality = clamp(BlurQuality, 0.0, 1.0);
	range *= 3.0 * blurQuality;
	
	float2 off = float2(0, BUFFER_PIXEL_SIZE.y);
	
	float4 my_normal;
	[branch]
	if (Bilateral)
	{
		my_normal = GetNormalFromTexture(texcoord);
	}
	
	[branch]
	if (Bilateral == 2)
	{
		off = float2(BUFFER_PIXEL_SIZE.x, 0);
	}
	
	float weights[32];
	weights[0] = 1;
	
	[unroll]
	for (int i = 1; i < 32; i++)
	{
		gauss = gauss / helper;
		helper = helper * helper2;
		weights[i] = gauss;
	}
	
	[loop]
	for(int k = 1; k < range; k++)
	{
		float weight = weights[abs(k)];
		
		if (Bilateral)
		{
			float4 normal = GetNormalFromTexture(texcoord + off * k);
			weight *= max(0.0, dot(my_normal.xyz, normal.xyz));
			float zdiff = abs(my_normal.w - normal.w);
			[flatten]
			if (zdiff >= StartFade)
			{
				weight *= saturate(1.0 - (zdiff - StartFade) / fade_range);
			}
			sum += tex2D(sAOTex2, texcoord + off * k).r * weight;
			sumCoef += weight;
		}
		else
		{
			sum += tex2D(sAOTex2, texcoord + off * k).r * weight;
			sumCoef += weight;
		}
	}
	
	[loop]
	for(int k = 1; k < range; k++)
	{
		float weight = weights[abs(k)];
		
		if (Bilateral)
		{
			float4 normal = GetNormalFromTexture(texcoord - off * k);
			weight *= saturate((dot(my_normal.xyz, normal.xyz) - normal_bias) / (1.0 - normal_bias));
			float zdiff = abs(my_normal.w - normal.w);
			if (zdiff >= StartFade)
			{
				weight *= saturate(1.0 - (zdiff - StartFade) / fade_range);
			}
			sum += tex2D(sAOTex2, texcoord - off * k).r * weight;
			sumCoef += weight;
		}
		else
		{
			sum += tex2D(sAOTex2, texcoord - off * k).r * weight;
			sumCoef += weight;
		}
	}
	
	[branch]
	if (debugEnabled)
	{
		return sum / sumCoef;
	}
	else
	{
		float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
		return color * sum / sumCoef;
	}
}

float2 ensure_1px_offset(float2 ray)
{
	float2 ray_in_pixels = ray / BUFFER_PIXEL_SIZE;
	float coef = max(abs(ray_in_pixels.x), abs(ray_in_pixels.y));
	[flatten]
	if (coef < 1.0)
	{
		ray /= coef;
	}
	return ray;
}

void SSAOPass(in float4 vpos : SV_Position, in float2 texcoord : TexCoord, out float occlusion : SV_Target0, out float4 normal : SV_Target1)
{	
	float3 position = GetPosition(texcoord);
	normal = GetNormalFromDepth(texcoord);
	
	int quality = clamp(Quality, 0, 7);
	
	int num_angle_samples;
	int num_distance_samples;
	
	[branch]
	switch(quality)
	{
		case 0:
			num_angle_samples = 4;
			num_distance_samples = 1;
			break;
		case 1:
			num_angle_samples = 4;
			num_distance_samples = 2;
			break;
		case 2:
			num_angle_samples = 4;
			num_distance_samples = 4;
			break;
		case 3:
			num_angle_samples = 6;
			num_distance_samples = 4;
			break;
		case 4:
			num_angle_samples = 8;
			num_distance_samples = 4;
			break;
		case 5:
			num_angle_samples = 6;
			num_distance_samples = 6;
			break;
		case 6:
			num_angle_samples = 8;
			num_distance_samples = 6;
			break;
		case 7:
			num_angle_samples = 8;
			num_distance_samples = 8;
			break;
	}
	
	int sample_dist = clamp(SampleDistance, 1, 128);
	float normal_bias = clamp(NormalBias, 0.0, 1.0);
	
	occlusion = 0.0;
	float fade_range = EndFade - StartFade;
	
	float angle_jitter = rand2D(texcoord) * 3.1415 * 2.0;

	[loop]
	for (int i = 0; i < num_angle_samples; i++)
	{
		float angle = 3.1415 * 2.0 / num_angle_samples * i + angle_jitter;
		
		float2 ray;
		ray.x = sin(angle);
		ray.y = cos(angle);
		ray *= BUFFER_PIXEL_SIZE * sample_dist;
		ray /= 1.0 + position.z * lerp(0, 0.05, pow(DepthShrink,4));
		
		float angle_occlusion = 0.0;
		
		[loop]
		for (int k = 0; k < num_distance_samples; k++)
		{
			float radius_jitter = rand2D(texcoord + float2(i, 1));
			float radius_coef = (k + 1.0 - radius_jitter) / num_distance_samples;
			radius_coef = max(radius_coef, 0.01);
			float2 scaled_ray = ensure_1px_offset(ray * radius_coef);
			float2 sample_coord = texcoord + scaled_ray;
			float3 sampled_position = GetPosition(sample_coord);
			float3 v = sampled_position - position;
			float ray_occlusion = dot(normal.xyz, normalize(v));
			ray_occlusion = max(ray_occlusion, 0.0);	// not just warning suppression, leave it be!
			ray_occlusion = pow (ray_occlusion, NormalPower);
			ray_occlusion = saturate((ray_occlusion - normal_bias) / (1.0 - normal_bias));
			float zdiff = abs(v.z);
			[flatten]
			if (zdiff >= StartFade)
			{
				ray_occlusion *= saturate(1.0 - (zdiff - StartFade) / fade_range);
			}

			float fade_coef = float(num_distance_samples - k) / num_distance_samples;
			fade_coef *= fade_coef;
			angle_occlusion = max(angle_occlusion, ray_occlusion * fade_coef);
		}
		
		occlusion += angle_occlusion;
	}
	occlusion /=  num_angle_samples * 2.0;
	occlusion *= saturate(1.0 - (position.z / DepthEndFade));
	occlusion = saturate(1.0 - occlusion * Strength);
	occlusion = pow(occlusion, Gamma);
	
	normal = normal * 0.5 + 0.5;
	normal.z = position.z;
}

technique MC_DAO
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = SSAOPass;
		RenderTarget0 = AOTex;
		RenderTarget1 = NormalTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurAOFirstPass;
		RenderTarget0 = AOTex2;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurAOSecondPass;
		//RenderTarget0 = AOTex;
	}/*
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurAOThirdPass;
	}*/
}
