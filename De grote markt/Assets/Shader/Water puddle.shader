Shader "Custom/URP/WetSurfaceAfterRain"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map (Albedo)", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Float) = 1.0
        _Smoothness("Dry Smoothness", Range(0.0, 1.0)) = 0.2
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0

        [Header(Rain and Puddle Settings)]
        _PuddleMask("Puddle Noise Mask (R)", 2D) = "gray" {}
        // [CHANGED] Added toggle to switch between Mesh UVs (respects Material Tiling) and World Space
        [Toggle] _UseMeshUV("Use Mesh UVs Instead of World Space", Float) = 0
        // [CHANGED] Lowered default scale so world-space puddles cover a much wider area without obvious tiling
        _PuddleScale("World Puddle Scale (Lower = Larger)", Float) = 0.04
        _Wetness("Local Wetness Level", Range(0.0, 1.0)) = 0.5
        _PuddleSharpness("Puddle Edge Sharpness", Range(0.01, 0.5)) = 0.08
        _WetDarkening("Wet Albedo Darkening", Range(0.1, 1.0)) = 0.45
        _WetSmoothness("Puddle Smoothness", Range(0.5, 1.0)) = 0.96
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                // [CHANGED] Added raw mesh UV so Puddle Mask can use its own Material Tiling independently
                float2 puddleUV     : TEXCOORD1;
                float3 positionWS   : TEXCOORD2;
                float3 normalWS     : TEXCOORD3;
                float4 tangentWS    : TEXCOORD4;
                float fogFactor     : TEXCOORD5;
            };

            TEXTURE2D(_BaseMap);        SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);        SAMPLER(sampler_BumpMap);
            TEXTURE2D(_PuddleMask);     SAMPLER(sampler_PuddleMask);

            float _GlobalRainWetness;

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                // [CHANGED] Added _PuddleMask_ST so Material Tiling/Offset works when Use Mesh UVs is checked
                float4 _PuddleMask_ST;
                half4 _BaseColor;
                float _BumpScale;
                half _Smoothness;
                half _Metallic;
                float _UseMeshUV;
                float _PuddleScale;
                half _Wetness;
                half _PuddleSharpness;
                half _WetDarkening;
                half _WetSmoothness;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                // [CHANGED] Compute scaled UVs for the puddle mask
                output.puddleUV = TRANSFORM_TEX(input.uv, _PuddleMask);
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // 1. Sample Base Textures
                half4 albedoSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                half3 tangentNormal = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);

                // 2. [CHANGED] Fixed multiplication operator & added Mesh UV vs World Space option + macro breakup
                float2 basePuddleUV = (_UseMeshUV > 0.5) ? input.puddleUV : (input.positionWS.xz * _PuddleScale);
                half maskMain = SAMPLE_TEXTURE2D(_PuddleMask, sampler_PuddleMask, basePuddleUV).r;
                // Sample a second rotated/scaled octave to break up visible grid repetition
                float2 macroUV = float2(basePuddleUV.x * 0.37 - basePuddleUV.y * 0.21, basePuddleUV.x * 0.21 + basePuddleUV.y * 0.37);
                half maskMacro = SAMPLE_TEXTURE2D(_PuddleMask, sampler_PuddleMask, macroUV).r;
                half maskValue = saturate(maskMain * 0.65 + maskMacro * 0.45);

                // Combine local material wetness with global weather controller
                half activeWetness = saturate(max(_Wetness, _GlobalRainWetness));

                // [CHANGED] Fixed minus operator: (input.normalWS.y - 0.5)
                half upwardFactor = saturate((input.normalWS.y - 0.5) * 2.0);
                activeWetness *= upwardFactor;

                // 3. [CHANGED] Fixed minus operators in smoothstep thresholds
                half dampMask = smoothstep(1.0 - activeWetness, (1.0 - activeWetness) + 0.35, maskValue);
                half puddleMask = smoothstep(1.0 - (activeWetness * 0.85), (1.0 - (activeWetness * 0.85)) + _PuddleSharpness, maskValue);

                // 4. [CHANGED] Fixed multiplication operator: albedoSample.rgb * _WetDarkening
                half3 finalAlbedo = lerp(albedoSample.rgb, albedoSample.rgb * _WetDarkening, saturate(dampMask + puddleMask));

                half3 flatNormal = half3(0.0, 0.0, 1.0);
                half3 finalTangentNormal = lerp(tangentNormal, flatNormal, puddleMask * 0.92);

                half dampSmoothness = lerp(_Smoothness, lerp(_Smoothness, _WetSmoothness, 0.45), dampMask);
                half finalSmoothness = lerp(dampSmoothness, _WetSmoothness, puddleMask);

                // [CHANGED] Fixed multiplication operator: input.tangentWS.w * cross(...)
                float3 bitangent = input.tangentWS.w * cross(input.normalWS, input.tangentWS.xyz);
                half3 normalWS = TransformTangentToWorld(finalTangentNormal, half3x3(input.tangentWS.xyz, bitangent, input.normalWS));
                normalWS = NormalizeNormalPerPixel(normalWS);

                // 5. PBR Lighting Calculation
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                inputData.fogCoord = input.fogFactor;
                inputData.bakedGI = SampleSH(normalWS);

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = finalAlbedo;
                surfaceData.metallic = _Metallic;
                surfaceData.specular = half3(0.0, 0.0, 0.0);
                surfaceData.smoothness = finalSmoothness;
                surfaceData.normalTS = finalTangentNormal;
                surfaceData.occlusion = 1.0;
                surfaceData.alpha = albedoSample.a;

                half4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, inputData.fogCoord);

                return color;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}