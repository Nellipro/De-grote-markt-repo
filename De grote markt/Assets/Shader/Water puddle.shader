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
        _WaterAmount ("Water Amount", Range(0.0, 1.0)) = 0.5
        _WaterEdgeSoftness ("Water Edge Softness", Range(0.001, 0.5)) = 0.05
        _WetPathBrightness ("Wet Path Brightness", Range(0.2, 1.0)) = 0.72
        _WetnessRampEnd ("Wetness Full At Water Amount", Range(0.05, 1.0)) = 0.35
        _ReflectionOpacity ("Reflection Opacity", Range(0.0, 1.0)) = 0.65

        [Header(Water Droplet Ripples)]
        _DropletCount ("Water Droplet Impacts", Int) = 250
        _DropletSize ("Droplet Ripple Size", Range(0.002, 0.2)) = 0.025
        _DropletSpeed ("Droplet Ripple Speed", Float) = 2.0
        _DropletStrength ("Droplet Ripple Strength", Range(0.0, 2.0)) = 0.45

        [Header(Snow Accumulation)]
        _SnowMap ("Snow Albedo Map", 2D) = "white" {}
        _SnowColor ("Snow Tint", Color) = (0.92, 0.96, 1.0, 1.0)
        [NoScaleOffset] _SnowBumpMap ("Snow Normal Map", 2D) = "bump" {}
        _SnowBumpScale ("Snow Normal Scale", Float) = 1.2
        _SnowNoiseMap ("Snow Location Noise", 2D) = "gray" {}
        _SnowAmount ("Snow Amount", Range(0.0, 1.0)) = 0.0
        _SnowEdgeSoftness ("Snow Edge Softness", Range(0.001, 0.5)) = 0.1
        _WaterMeltsSnow ("Water Melts Snow", Range(0.0, 1.0)) = 0.85

        [Header(Snow Pile Height Displacement)]
        _SnowMaxHeight ("Max Snow Pile Height", Range(0.0, 1.0)) = 0.12
        _SnowPileSharpness ("Snow Pile Mound Curve", Range(0.5, 4.0)) = 1.5
        _PileNormalStrength ("Snow Pile Slope Shading", Range(0.0, 8.0)) = 2.5
        [Toggle(_USE_PILE_NOISE)] _UsePileNoise ("Use Separate Pile Location Noise", Float) = 0
        _SnowPileNoiseMap ("Snow Pile Location Noise (Optional)", 2D) = "gray" {}

        [Header(VR Snow Micro Sparkles)]
        _SparkleScale ("Sparkle Density", Float) = 160.0
        _SparkleSize ("Sparkle Dot Radius", Range(0.05, 0.45)) = 0.22
        _SparkleThreshold ("Sparkle Angle Threshold", Range(0.1, 0.99)) = 0.75
        _SparkleIntensity ("Sparkle Brightness", Range(0.0, 5.0)) = 1.5
        _RimColor ("Snow Subsurface Rim Tint", Color) = (0.65, 0.82, 1.0, 1.0)
        _RimPower ("Snow Subsurface Rim Power", Range(1.0, 8.0)) = 3.5

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

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        TEXTURE2D(_SecondBaseMap);
        TEXTURE2D(_SecondTileNoiseMap);
        TEXTURE2D(_WaterNoiseMap);

        TEXTURE2D(_SnowMap);
        TEXTURE2D(_SnowBumpMap);
        TEXTURE2D(_SnowNoiseMap);
        TEXTURE2D(_SnowPileNoiseMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _SecondBaseMap_ST;
            float4 _SecondTileNoiseMap_ST;
            float4 _WaterNoiseMap_ST;
            float4 _SnowMap_ST;
            float4 _SnowNoiseMap_ST;
            float4 _SnowPileNoiseMap_ST;
            half _TileBlendSharpness;
            half _WaterAmount;
            half _WaterEdgeSoftness;
            half _WetPathBrightness;
            half _WetnessRampEnd;
            half _ReflectionOpacity;
            int _DropletCount;
            float _DropletSize;
            float _DropletSpeed;
            half _DropletStrength;
            half4 _SnowColor;
            half _SnowBumpScale;
            half _SnowAmount;
            half _SnowEdgeSoftness;
            half _WaterMeltsSnow;
            half _SnowMaxHeight;
            half _SnowPileSharpness;
            half _PileNormalStrength;
            half _SparkleScale;
            half _SparkleSize;
            half _SparkleThreshold;
            half _SparkleIntensity;
            half4 _RimColor;
            half _RimPower;
            float _FogClearRadius;
            float _FogTransitionDistance;
        CBUFFER_END

        float EvaluateSnowPileHeight(float2 uv, half upwardNormalY)
        {
            if (_SnowAmount <= 0.0001h || _SnowMaxHeight <= 0.0001h)
                return 0.0;

            half clampedWater = saturate(_WaterAmount);
            half curvedWater = clampedWater * clampedWater;
            half waterThreshold = lerp(1.0h + _WaterEdgeSoftness, -_WaterEdgeSoftness, curvedWater);
            half waterNoise = SAMPLE_TEXTURE2D_LOD(_WaterNoiseMap, sampler_BaseMap, TRANSFORM_TEX(uv, _WaterNoiseMap), 0).r;
            half waterMask = smoothstep(waterThreshold - _WaterEdgeSoftness, waterThreshold + _WaterEdgeSoftness, waterNoise) * step(0.0001h, clampedWater);

            half clampedSnow = saturate(_SnowAmount);
            half curvedSnow = clampedSnow * clampedSnow;
            half snowThreshold = lerp(1.0h + _SnowEdgeSoftness, -_SnowEdgeSoftness, curvedSnow);
            half snowNoise = SAMPLE_TEXTURE2D_LOD(_SnowNoiseMap, sampler_BaseMap, TRANSFORM_TEX(uv, _SnowNoiseMap), 0).r;
            half snowMask = smoothstep(snowThreshold - _SnowEdgeSoftness, snowThreshold + _SnowEdgeSoftness, snowNoise) * step(0.0001h, clampedSnow);
            snowMask *= saturate(upwardNormalY);
            snowMask *= saturate(1.0h - waterMask * _WaterMeltsSnow);

            #if defined(_USE_PILE_NOISE)
                half pileNoise = SAMPLE_TEXTURE2D_LOD(_SnowPileNoiseMap, sampler_BaseMap, TRANSFORM_TEX(uv, _SnowPileNoiseMap), 0).r;
            #else
                half pileNoise = snowNoise;
            #endif

            half pileProfile = pow(saturate(pileNoise), max(_SnowPileSharpness, 0.01h));
            return (float)(snowMask * pileProfile * _SnowMaxHeight);
        }
        ENDHLSL

        Pass
        {
            Name "VRWater"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma shader_feature_local _USE_PILE_NOISE

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
                // [CHANGED]: Packed original undisplaced floor upward normal Y into TEXCOORD4.y alongside fogFactor
                half2 fogAndUpward : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float2 Hash22(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xx + p3.yz) * p3.zy);
            }

            float3 Hash33(float3 p3)
            {
                p3 = frac(p3 * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yxz + 33.33);
                return frac((p3.xxy + p3.yxx) * p3.zyx);
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

                float3 posOS = input.positionOS.xyz;
                VertexNormalInputs baseNormalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                half upwardY = (half)baseNormalInput.normalWS.y;

                float pileHeight = EvaluateSnowPileHeight(input.uv, upwardY);
                posOS += input.normalOS * pileHeight;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(posOS);

                half3 displacedNormalWS = (half3)baseNormalInput.normalWS;
                if (pileHeight > 0.00001 && _PileNormalStrength > 0.001h)
                {
                    float uvStep = 0.005;
                    float heightU = EvaluateSnowPileHeight(input.uv + float2(uvStep, 0.0), upwardY);
                    float heightV = EvaluateSnowPileHeight(input.uv + float2(0.0, uvStep), upwardY);

                    half dU = (half)((pileHeight - heightU) / uvStep) * _PileNormalStrength * 0.05h;
                    half dV = (half)((pileHeight - heightV) / uvStep) * _PileNormalStrength * 0.05h;
                    half3 moundNormalTS = normalize(half3(dU, dV, 1.0h));

                    half3 tWS = (half3)baseNormalInput.tangentWS;
                    half3 nWS = (half3)baseNormalInput.normalWS;
                    half3 bWS = cross(nWS, tWS) * (half)input.tangentOS.w;
                    displacedNormalWS = normalize(mul(moundNormalTS, half3x3(tWS, bWS, nWS)));
                }

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = displacedNormalWS;
                output.tangentWS = half4((half3)baseNormalInput.tangentWS, (half)input.tangentOS.w);
                output.uv = input.uv;
                // [CHANGED]: Store fogFactor in .x and original undisplaced upwardY in .y
                output.fogAndUpward = half2((half)ComputeFogFactor(vertexInput.positionCS.z), upwardY);

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

                // 2. Calibrated Water Mask
                float2 uvWaterNoise = TRANSFORM_TEX(input.uv, _WaterNoiseMap);
                half waterNoise = SAMPLE_TEXTURE2D(_WaterNoiseMap, sampler_BaseMap, uvWaterNoise).r;

                half clampedWater = saturate(_WaterAmount);
                half curvedWater = clampedWater * clampedWater;
                half threshold = lerp(1.0h + _WaterEdgeSoftness, -_WaterEdgeSoftness, curvedWater);
                half waterMask = smoothstep(threshold - _WaterEdgeSoftness, threshold + _WaterEdgeSoftness, waterNoise);
                waterMask *= step(0.0001h, clampedWater);

                half pathDampFactor = smoothstep(0.0h, max(_WetnessRampEnd, 0.001h), clampedWater);
                half surfaceBrightness = lerp(1.0h, _WetPathBrightness, max(pathDampFactor, waterMask));
                surfaceBrightness *= lerp(1.0h, 0.85h, waterMask);
                half3 wetAlbedo = combinedTileAlbedo * surfaceBrightness;

                // 2.5. Snow Accumulation Mask & Albedo Blend
                half3 baseNormalWS = normalize(input.normalWS);
                half clampedSnow = saturate(_SnowAmount);
                half curvedSnow = clampedSnow * clampedSnow;
                float2 uvSnowNoise = TRANSFORM_TEX(input.uv, _SnowNoiseMap);
                half snowNoise = SAMPLE_TEXTURE2D(_SnowNoiseMap, sampler_BaseMap, uvSnowNoise).r;

                half snowThreshold = lerp(1.0h + _SnowEdgeSoftness, -_SnowEdgeSoftness, curvedSnow);
                half snowMask = smoothstep(snowThreshold - _SnowEdgeSoftness, snowThreshold + _SnowEdgeSoftness, snowNoise);
                snowMask *= step(0.0001h, clampedSnow);
                // [CHANGED]: Use original undisplaced upward normal (input.fogAndUpward.y) so steep snow pile slopes remain covered in snow
                snowMask *= saturate(input.fogAndUpward.y);
                snowMask *= saturate(1.0h - waterMask * _WaterMeltsSnow);

                half3 surfaceAlbedo = wetAlbedo;
                [branch]
                if (snowMask > 0.001h)
                {
                    float2 uvSnow = TRANSFORM_TEX(input.uv, _SnowMap);
                    half3 snowAlbedo = SAMPLE_TEXTURE2D(_SnowMap, sampler_BaseMap, uvSnow).rgb * _SnowColor.rgb;
                    surfaceAlbedo = lerp(wetAlbedo, snowAlbedo, snowMask);
                }

                // 3. Combined Droplet Ripple & Snow Normals
                half3 finalNormalWS = baseNormalWS;
                half activeRippleMask = waterMask * (1.0h - snowMask);
                bool hasRipples = (activeRippleMask > 0.001h && _DropletCount > 0 && _DropletStrength > 0.0001h);
                bool hasSnow = (snowMask > 0.001h);

                [branch]
                if (hasRipples || hasSnow)
                {
                    half3 tangentWS = normalize(input.tangentWS.xyz);
                    half3 bitangentWS = cross(baseNormalWS, tangentWS) * input.tangentWS.w;
                    half3x3 TBN = half3x3(tangentWS, bitangentWS, baseNormalWS);

                    if (hasRipples)
                    {
                        half3 dropletNormalTS = CalculateDropletNormal(input.uv, _DropletCount, _DropletSize, _DropletSpeed, _DropletStrength, threshold);
                        half3 dropletNormalWS = normalize(mul(dropletNormalTS, TBN));
                        finalNormalWS = normalize(lerp(finalNormalWS, dropletNormalWS, activeRippleMask));
                    }

                    if (hasSnow)
                    {
                        float2 uvSnowBump = TRANSFORM_TEX(input.uv, _SnowMap);
                        half3 snowNormalTS = (half3)UnpackNormalScale(SAMPLE_TEXTURE2D(_SnowBumpMap, sampler_BaseMap, uvSnowBump), _SnowBumpScale);
                        half3 snowNormalWS = normalize(mul(snowNormalTS, TBN));
                        finalNormalWS = normalize(lerp(finalNormalWS, snowNormalWS, snowMask));
                    }
                }

                // 4. Lighting
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half NdotL = saturate(dot(finalNormalWS, (half3)mainLight.direction));
                half3 ambient = SampleSH(finalNormalWS);
                half3 litBaseColor = surfaceAlbedo * (ambient + (half3)mainLight.color * (half)mainLight.shadowAttenuation * NdotL);

                // 4.5. Circular Micro-Facet Snow Glints
                half3 viewDirWS = (half3)GetWorldSpaceNormalizeViewDir(input.positionWS);
                [branch]
                if (hasSnow)
                {
                    float3 scaledPos = input.positionWS * _SparkleScale;
                    float3 cellID = floor(scaledPos);
                    float3 cellLocal = frac(scaledPos);

                    float3 randVec = Hash33(cellID);
                    float3 crystalCenter = lerp(0.22, 0.78, randVec);
                    half distToCenter = (half)length(cellLocal - crystalCenter);
                    half pinpointMask = smoothstep(_SparkleSize, 0.0h, distToCenter);

                    half3 microFacetNormal = normalize(finalNormalWS + (half3)(randVec * 2.0 - 1.0) * 0.65h);
                    half3 halfDir = normalize((half3)mainLight.direction + viewDirWS);
                    half glintAlignment = pow(saturate(dot(microFacetNormal, halfDir)), 32.0h);

                    half viewDist = (half)length(input.positionWS - _WorldSpaceCameraPos);
                    half distFade = 1.0h - smoothstep(1.5h, 10.0h, viewDist);

                    half lightVisibility = lerp(0.2h, 1.0h, (half)mainLight.shadowAttenuation);
                    half sparkle = pinpointMask * smoothstep(_SparkleThreshold, 1.0h, glintAlignment) * _SparkleIntensity * lightVisibility * distFade * snowMask;

                    half fresnel = pow(1.0h - saturate(dot(finalNormalWS, viewDirWS)), _RimPower);
                    half3 subsurfaceRim = _RimColor.rgb * fresnel * 0.25h * snowMask;

                    litBaseColor += (sparkle + subsurfaceRim);
                }

                // 5. Environment Reflection (suppressed where snow covers water)
                half3 finalColor = litBaseColor;
                half finalReflectionFactor = waterMask * (1.0h - snowMask) * saturate(_ReflectionOpacity);

                [branch]
                if (finalReflectionFactor > 0.001h)
                {
                    half3 reflectVector = reflect(-viewDirWS, finalNormalWS);
                    half3 envReflection = GlossyEnvironmentReflection(reflectVector, input.positionWS, 0.05h, 1.0h);
                    finalColor = lerp(litBaseColor, envReflection, finalReflectionFactor);
                }

                // 6. Player Distance Fog Circle
                float playerDistXZ = length(input.positionWS.xz - _WorldSpaceCameraPos.xz);
                half fogDistanceMask = (half)smoothstep(_FogClearRadius, _FogClearRadius + max(_FogTransitionDistance, 0.001), playerDistXZ);

                [branch]
                if (fogDistanceMask > 0.001h)
                {
                    // [CHANGED]: Read fogFactor from input.fogAndUpward.x
                    half3 foggedColor = MixFog(finalColor, input.fogAndUpward.x);
                    finalColor = lerp(finalColor, foggedColor, fogDistanceMask);
                }

                return half4(finalColor, 1.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma shader_feature_local _USE_PILE_NOISE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float pileHeight = EvaluateSnowPileHeight(input.uv, (half)normalWS.y);
                float3 displacedPosOS = input.positionOS.xyz + input.normalOS * pileHeight;

                float3 positionWS = TransformObjectToWorld(displacedPosOS);
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}