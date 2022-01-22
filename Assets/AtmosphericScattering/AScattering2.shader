Shader "Universal Render Pipeline/Custom/AScattering2"
{
    Properties
    {
        [MainColor] _BaseColor("BaseColor", Color) = (1,1,1,1)
        [MainTexture] _MainTex("Main Tex", 2D) = "white" {}
//        _BakedOpticalDepth("Main Tex", 2D) = "white" {}
//    	_ScatteringPoints("ScatteringPoints", int) = 10
//    	_OpticalDepthPoints("Optical Depth Points", int) = 10
//    	_DensityFalloff("Density Falloff", float) = 10
//    	_AtmosphereRadius("Atmosphere Radius", float) = 10
//    	_PlanetSize("Planet Size", float) = 3
    	_PlanetLocation("Planet Location", Vector) = (0,0,0, 0)
    	_AtmosphereHeight("Atmosphere Height", Range(0,10)) = 1
    	_DepthDistance("Depth Distance", float) = 100
    	_SunLightScattering("Sun Light Scattering", Range(0,1)) = 0.5
    	_VolumetricShadowPower("Shadow Power", float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalRenderPipeline"}

        // Include material cbuffer for all passes. 
        // The cbuffer has to be the same for all passes to make this shader SRP batcher compatible.
        HLSLINCLUDE
        
        
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST; 
        half4 _BaseColor;
        CBUFFER_END

        ENDHLSL

        Pass
        {
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 uv           : TEXCOORD0;
                float4 positionHCS  : SV_POSITION;
                float3 viewVector : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float3 positionOS : TEXCOORD3;
            	float3 worldPos : TEXCOORD4;
            	float2 screenPos : TEXCOORD5;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

			TEXTURE2D(_BakedOpticalDepth);
			SAMPLER(sampler_BakedOpticalDepth);
            
            TEXTURE2D(_BlueNoise);
			SAMPLER(sampler_BlueNoise);
            
            int _ScatteringPoints;
            int _OpticalDepthPoints;
            float _DensityFalloff;
            float _PlanetSize;
            float _AtmosphereHeight;
            float _DepthDistance;			
            float3 _PlanetLocation;			

            // float atmosphereScale;
            float _AtmosphereRadius;
			float4 scatteringCoefficients;
            
			float3 sunDirection;
            float _SunLightScattering;
            float _VolumetricShadowPower;


            float _LightPower;
			int _LightDistance;
            int _LightStepSize;
			int _ShadowStepSize;
			int _ShadowSteps;
            
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
            	VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
            	OUT.screenPos = ComputeScreenPos(positionInputs.positionCS);
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                // OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz); 
                OUT.positionWS = positionInputs.positionWS;
                OUT.positionOS = IN.positionOS.xyz;
                // OUT.uv.xy = TRANSFORM_TEX(IN.uv, _BaseMap);
				OUT.uv.xy = UnityStereoTransformScreenSpaceTex(IN.uv);
            	float4 projPos = OUT.positionHCS * 0.5;
				OUT.uv.zw = projPos.xy;
                float3 viewVector = mul(unity_CameraInvProjection, float4(IN.uv.xy * 2 - 1, 0, -1));
				OUT.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));
                OUT.worldPos =  mul (unity_ObjectToWorld, IN.uv);
            	
                return OUT;
            }
            float3 sunDir;
            // float planetSize = 3;
			// Calculate densities $\rho$.
			// Returns vec2(rho_rayleigh, rho_mie)
			// Note that intro version is more complicated and adds clouds by abusing Mie scattering density. That's why it's a separate function
			float2 densitiesRM(float3 p)
            {
				float h = max(0., length(p - _PlanetLocation) - _AtmosphereRadius); // calculate height from Earth surface
				// float height01 = (h / ( atmosphereScale - _PlanetSize) );
				return float2(exp(-h/8e3), exp(-h/12e2));
			}
            
			float Unity_Dither_float4(float2 ScreenPosition)
			{
				float2 uv = ScreenPosition.xy * _ScreenParams.xy;
				float DITHER_THRESHOLDS[16] =
				{
					1.0 / 17.0,  9.0 / 17.0,  3.0 / 17.0, 11.0 / 17.0,
					13.0 / 17.0,  5.0 / 17.0, 15.0 / 17.0,  7.0 / 17.0,
					4.0 / 17.0, 12.0 / 17.0,  2.0 / 17.0, 10.0 / 17.0,
					16.0 / 17.0,  8.0 / 17.0, 14.0 / 17.0,  6.0 / 17.0
				};
				uint index = (uint(uv.x) % 4) * 4 + uint(uv.y) % 4;
				return DITHER_THRESHOLDS[index];
			}

   //          float Blur(float inColor)
			// {
			// 	float color = inColor;
			// 	float Pi = 6.28318530718;
			// 	float quality = 3.0;
			// 	for( float d=0.0; d<Pi; d+=Pi/16)
			// 	{
			// 		for(float i=1.0/quality; i<=1.0; i+=1.0/quality)
			// 		{
			// 			color += texture( iChannel0, uv+vec2(cos(d),sin(d))*Radius*i);		
			// 		}
			// 	}
			// }
			float NormalizedHeighValue(float3 samplePos)
            {

	            return (1-(samplePos.y) / (_AtmosphereHeight));
            }

            half ShadowAtten(float3 worldPosition)
			{
			        return MainLightRealtimeShadow(TransformWorldToShadowCoord(worldPosition));
			}


            half ShadowAtten2(float3 worldPosition)
			{
				half cascadeIndex = ComputeCascadeIndex(worldPosition);
				float4 coords = mul(_MainLightWorldToShadow[cascadeIndex], float4(worldPosition, 1.0));
				                           
				ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
				half4 shadowParams = GetMainLightShadowParams();
				float atten = SampleShadowmap(TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture), coords, shadowSamplingData, shadowParams, false);
				return  shadowParams.r + atten * (1 - shadowParams.r);
			}            

            static const float maxFloat = 3.402823466e+38;
            float2 raySphere(float3 sphereCentre, float sphereRadius, float3 rayOrigin, float3 rayDir)
            {
				// float3 offset = rayOrigin - sphereCentre;
				float3 offset = rayOrigin - sphereCentre;
				float a = 1; // Set to dot(rayDir, rayDir) if rayDir might not be normalized
				float b = 2 * dot(offset, rayDir);
				float c = dot (offset, offset) - sphereRadius * sphereRadius;
				float d = b * b - 4 * a * c; // Discriminant from quadratic formula
 
				// Number of intersections: 0 when d < 0; 1 when d = 0; 2 when d > 0
				if (d > 0) {
					float s = sqrt(d);
					float dstToSphereNear = max(0, (-b - s) / (2 * a));
					float dstToSphereFar = (-b + s) / (2 * a);

					// Ignore intersections that occur behind the ray
					if (dstToSphereFar >= 0) {
						return float2(dstToSphereNear, dstToSphereFar - dstToSphereNear);
					}
				}
				// Ray did not intersect sphere
				return float2(maxFloat, 0);
            	
			}
            
             float densityAtPoint(float3 samplePoint)
            {
            	float heightAboveSurface = length(samplePoint - _PlanetLocation ) - _PlanetSize;
            	float height01 = (heightAboveSurface / ( _AtmosphereRadius - _PlanetSize) );
            	float localDensity = exp(-height01 * _DensityFalloff) * (1 -height01);
            	
            	return localDensity;
            }

            float opticalDepth(float3 rayOrigin, float3 rayDir, float rayLength)
            {
				float3 densitySamplePoint = rayOrigin;
				float stepSize = rayLength / (_OpticalDepthPoints - 1);
				float opticalDepth = 0;

				for (int i = 0; i < _OpticalDepthPoints; i ++)
				{            		
					float localDensity = densityAtPoint(densitySamplePoint) ;

					opticalDepth += localDensity * stepSize;
					densitySamplePoint += rayDir * stepSize;
				}
				return opticalDepth;
			}

            float3 planetCentre = 0;
			float opticalDepthBaked(float3 rayOrigin, float3 rayDir)
            {
				float height = length(rayOrigin - planetCentre) - _PlanetSize;
				float height01 = saturate(height / (_AtmosphereRadius - _PlanetSize));

				// float uvX = 1 - (dot(normalize(rayOrigin - planetCentre), rayDir));
				float uvX = 1 - (dot(normalize(rayOrigin - planetCentre), rayDir) * .5 + .5);
				return SAMPLE_TEXTURE2D_LOD(_BakedOpticalDepth, sampler_BakedOpticalDepth, float4(uvX, height01,0,0), 0);
			}
            
            float opticalDepthBaked2(float3 rayOrigin, float3 rayDir, float rayLength)
            {
				float3 endPoint = rayOrigin + rayDir * rayLength;
				float d = dot(rayDir, normalize(rayOrigin-planetCentre));
				float opticalDepth = 0;

				const float blendStrength = 1.5;
				float w = saturate(d * blendStrength + .5);
				
				float d1 = opticalDepthBaked(rayOrigin, rayDir) - opticalDepthBaked(endPoint, rayDir);
				float d2 = opticalDepthBaked(endPoint, -rayDir) - opticalDepthBaked(rayOrigin, -rayDir);

				opticalDepth = lerp(d2, d1, w);
				return opticalDepth;
			}
            
            // float G_SCATTERING = 0;
			float ComputeScattering(float lightDotView)
			{
				float result = 1.0f - _SunLightScattering * _SunLightScattering;				
				result /= 4.0f * PI * pow(1.0f + _SunLightScattering * _SunLightScattering - (2.0f * _SunLightScattering) * lightDotView, 1.5f);
				// result /= 100.0f * PI * pow(1 + _SunLightScattering * _SunLightScattering - (2.0f * _SunLightScattering) * lightDotView, 1.5);
				return result; 				
			}
            
			const float3 bR = float3(58, 135, 331); // Rayleigh scattering coefficient
			// const float3 bR = float3(58e-7, 135e-7, 331e-7); // Rayleigh scattering coefficient
			const float3 bMs = float3(2e-5, 2e-5, 2e-5); // Mie scattering coefficients
			// const float3 bMe = bMs * 1.1;
            // float4 scatteringCoefficients;

            float3 _betaR = float3(1.95e-2, 1.1e-1, 2.94e-1); 
			float3 _betaM = float3(4e-2, 4e-2, 4e-2);

			float3 calcLightTest(float3 rayOrigin, float3 rayDir, float length, float3 originalCol, float3 wPos, float dist, float2 screenSpacePos)
            {

				
				float blueNoise = SAMPLE_TEXTURE2D(_BlueNoise, sampler_BlueNoise, screenSpacePos * 10);
				// blueNoise = (blueNoise ) * 1;
            	float rayLength = length;
            	// float rayDirLengthened = rayDir * length;
            	
            	float3 inScatterPoint = rayOrigin;
            	float stepSize = rayLength / (_ScatteringPoints -1);
            	// float3 lightDirection = normalize(_MainLightPosition.xyz);
            	// float Ldot = dot(normalize(rayDir), lightDirection);
            	// float4 color = 0;
            	// float4 color = Ldot;
            	float3 inScatteredLight = 0;
            	float viewRayOpticalDepth = 0;         	
            	float rayOpticalDepth = 0;         	
    //         	float sunDot = clamp(dot(rayDir, sunDir), 0.0, 1.0);
    // 			float sunDotSmall = pow( sunDot, 700.0 );
    // 			float sunDotlarge = (pow( sunDot, 2.0 ));
				// float3 inScatterPoint2 = _WorldSpaceCameraPos;
				// float3 I_R = 0;
				// float3 I_M = 0;
				for(int i = 0; i < _ScatteringPoints; i++)
            	{
					// float3 localSunDir = normalize(rayDir - sunDir);
					float sunRayLength = raySphere(_PlanetLocation, _AtmosphereRadius, inScatterPoint, sunDir).y;
					// float sunRayLength = raySphere(0, _AtmosphereHeight, inScatterPoint, localSunDir).y;
					// float sunRayOpticalDepth = opticalDepthBaked(inScatterPoint + sunDir, sunDir);
					rayOpticalDepth = opticalDepth(inScatterPoint, sunDir, sunRayLength);
					
					viewRayOpticalDepth = opticalDepth(inScatterPoint, -rayDir, stepSize * i);
					// viewRayOpticalDepth = opticalDepthBaked2(rayOrigin, rayDir, stepSize * i);
					// viewRayOpticalDepth = opticalDepthBaked(inScatterPoint + sunDir, sunDir);
					float localDensity = densityAtPoint(inScatterPoint);

					
					float3 transmittance = exp(-( rayOpticalDepth + viewRayOpticalDepth) * scatteringCoefficients);

					inScatteredLight += localDensity * transmittance;

					inScatterPoint += rayDir * stepSize;			
				}

				// float mu = dot(rayDir, sunDir);
				//
				// float3 bR = float3(58e-7, 135e-7, 331e-7);
				// float3 bMs = float3(58e-7, 135e-7, 331e-7) * 1.1;

				// float originalSunRayOpticalDepth = exp(-rayOpticalDepth);
				float originalColTransmittance = exp(-viewRayOpticalDepth);

				float sunPow = 0;

				// return blueNoise;
				float distTravelled = 0;
				float distTravelled2 = 0;
				
				float4x4 ditherPattern = {{ 0.1f, 0.5f, 0.125f, 0.625f},
					{ 0.75f, 0.22f, 0.875f, 0.375f},
					{ 0.1875f, 0.6875f, 0.0625f, 0.5625},
					{ 0.9375f, 0.4375f, 0.8125f, 0.3125}};	

				float ditherValue =Unity_Dither_float4(screenSpacePos);
				// blueNoise = (blueNoise) * (ditherValue * 0.1);
				// float stepSize2 = rayLength / _LightSteps;
				// float shadowStepSize = 3;
				// int steps = 100;
				// int stepsShadows = 200;
				// return ditherValue;
				// while(distTravelled < _LightDistance)
    //             {
				// 	// rayDir+= _LightStepSize * (ditherValue*10000);
    //
				// 	// rayDir *= ditherValue;
				// 	// wPos += ditherValue * 50;
    //                 float3 rayPos = wPos + rayDir * distTravelled;
    //                 // float3 rayPos2 = wPos + rayDir * distTravelled2 ;
    //
    //                 if(ShadowAtten(rayPos) > 0.01 &&  distTravelled < dist) 
    //                 {
    //
    //                 	sunPow += (ComputeScattering(dot(rayDir, sunDir)));
    //                 }					
    //
				// 	distTravelled += _LightStepSize ;
    //
				// 	 // float3 rayPos2 = wPos + rayDir * distTravelled2 ;
    //
    //  
				//  	// if(ShadowAtten(rayPos2) < 0.01 &&  distTravelled2 < dist)
				//  	// {
				//  	// 	sunPow -= (ComputeScattering(dot(rayDir, sunDir))) * _VolumetricShadowPower;
				//  	// }
				// 	
    //                 // distTravelled2 += shadowStepSize;
    //                 
    //             }
				
				// while(distTravelled2 < _ShadowSteps )
    //             {
    //                 float3 rayPos2 = wPos + rayDir * distTravelled2 ;
    //
    //  
				//  	if(ShadowAtten(rayPos2) < 0.01 &&  distTravelled2 < dist)
				//  	{
				//  		sunPow -= (ComputeScattering(dot(rayDir, sunDir))) * _VolumetricShadowPower;
				//  	}
				// 	
    //                 distTravelled2 += _ShadowStepSize;                    
    //             }
				
				//sunPow/= _LightDistance/_LightPower;
				//sunPow = clamp(sunPow, 0, 99);

				inScatteredLight *=  (scatteringCoefficients) * stepSize;
				// inScatteredLight += blueNoise * 0.01;
            	return originalCol  * originalColTransmittance  + inScatteredLight;
            	
            }

            
			// Basically a ray-sphere intersection. Find distance to where rays escapes a sphere with given radius.
			// Used to calculate length at which ray escapes atmosphere
			float escape(float3 p, float3 d, float R)
            {
				float3 v = p - float3(0, 0, 0);
				float b = dot(v, d);
				float det = b * b - dot(v, v) + R*R;
				if (det < 0.) return -1.;
				det = sqrt(det);
				float t1 = -b - det, t2 = -b + det;
				return (t1 >= 0.) ? t1 : t2;
			}
             float Dither17(float2 Pos, float FrameIndexMod4)
		      {
		          // 3 scalar float ALU (1 mul, 2 mad, 1 frac)
		          return frac(dot(float3(Pos.xy, FrameIndexMod4), uint3(2, 7, 23) / 17.0f));
		      }	
            half4 frag(Varyings IN) : SV_Target
            {

            	sunDir = normalize(_MainLightPosition.xyz);   
                float nonLinearDepth =  SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, IN.uv.xy).r;
				// #if UNITY_REVERSED_Z
				//             nonLinearDepth = 1 - nonLinearDepth;
				// #endif
				//             nonLinearDepth = 2 * nonLinearDepth - 1; //NOTE: Currently must massage depth before computing CS position.
				// return nonLinearDepth*5;
				// float3 vpos = ComputeViewSpacePosition(IN.uv.zw, nonLinearDepth, unity_CameraInvProjection);
            	// float3 wpos = mul(unity_CameraToWorld, float4(vpos, 1)).xyz;

				float distance = length(IN.viewVector);
            	float dist2 = LinearEyeDepth(nonLinearDepth, _ZBufferParams) * distance;

            	float sceneDepth = LinearEyeDepth(nonLinearDepth, _ZBufferParams) * distance / (_DepthDistance / (_PlanetSize));

                float3 origin = _WorldSpaceCameraPos;
            	float3 rayDir = normalize(IN.viewVector);


            	// atmosphereScale = _AtmosphereRadius;
            	float2 hitSphere = raySphere(_PlanetLocation, _AtmosphereRadius, origin, (rayDir));
            	// return sceneDepth;
            	// float esc = escape(origin, rayDir, atmosphereScale);
            	// return esc;
            	float distToAtmosphere = hitSphere.x;
            	// float d = min(sceneDepth - distToAtmosphere, hitSphere.y);
            	// float distTthroughAtmosphere =  saturate(1-(hitSphere.x /  d));
            	// float distTthroughAtmosphere =  d / (_AtmosphereHeight * 2);
            	float distTthroughAtmosphere =  min(hitSphere.y, sceneDepth - distToAtmosphere);
            	// return d;
            	// float distTthroughAtmosphere =  min(hitSphere.y, sceneDepth - distToAtmosphere);
            	// distTthroughAtmosphere = distTthroughAtmosphere / (atmosphereScale * 2);
            	float4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);

				// float sunDot = clamp(dot(rayDir, sunDir), 0.0, 1.0);
    //
    //         	float stepSize = 0.1;
    //             float distTravelled = 0;
    //         	// float rayLength = length(rayVector);
    //             float stepLength = 15 / _ScatteringPoints;
    //         	// float3 step = rayDir * stepLength;
				// float3 camVec = normalize( mul(_WorldSpaceCameraPos, unity_WorldToObject) );
				// float3 currentPosition = wpos;
    //         	float3 col2 = col.rgb;

					
            	if(distTthroughAtmosphere > 0)
            	{
            		const float epsilon = 0.0001;
            		float3 pointInAtmosphere = origin + rayDir * (distToAtmosphere + epsilon);  
            		float3 light = calcLightTest(pointInAtmosphere, rayDir, distTthroughAtmosphere - epsilon * 2, col.rgb, origin, dist2, IN.screenPos);
            		return float4(light, 1);
 
            	}
            	return col;
				// float esc = escape(origin, rayDir, planetSize);
            	// return esc;
				// return (calcLightTest(origin, rayDir, esc));
            	// return min(col, sceneDepth);
            }
            ENDHLSL
        }
    	// Used for rendering shadowmaps
    }
}