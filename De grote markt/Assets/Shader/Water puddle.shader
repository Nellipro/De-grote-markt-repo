Shader "Custom/VR_Reflective_Tile_Water"
{
    Properties
    {
        [Header(Base Tile Maps)]
        _BaseMap ("Basic Tile Map", 2D) = "white" {}
        _SecondBaseMap ("Second Base Tile Map", 2D) = "white" {}
        _SecondTileNoiseMap ("Second Tile Noise Map", 2D) = "gray" {}
        _TileBlendSharpness ("Second Tile Blend Sharpness", Range(0.01, 1.0)) = 0.2

        [Header(Water and Reflections)]
        _WaterNoiseMap ("Water Location Noise", 2D) = "gray" {}
        _WaterAmount ("Water Amount", Float) = 0.5
        _WaterEdgeSoftness ("Water Edge Softness", Range(0.001, 0.5)) = 0.05
        _ReflectionOpacity ("Reflection Opacity", Range(0.0, 1.0)) = 0.65

        [Header(Water Droplet Ripples)]
        _DropletCount ("Water Droplet Impacts", Int) = 250
        _DropletSize ("Droplet Ripple Size", Range(0.002, 0.2)) = 0.025
        _DropletSpeed ("Droplet Ripple Speed", Float) = 2.0
        _DropletStrength ("Droplet Ripple Strength", Range(0.0, 2.0)) = 0.45

        // [CHANGED]: Added Inspector controls for the clear fog radius around the player and smooth fade-in distance
        [Header(Player Distance Fog)]
        _FogClearRadius ("Fog Clear Radius", Float) = 5.0
        _FogTransitionDistance ("Fog Transition Distance", Float) = 10.0
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "VRWater"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            // [CHANGED]: Re-enabled multi_compile_fog so URP scene fog can blend in at a distance from the player
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                half3 normalWS     : TEXCOORD2;
                half4 tangentWS    : TEXCOORD3;
                // [CHANGED]: Restored fogFactor interpolator to compute URP scene fog
                half fogFactor     : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_SecondBaseMap);
            TEXTURE2D(_SecondTileNoiseMap);
            TEXTURE2D(_WaterNoiseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _SecondBaseMap_ST;
                float4 _SecondTileNoiseMap_ST;
                float4 _WaterNoiseMap_ST;
                half _TileBlendSharpness;
                half _WaterAmount;
                half _WaterEdgeSoftness;
                half _ReflectionOpacity;
                int _DropletCount;
                float _DropletSize;
                float _DropletSpeed;
                half _DropletStrength;
                // [CHANGED]: Added player fog radius and transition properties to UnityPerMaterial buffer
                float _FogClearRadius;
                float _FogTransitionDistance;
            CBUFFER_END

            float2 Hash22(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xx + p3.yz) * p3.zy);
            }

            half3 CalculateDropletNormal(float2 uv, int count, float size, float speed, half strength, half waterThreshold)
            {
                half2 totalOffset = half2(0.0h, 0.0h);

                float safeSize = max(size, 0.001);
                float maxSafeDensity = 1.0 / safeSize;
                float gridDensity = max(1.0, min(sqrt((float)count), maxSafeDensity));

                float invGridDensity = 1.0 / gridDensity;
                float sizeSq = safeSize * safeSize;
                float invSize = 1.0 / safeSize;
                half ringSharpness = (half)(12.0 * invSize);
                half waveFrequency = (half)(24.0 * invSize);
                float scaledTime = _Time.y * speed * 0.5;

                float2 gridUV = uv * gridDensity;
                float2 baseCell = floor(gridUV);

                [unroll]
                for (int y = -1; y <= 1; y++)
                {
                    [unroll]
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 neighborCell = baseCell + float2(x, y);
                        float2 randHash = Hash22(neighborCell);

                        float timePhase = scaledTime + randHash.x * 13.7;
                        float cycle = floor(timePhase);
                        half life = (half)frac(timePhase);

                        float2 cellJitter = Hash22(neighborCell + cycle * 7.13);
                        float2 dropUV = (neighborCell + cellJitter) * invGridDensity;

                        float2 diff = uv - dropUV;
                        float distSq = dot(diff, diff);

                        if (distSq > sizeSq)
                            continue;

                        half spawnNoise = SAMPLE_TEXTURE2D_LOD(_WaterNoiseMap, sampler_BaseMap, TRANSFORM_TEX(dropUV, _WaterNoiseMap), 0).r;
                        if (spawnNoise < waterThreshold)
                            continue;

                        float dist = sqrt(distSq);
                        half edgeFade = (half)smoothstep(safeSize, safeSize * 0.65, dist);

                        half ringDist = (half)(dist - (float)life * safeSize);

                        half falloffInput = abs(ringDist) * ringSharpness;
                        half ringFalloff = rcp(1.0h + falloffInput + 0.48h * falloffInput * falloffInput);
                        half ringMask = ringFalloff * (1.0h - life) * edgeFade;

                        half wave = sin(ringDist * waveFrequency) * ringMask;

                        half2 dir = (distSq > 1e-8) ? (half2)(diff * rsqrt(distSq)) : half2(0.0h, 0.0h);
                        totalOffset += dir * (wave * strength);
                    }
                }

                return normalize(half3(totalOffset.x, totalOffset.y, 1.0h));
            }

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = (half3)normalInput.normalWS;
                output.tangentWS = half4((half3)normalInput.tangentWS, (half)input.tangentOS.w);
                output.uv = input.uv;
                // [CHANGED]: Compute URP fog factor in vertex shader
                output.fogFactor = (half)ComputeFogFactor(vertexInput.positionCS.z);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // 1. Sample Base Tile Map & Second Base Tile Map
                float2 uvBase = TRANSFORM_TEX(input.uv, _BaseMap);
                float2 uvSecond = TRANSFORM_TEX(input.uv, _SecondBaseMap);
                float2 uvSecondNoise = TRANSFORM_TEX(input.uv, _SecondTileNoiseMap);

                half3 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvBase).rgb;
                half3 secondCol = SAMPLE_TEXTURE2D(_SecondBaseMap, sampler_BaseMap, uvSecond).rgb;
                half secondNoise = SAMPLE_TEXTURE2D(_SecondTileNoiseMap, sampler_BaseMap, uvSecondNoise).r;

                half tileBlend = smoothstep(0.5h - _TileBlendSharpness, 0.5h + _TileBlendSharpness, secondNoise);
                half3 combinedTileAlbedo = lerp(baseCol, secondCol, tileBlend);

                // 2. Water Mask from Water Noise & Water Amount
                float2 uvWaterNoise = TRANSFORM_TEX(input.uv, _WaterNoiseMap);
                half waterNoise = SAMPLE_TEXTURE2D(_WaterNoiseMap, sampler_BaseMap, uvWaterNoise).r;

                half threshold = 1.0h - saturate(_WaterAmount);
                half waterMask = smoothstep(threshold - _WaterEdgeSoftness, threshold + _WaterEdgeSoftness, waterNoise);
                waterMask *= step(0.0001h, _WaterAmount);

                half3 wetAlbedo = combinedTileAlbedo * lerp(1.0h, 0.65h, waterMask);

                // 3. Droplet Ripple Normals
                half3 baseNormalWS = normalize(input.normalWS);
                half3 finalNormalWS = baseNormalWS;

                [branch]
                if (waterMask > 0.001h && _DropletCount > 0 && _DropletStrength > 0.0001h)
                {
                    half3 tangentWS = normalize(input.tangentWS.xyz);
                    half3 bitangentWS = cross(baseNormalWS, tangentWS) * input.tangentWS.w;
                    half3x3 TBN = half3x3(tangentWS, bitangentWS, baseNormalWS);

                    half3 dropletNormalTS = CalculateDropletNormal(input.uv, _DropletCount, _DropletSize, _DropletSpeed, _DropletStrength, threshold);
                    half3 dropletNormalWS = normalize(mul(dropletNormalTS, TBN));

                    finalNormalWS = normalize(lerp(baseNormalWS, dropletNormalWS, waterMask));
                }

                // 4. Lighting
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half NdotL = saturate(dot(finalNormalWS, (half3)mainLight.direction));
                half3 ambient = SampleSH(finalNormalWS);
                half3 litBaseColor = wetAlbedo * (ambient + (half3)mainLight.color * (half)mainLight.shadowAttenuation * NdotL);

                // 5. Environment Reflection
                half3 finalColor = litBaseColor;
                half finalReflectionFactor = waterMask * saturate(_ReflectionOpacity);

                [branch]
                if (finalReflectionFactor > 0.001h)
                {
                    half3 viewDirWS = (half3)GetWorldSpaceNormalizeViewDir(input.positionWS);
                    half3 reflectVector = reflect(-viewDirWS, finalNormalWS);
                    half3 envReflection = GlossyEnvironmentReflection(reflectVector, input.positionWS, 0.05h, 1.0h);
                    finalColor = lerp(litBaseColor, envReflection, finalReflectionFactor);
                }

                // [CHANGED]: Measure horizontal (XZ) circle distance from the VR player/camera position
                float playerDistXZ = length(input.positionWS.xz - _WorldSpaceCameraPos.xz);
                half fogDistanceMask = (half)smoothstep(_FogClearRadius, _FogClearRadius + max(_FogTransitionDistance, 0.001), playerDistXZ);

                // [CHANGED]: Keep the floor completely clear inside _FogClearRadius, then smoothly blend in scene fog
                [branch]
                if (fogDistanceMask > 0.001h)
                {
                    half3 foggedColor = MixFog(finalColor, input.fogFactor);
                    finalColor = lerp(finalColor, foggedColor, fogDistanceMask);
                }

                return half4(finalColor, 1.0h);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}