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
        _DropletCount ("Water Droplet Impacts", Int) = 6
        _DropletSpeed ("Droplet Ripple Speed", Float) = 1.5
        _DropletStrength ("Droplet Ripple Strength", Range(0.0, 2.0)) = 0.5
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
                // [CHANGED / FIX]: Must be float2 (not float) so TRANSFORM_TEX can access .xy
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                // [CHANGED / FIX]: Explicitly float2 to match Attributes.uv
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
                float _DropletSpeed;
                float _DropletStrength;
            CBUFFER_END

            float2 Hash21(float p)
            {
                float3 p3 = frac(float3(p, p, p) * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xx + p3.yz) * p3.zy);
            }

            float3 CalculateDropletNormal(float2 uv, int count, float speed, float strength)
            {
                float2 totalOffset = float2(0.0, 0.0);
                int clampedCount = clamp(count, 0, 32);

                for (int i = 0; i < clampedCount; i++)
                {
                    float seed = (float)i + 1.0;
                    float2 randPos = Hash21(seed * 17.31);
                    float timeOffset = frac(sin(seed * 91.7) * 43758.5453);

                    float life = frac(_Time.y * speed * 0.5 + timeOffset);
                    float maxRadius = 0.25;
                    float currentRadius = life * maxRadius;

                    float2 diff = uv - randPos;
                    float dist = length(diff);

                    float ringDist = dist - currentRadius;
                    float ringMask = exp(-abs(ringDist) * 45.0) * (1.0 - life);
                    float wave = sin(ringDist * 80.0) * ringMask;

                    float2 dir = (dist > 0.0001) ? (diff / dist) : float2(0.0, 0.0);
                    totalOffset += dir * wave * strength;
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
                // [CHANGED / FIX]: Direct float2 assignment (avoid .xy on scalar floats)
                output.uv = input.uv;
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // 1. Sample Base Tile Map & Second Base Tile Map
                // [CHANGED / FIX]: TRANSFORM_TEX safely operates on float2 input.uv
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

                // 3. Droplet Ripple Normals
                float3 baseNormalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS.xyz);
                float3 bitangentWS = cross(baseNormalWS, tangentWS) * input.tangentWS.w;
                float3x3 TBN = float3x3(tangentWS, bitangentWS, baseNormalWS);

                float3 dropletNormalTS = CalculateDropletNormal(input.uv, _DropletCount, _DropletSpeed, _DropletStrength);
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