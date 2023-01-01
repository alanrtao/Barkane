//UNITY_SHADER_NO_UPGRADE
#ifndef RAYMARCH_INCLUDE
#define RAYMARCH_INCLUDE

// Includes referenced from generated shader
#ifdef UNIVERSAL_LIGHTING_INCLUDED
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#endif

#include "./Panoramic.cginc"
#include "./noiseSimplex.cginc"

const static int bayer_n = 4;
const static float bayer_matrix_4x4[][bayer_n] = {
	{    -0.5,       0,  -0.375,   0.125 },
	{    0.25,   -0.25,   0.375, -0.125 },
	{ -0.3125,  0.1875, -0.4375,  0.0625 },
	{  0.4375, -0.0625,  0.3125, -0.1875 },
};

const static uint steps = 4;
const static float r = .5; // unity uses [-1, 1] object space, but unity's default sphere is .5 radius

float densityDrop(
	float3 p,
	float dropoff
) {
	float sq = dot(p, p);
	float t = sq / r;
	return exp(-dropoff * t) - exp(-dropoff); // the subtraction makes sure it is zeroed at 1
}

// Beer's law
float beer(float l) {
	return exp(-l);
}

float hg(float cosa, float g) {
	float g2 = g * g;
	return (1 - g2) / (4 * 3.1415 * pow(1 + g2 - 2 * g * cosa, 1.5));
}

// https://www.oceanopticsbook.info/view/scattering/level-2/the-henyey-greenstein-phase-function
// here gBias is an ambient factor not mentioned in the original
float twoTermHG(float t, float g1, float g2, float cosa, float gBias) {
	return lerp(hg(cosa, g1), hg(cosa, -g2), t) + gBias;
}

// dithering
float bayer(float2 px, float t) {
	uint2 ipx = floor(px);
	return t > bayer_matrix_4x4[ipx.x % 4][ipx.y % 4] ? 1 : 0;
}

float densityAt(
	UnitySamplerState worleyState,
	UnityTexture3D worley,
	float4 weights,
	float3 p,
	float scl,
	float baseDensity,
	float densityDropoff
) {

	float3 pWorld = mul(unity_ObjectToWorld, float4(p, 1)).xyz;
	pWorld = pWorld * scl;

	return baseDensity 
		* (weights.x + weights.y
			// originally the negation is built into the worley generation shader
			// it is moved here to make the worley noise texture itself more usable elsewhere
			- weights.x * worley.Sample(worleyState, pWorld).r
			- weights.y * worley.Sample(worleyState, pWorld).g)
		* densityDrop(p, densityDropoff);
}

float march(
	UnitySamplerState worleyState,
	UnityTexture3D worley,
	float4 weights,
	float scl,
	float3 p,
	float3 l,
	float sunAbsorption,
	float baseDensity,
	float densityDropoff
) {
	// same indicator as below
	float I = dot(l, p);
	float end = -I;

	I = I * I - dot(p, p) + r * r;
	if (I < 0) return 1;

	// length between base point and exit point of the light ray in the sphere
	end += sqrt(I);
	const float stepSize = end / steps;
	float mass = 0;

	for (uint i = 0; i < steps; i++) {
		float t = stepSize * (i + 1);
		float3 samplePt = p + l * t;

		mass += stepSize * densityAt(
			worleyState,
			worley,
			weights,
			samplePt,
			scl,
			baseDensity,
			densityDropoff
		);
	}

	return beer(mass * sunAbsorption);
}

float3 weigh(float3 weights, float4 color) {
	return float3(weights.x * color.x, weights.y * color.y, weights.z * color.z);
}

float3 weigh(float3 weights, float3 color) {
	return float3(weights.x * color.x, weights.y * color.y, weights.z * color.z);
}

void RaySampler_float(
	float3 p,
	float3 v,
	float3 l,

	UnitySamplerState worleyState,
	UnityTexture3D worley,
	UnityTexture2D panoramic,

	float scl,
	float4 weights,

	float sunAbsorption,
	float cloudAbsorption,
	float g1,
	float g2,
	float gBias,
	float ltBias,

	float baseDensity,
	float densityDropoff,

	float cutoff,

	float2 px,
	float2 px01,

	float depth,

	out float opacity,
	out float3 cloudColor
) {
	v = -v;

	float I = dot(v, p);
	float end = -I;

	I = I * I - dot(p, p) + r * r;
	if (I < 0) discard;
	end += sqrt(I);

	// borrows from Sebastian Lague's
	// https://github.com/SebLague/Clouds/blob/master/Assets/Scripts/Clouds/Shaders/Clouds.shader
	float3 energy = 0;
	float transmittance = 1;

	const float cosa = dot(v, l);
	const float phaseVal = twoTermHG(0.5, g1, g2, cosa, gBias);

	// note this is still in object space! this make per-object light absorption *consitent* but not physical
	const float stepSize = end / steps;

	const float3 pWorld = mul(unity_ObjectToWorld, float4(p, 1)).xyz;

	for (uint i = 0; i < steps; i++) {
		const float t = stepSize * (i + 1); 
		const float3 pSample = p + t * v;

		float density = densityAt(
			worleyState,
			worley,
			weights,
			pSample,
			scl,
			baseDensity,
			densityDropoff
		);

		float mass = density * stepSize;

		float lightTransmittance = march(
			worleyState,
			worley,

			weights,
			scl,

			pSample,
			l,

			sunAbsorption,
			baseDensity,
			densityDropoff
		);

		energy += stepSize * density * transmittance * (lightTransmittance * (1 - ltBias) + ltBias) * phaseVal;
		transmittance *= beer(mass * cloudAbsorption);
	}

	if (transmittance > cutoff) {
		int2 ipx = floor(px);
		transmittance = bayer(px, transmittance - 0.1) + depth * 0.05; // attenuate the dithering to exclude far items, avoids some aliasing artifacts
	}

	transmittance = saturate(transmittance);
	opacity = 1 - transmittance;
	
	float4 backgroundColor;
	panoramic_float(mul(unity_ObjectToWorld, float4(v, 0)).xyz, worleyState, panoramic, backgroundColor);

	cloudColor = backgroundColor.xyz * transmittance + energy;
}

#endif 