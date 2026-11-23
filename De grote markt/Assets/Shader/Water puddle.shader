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
        // [CHANGED]: Now scales a 3x3 spatial grid so values like 1000 render fully at fast VR framerates
        _DropletCount ("Water Droplet Impacts", Int) = 250
        _DropletSize ("Droplet Ripple Size", Range(0.002, 0.1)) = 0.025
        _DropletSpeed ("Droplet Ripple Speed", Float) = 2.0
        _DropletStrength ("Droplet Ripple Strength", Range(0.0, 2.0)) = 0.45
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
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
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
                float3 normalWS    : TEXCOORD2;
                float4 tangentWS   : TEXCOORD3;
                float fogFactor    : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_SecondBaseMap);
            SAMPLER(sampler_SecondBaseMap);

            TEXTURE2D(_SecondTileNoiseMap);
            SAMPLER(sampler_SecondTileNoiseMap);

            TEXTURE2D(_WaterNoiseMap);
            SAMPLER(sampler_WaterNoiseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _SecondBaseMap_ST;
                float4 _SecondTileNoiseMap_ST;
                float4 _WaterNoiseMap_ST;
                float _TileBlendSharpness;
                float _WaterAmount;
                float _WaterEdgeSoftness;
                float _ReflectionOpacity;
                int _DropletCount;
                float _DropletSize;
                float _DropletSpeed;
                float _DropletStrength;
            CBUFFER_END

            // [CHANGED]: 2D-to-2D hash so each grid cell gets a unique random position and phase
            float2 Hash22(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xx + p3.yz) * p3.zy);
            }

            // [CHANGED]: Replaced the 32-capped global loop with a 3x3 spatial grid cell solver.
            // Supports 1000+ impacts with only 9 loop iterations per pixel and spawns strictly on white noise pixels.
            float3 CalculateDropletNormal(float2 uv, int count, float size, float speed, float strength, float waterThreshold)
            {
                if (count <= 0 || strength <= 0.0001)
                    return float3(0.0, 0.0, 1.0);

                float2 totalOffset = float2(0.0, 0.0);

                // [CHANGED]: Derive grid density from _DropletCount (e.g., 1000 impacts -> ~31x31 grid cells)
                float gridDensity = max(1.0, sqrt((float)count));
                float2 gridUV = uv * gridDensity;
                float2 baseCell = floor(gridUV);

                float ringSharpness = 12.0 / max(size, 0.001);
                float waveFrequency = 24.0 / max(size, 0.001);

                // [CHANGED]: Check the pixel's own cell and its 8 neighbors (always 9 iterations, even at 1000+ impacts)
                [unroll]
                for (int y = -1; y <= 1; y++)
                {
                    [unroll]
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 neighborCell = baseCell + float2(x, y);
                        float2 randHash = Hash22(neighborCell);

                        // [CHANGED]: Stagger drop timing per cell and pick a new random spot inside the cell each cycle
                        float cycle = floor(_Time.y * speed * 0.5 + randHash.x * 13.7);
                        float life = frac(_Time.y * speed * 0.5 + randHash.x * 13.7);

                        float2 cellJitter = Hash22(neighborCell + cycle * 7.13);
                        float2 dropUV = (neighborCell + cellJitter) / gridDensity;

                        // [CHANGED]: Sample _WaterNoiseMap at the exact droplet spawn UV; skip if not on white water
                        float spawnNoise = SAMPLE_TEXTURE2D_LOD(_WaterNoiseMap, sampler_WaterNoiseMap, TRANSFORM_TEX(dropUV, _WaterNoiseMap), 0).r;
                        float spawnMask = step(waterThreshold, spawnNoise);
                        if (spawnMask <= 0.0)
                            continue;

                        float currentRadius = life * size;
                        float2 diff = uv - dropUV;
                        float dist = length(diff);

                        float ringDist = dist - currentRadius;
                        float ringMask = exp(-abs(ringDist) * ringSharpness) * (1.0 - life);
                        float wave = sin(ringDist * waveFrequency) * ringMask;

                        float2 dir = (dist > 0.0001) ? (diff / dist) : float2(0.0, 0.0);
                        totalOffset += dir * wave * strength * spawnMask;
                    }
                }

                return normalize(float3(totalOffset.x, totalOffset.y, 1.0));
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
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                output.uv = input.uv;
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

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

                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvBase);
                half4 secondCol = SAMPLE_TEXTURE2D(_SecondBaseMap, sampler_SecondBaseMap, uvSecond);
                half secondNoise = SAMPLE_TEXTURE2D(_SecondTileNoiseMap, sampler_SecondTileNoiseMap, uvSecondNoise).r;

                half tileBlend = smoothstep(0.5 - _TileBlendSharpness, 0.5 + _TileBlendSharpness, secondNoise);
                half3 combinedTileAlbedo = lerp(baseCol.rgb, secondCol.rgb, tileBlend);

                // 2. Water Mask from Water Noise & Water Amount
                float2 uvWaterNoise = TRANSFORM_TEX(input.uv, _WaterNoiseMap);
                half waterNoise = SAMPLE_TEXTURE2D(_WaterNoiseMap, sampler_WaterNoiseMap, uvWaterNoise).r;

                float threshold = 1.0 - saturate(_WaterAmount);
                half waterMask = smoothstep(threshold - _WaterEdgeSoftness, threshold + _WaterEdgeSoftness, waterNoise);
                waterMask *= step(0.0001, _WaterAmount);

                half3 wetAlbedo = combinedTileAlbedo * lerp(1.0, 0.65, waterMask);

                // 3. Droplet Ripple Normals (restricted to white water regions)
                float3 baseNormalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS.xyz);
                float3 bitangentWS = cross(baseNormalWS, tangentWS) * input.tangentWS.w;
                float3x3 TBN = float3x3(tangentWS, bitangentWS, baseNormalWS);

                float3 dropletNormalTS = CalculateDropletNormal(input.uv, _DropletCount, _DropletSize, _DropletSpeed, _DropletStrength, threshold);
                float3 dropletNormalWS = normalize(mul(dropletNormalTS, TBN));

                float3 finalNormalWS = normalize(lerp(baseNormalWS, dropletNormalWS, waterMask));

                // 4. Lighting
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half NdotL = saturate(dot(finalNormalWS, mainLight.direction));
                half3 ambient = SampleSH(finalNormalWS);
                half3 litBaseColor = wetAlbedo * (ambient + mainLight.color * mainLight.shadowAttenuation * NdotL);

                // 5. Environment Reflection
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float3 reflectVector = reflect(-viewDirWS, finalNormalWS);
                half3 envReflection = GlossyEnvironmentReflection(reflectVector, input.positionWS, 0.05h, 1.0h);

                // 6. Reflection Opacity Blend
                half finalReflectionFactor = waterMask * saturate(_ReflectionOpacity);
                half3 finalColor = lerp(litBaseColor, envReflection, finalReflectionFactor);

                finalColor = MixFog(finalColor, input.fogFactor);

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}