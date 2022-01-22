#include "Packages/jp.keijiro.noiseshader/Shader/SimplexNoise3D.hlsl"
#include "Packages/jp.keijiro.noiseshader/Shader/ClassicNoise3D.hlsl"

void SimplexNoise3D_float (float3 uv, float scale, out float noise)
{
	noise = SimplexNoise(uv / scale);
}
void ClassicNoise3D_float (float3 uv, float scale, out float noise)
{
	noise = ClassicNoise(uv / scale);
}