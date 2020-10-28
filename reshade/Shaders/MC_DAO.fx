/*
 	Disk Ambient Occlusion by Constantine 'MadCake' Rudenko

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
	ui_min = 0.0; ui_max = 8.0; ui_step = 0.1;
	ui_tooltip = "Strength of the effect (recommended 0.6)";
	ui_label = "Strength";
> = 1.0;

uniform int SampleDistance < __UNIFORM_SLIDER_INT1
	ui_min = 1; ui_max = 64;
	ui_tooltip = "Sampling disk radius (in pixels)\nrecommended: 32";
	ui_label = "Sampling disk radius";
> = 32.0;

uniform int NumSamples < __UNIFORM_SLIDER_INT1
	ui_min = 1; ui_max = 32;
	ui_tooltip = "Number of samples (higher numbers give better quality at the cost of performance)\nrecommended: 8";
	ui_label = "Number of samples";
> = 8;

uniform float ReduceRadiusJitter < __UNIFORM_SLIDER_INT1
	ui_min = 0; ui_max = 1; ui_step = 0.1;
	ui_tooltip = "Less accurate AO, but also less noisy.\nrecommended: 0.2";
	ui_label = "Limit radius jitter";
> = 0.2;

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

uniform int BlurRadius < __UNIFORM_SLIDER_INT1
	ui_min = 1.0; ui_max = 32.0;
	ui_tooltip = "Blur radius (in pixels)\nrecommended: 4 to 8";
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

sampler2D sAOTex { Texture = AOTex; };
sampler2D sAOTex2 { Texture = AOTex2; };

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

float rand2D(float2 uv){
	uv = frac(uv);
	float x = frac(cos(uv.x*64)*256);
	float y = frac(cos(uv.y*137)*241);
	float z = x+y;
	return frac(cos((z)*107)*269);
}

float3 BlurAOHorizontalPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float range = clamp(BlurRadius, 1, 32);

	float tmp = 1.0 / (range * range);
	float gauss = 1.0;
	float helper = exp(tmp * 0.5);
	float helper2 = exp(tmp);
	float sum = tex2D(sAOTex, texcoord).r;
	float sumCoef = 1.0;
	
	float blurQuality = clamp(BlurQuality, 0.0, 1.0);
	range *= 3.0 * blurQuality;

	float2 off = float2(BUFFER_PIXEL_SIZE.x, 0);
	
	[loop]
	for(int k = 1; k < range; k++){
		gauss = gauss / helper;
		helper = helper * helper2;
		sumCoef += gauss * 2.0;
		sum += tex2D(sAOTex, texcoord + off * k).r * gauss;
		sum += tex2D(sAOTex, texcoord - off * k).r * gauss;
	}
	
	return sum / sumCoef;
}


float3 BlurAOVerticalPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float range = clamp(BlurRadius, 1, 32);

	float tmp = 1.0 / (range * range);
	float gauss = 1.0;
	float helper = exp(tmp * 0.5);
	float helper2 = exp(tmp);
	float sum = tex2D(sAOTex2, texcoord).r;
	float sumCoef = 1.0;
	
	float blurQuality = clamp(BlurQuality, 0.0, 1.0);
	range *= 3.0 * blurQuality;

	float2 off = float2(0, BUFFER_PIXEL_SIZE.y);
	
	[loop]
	for(int k = 1; k < range; k++){
		gauss = gauss / helper;
		helper = helper * helper2;
		sumCoef += gauss * 2.0;
		sum += tex2D(sAOTex2, texcoord + off * k).r * gauss;
		sum += tex2D(sAOTex2, texcoord - off * k).r * gauss;
	}
	
	sum = sum / sumCoef;
	
	if (DebugEnabled == 2)
	{
		return tex2D(sAOTex, texcoord).r;
	}
	
	if (DebugEnabled == 1)
	{
		return sum;
	}
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color *= sum;
	return color;
}

float2 ensure_1px_offset(float2 ray)
{
	float2 ray_in_pixels = ray / BUFFER_PIXEL_SIZE;
	float coef = max(abs(ray_in_pixels.x), abs(ray_in_pixels.y));
	if (coef < 1.0)
	{
		ray /= coef;
	}
	return ray;
}

float3 MadCakeDiskAOPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{	
	float3 position = GetPosition(texcoord);
	float3 normal = GetNormalFromDepth(texcoord);
	
	int num_samples = clamp(NumSamples, 1, 64);
	int sample_dist = clamp(SampleDistance, 1, 128);
	float normal_bias = clamp(NormalBias, 0.0, 1.0);
	
	float occlusion = 0.0;
	float fade_range = EndFade - StartFade;
	
	float angle_jitter_minor = rand2D(texcoord);
	float angle_jitter_major = rand2D(texcoord + float2(-1, 0)) * 3.1415 * 2.0 * 0.0;

	[loop]
	for (int i = 0; i < num_samples; i++)
	{
		float angle = 3.1415 * 2.0 / num_samples * (i + angle_jitter_minor) + angle_jitter_major;
		float2 ray;
		ray.x = sin(angle);
		ray.y = cos(angle);
		ray *= BUFFER_PIXEL_SIZE * sample_dist;
		ray /= 1.0 + position.z * lerp(0, 0.05, pow(DepthShrink,4));
		float radius_coef = 1.0;
		float radius_jitter = rand2D(texcoord + float2(i, 1));
		ray *= lerp(max(0.01,ReduceRadiusJitter), 1.0, radius_jitter);
		ray = ensure_1px_offset(ray);
		float2 sample_coord = texcoord + ray;
		float3 sampled_position = GetPosition(sample_coord);
		float3 v = sampled_position - position;
		float ray_occlusion = dot(normal, normalize(v));
		ray_occlusion = max(ray_occlusion, 0.0);	// not just warning suppression, leave it be!
		ray_occlusion = pow (ray_occlusion, NormalPower);
		ray_occlusion = (ray_occlusion - normal_bias) / (1.0 - normal_bias);
		float zdiff = abs(v.z);
		if (zdiff >= StartFade)
		{
			ray_occlusion *= saturate(1.0 - (zdiff - StartFade) / fade_range);
		}
		occlusion += ray_occlusion / num_samples;
	}
	occlusion *= saturate(1.0 - (position.z / DepthEndFade));
	occlusion = saturate(1.0 - occlusion * Strength);
	return pow(occlusion, Gamma);
}

technique MC_DAO
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = MadCakeDiskAOPass;
		RenderTarget0 = AOTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurAOHorizontalPass;
		RenderTarget0 = AOTex2;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurAOVerticalPass;
	}
}
