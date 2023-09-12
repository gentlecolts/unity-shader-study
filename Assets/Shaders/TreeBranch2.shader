//found at https://forum.unity.com/threads/custom-shadow-caster-and-collector-pass.1141900/
//demonstrates working shadow pass in frag shader
Shader "Unlit/TreeBranch2"
{
	Properties
	{
		_Color("Color", Color) = (1,1,1,1)
		_MainTex("Base (RGB) Transparency (A)", 2D) = "white" {}
		_BumpMap("Normalmap", 2D) = "bump" {}
		_Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
		_Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
		_VertexAnimationMask("Vertex Animation Mask", 2D) = "white" {}
		[Header(Vertex Animation)]
		_NoiseTex("Noise Texture", 2D) = "white" {}
		_WindAmount("Wind Amount", Range(0.0, 1.0)) = 0.5
		_WindSpeed("Wind Speed", Vector) = (1.0, 1.0, 1.0, 1.0)
		_WindScale("Wind Scale", Vector) = (1.0, 1.0, 1.0, 1.0)
	}
	CGINCLUDE
	#include "UnityCG.cginc"
	sampler2D _MainTex;
	sampler2D _NoiseTex;
	float4 _MainTex_ST;
	sampler2D _BumpMap;
	sampler2D _VertexAnimationMask;
	float _Cutoff;
	float _Smoothness;
	float4 _Color;
	float4 _WindSpeed;
	float4 _WindScale;
	float _WindAmount;
	float Noise3D(sampler2D noiseTex, float3 pos) //moved to textured noise
	{
		float p = floor(pos.z);
		float f = (pos.z - p);
		float invNoiseRes = 1.0 / 32;
		float zStretch = 40.0f * invNoiseRes;
		float2 coord = pos.xy * invNoiseRes + (p * zStretch);
		float2 nise = float2(tex2Dlod(noiseTex, float4(coord.x, coord.y, 0, 0)).x, tex2Dlod(noiseTex, float4(coord.x + zStretch, coord.y + zStretch, 0, 0)).x);
		float final = saturate(lerp(nise.x, nise.y, f));
		return final;
	}
	float GetWindNoise(float2 texcoord, float4 vertex)
	{
		float2 uvCoords = TRANSFORM_TEX(texcoord, _MainTex);
		float vertexMask = tex2Dlod(_VertexAnimationMask, float4(uvCoords, 0, 0)).r;
		float4 worldPosition = mul(unity_ObjectToWorld, vertex);
		worldPosition.xyz *= _WindScale.xyz * _WindScale.w;
		worldPosition.xyz += float3(sin(_WindSpeed.x * _Time.x), sin(_WindSpeed.y * _Time.y), sin(_WindSpeed.z * _Time.z)) * _WindSpeed.w;
		float noise = Noise3D(_NoiseTex, worldPosition.xyz);
		noise *= vertexMask;
		noise *= _WindAmount;
		return noise;
	}
	ENDCG
	SubShader
	{
		Tags
		{
			"Queue" = "AlphaTest"
			"RenderType" = "TransparentCutout"
			"IgnoreProjector" = "True"
			"DisableBatching" = "LODFading"
		}
		LOD 100
		//BASE PASS
		Pass
		{
			Tags {"LightMode" = "ForwardBase"}
			CGPROGRAM
			#pragma vertex vert_base
			#pragma fragment frag_base
			// make fog work
			#pragma multi_compile_fog
			#pragma multi_compile_fwdbase
			#pragma fragmentoption ARB_precision_hint_fastest
			#include "UnityCG.cginc"
			#include "UnityLightingCommon.cginc"
			#include "UnityStandardBRDF.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"
			#include "UnityShadowLibrary.cginc"
			struct v2f_base
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float4 posWorld : TEXCOORD1; //world space position
				half3 tspace0 : TEXCOORD2; //tangent space 0
				half3 tspace1 : TEXCOORD3; //tangent space 1
				half3 tspace2 : TEXCOORD4; //tangent space 2
				DECLARE_LIGHT_COORDS(5)
				unityShadowCoord4 _ShadowCoord : TEXCOORD6;
				UNITY_FOG_COORDS(7)
			};
			v2f_base vert_base(appdata_tan v)
			{
				v2f_base o;
				v.vertex.xyz += GetWindNoise(v.texcoord, v.vertex);
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
				//define our world position vector
				o.posWorld = mul(unity_ObjectToWorld, v.vertex);
				//the world normal of the mesh
				half3 worldNormal = UnityObjectToWorldNormal(v.normal);
				//the tangents of the mesh
				half3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
				// compute bitangent from cross product of normal and tangent
				half tangentSign = v.tangent.w * unity_WorldTransformParams.w;
				half3 worldBiTangent = cross(worldNormal, worldTangent) * tangentSign;
				// output the tangent space matrix
				o.tspace0 = half3(worldTangent.x, worldBiTangent.x, worldNormal.x);
				o.tspace1 = half3(worldTangent.y, worldBiTangent.y, worldNormal.y);
				o.tspace2 = half3(worldTangent.z, worldBiTangent.z, worldNormal.z);
				TRANSFER_VERTEX_TO_FRAGMENT(o);
				UNITY_TRANSFER_FOG(o, o.pos);
				return o;
			}
			fixed4 frag_base(v2f_base i) : SV_Target
			{
				//--------------------------- VECTORS -------------------------------
				float2 uv = i.uv.xy;
				float4 worldPosition = i.posWorld;
				float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);
				float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);
				float3 halfDirection = normalize(viewDirection + lightDirection);
				//--------------------------- NORMAL MAPPING -------------------------------
				//sample our normal map
				float4 normalMap = tex2D(_BumpMap, uv);
				normalMap.xyz = UnpackNormal(normalMap);
				//calculate our mesh normals with the normal map into consideration
				float3 normalDirection;
				normalDirection.x = dot(i.tspace0, normalMap.xyz);
				normalDirection.y = dot(i.tspace1, normalMap.xyz);
				normalDirection.z = dot(i.tspace2, normalMap.xyz);
				normalDirection = normalize(normalDirection);
				//--------------------------- ADDITIONAL VECTORS ------------------------------- (some of these vectors need to take normals into account)
				float3 reflectionDirection = reflect(-viewDirection, normalDirection);
				float NdotL = dot(normalDirection, lightDirection);
				float NdotV = dot(normalDirection, viewDirection);
				float LdotH = dot(lightDirection, halfDirection);
				float HdotV = dot(halfDirection, viewDirection);
				//--------------------------- TEXTURES -------------------------------
				float4 albedo = tex2D(_MainTex, i.uv);
				float4 specular = float4(0, 0, 0, 0);
				float oneMinusReflectivity = 0.0f;
				float smoothness = _Smoothness;
				//alpha cutoff
				clip(albedo.a - _Cutoff);
				//--------------------------- LIGHTING -------------------------------
				float atten = LIGHT_ATTENUATION(i); // Light attenuation + shadows.
				float3 ambientColor = ShadeSH9(half4(normalDirection, 1));
				//_LightColor0
				float perceptualRoughness = SmoothnessToPerceptualRoughness(smoothness);
				float diffuseLighting = DisneyDiffuse(NdotV, NdotL, LdotH, perceptualRoughness);
				diffuseLighting = max(0.0f, diffuseLighting);
				float4 finalColor = float4(0, 0, 0, albedo.a);
				//--------------------------- COMBINE LIGHTING -------------------------------
				//finalColor.rgb += diffuseLighting * atten;
				finalColor.rgb += _LightColor0.rgb * atten;
				finalColor.rgb += ambientColor;
				finalColor.rgb *= albedo.rgb;
				// apply fog
				UNITY_APPLY_FOG(i.fogCoord, finalColor);
				return finalColor;
			}
			ENDCG
		}
		//FORWARD ADD PASS
		Pass
		{
			Tags {"LightMode" = "ForwardAdd"}
			Blend One One
			CGPROGRAM
			#pragma vertex vert_base
			#pragma fragment frag_base
			// make fog work
			#pragma multi_compile_fog
			#pragma multi_compile_fwdadd_fullshadows
			#pragma fragmentoption ARB_precision_hint_fastest
			#include "UnityCG.cginc"
			#include "UnityLightingCommon.cginc"
			#include "UnityStandardBRDF.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"
			#include "UnityShadowLibrary.cginc"
			struct v2f_base
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float4 posWorld : TEXCOORD1; //world space position
				half3 tspace0 : TEXCOORD2; //tangent space 0
				half3 tspace1 : TEXCOORD3; //tangent space 1
				half3 tspace2 : TEXCOORD4; //tangent space 2
				DECLARE_LIGHT_COORDS(5)
				unityShadowCoord4 _ShadowCoord : TEXCOORD6;
				UNITY_FOG_COORDS(7)
			};
			v2f_base vert_base(appdata_tan v)
			{
				v2f_base o;
				v.vertex.xyz += GetWindNoise(v.texcoord, v.vertex);
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
				//define our world position vector
				o.posWorld = mul(unity_ObjectToWorld, v.vertex);
				//the world normal of the mesh
				half3 worldNormal = UnityObjectToWorldNormal(v.normal);
				//the tangents of the mesh
				half3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
				// compute bitangent from cross product of normal and tangent
				half tangentSign = v.tangent.w * unity_WorldTransformParams.w;
				half3 worldBiTangent = cross(worldNormal, worldTangent) * tangentSign;
				// output the tangent space matrix
				o.tspace0 = half3(worldTangent.x, worldBiTangent.x, worldNormal.x);
				o.tspace1 = half3(worldTangent.y, worldBiTangent.y, worldNormal.y);
				o.tspace2 = half3(worldTangent.z, worldBiTangent.z, worldNormal.z);
				UNITY_TRANSFER_FOG(o, o.pos);
				TRANSFER_VERTEX_TO_FRAGMENT(o);
				return o;
			}
			fixed4 frag_base(v2f_base i) : SV_Target
			{
				//--------------------------- VECTORS -------------------------------
				float2 uv = i.uv.xy;
				float4 worldPosition = i.posWorld;
				float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);
				float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);
				float3 halfDirection = normalize(viewDirection + lightDirection);
				//--------------------------- NORMAL MAPPING -------------------------------
				//sample our normal map
				float4 normalMap = tex2D(_BumpMap, uv);
				normalMap.xyz = UnpackNormal(normalMap);
				//calculate our mesh normals with the normal map into consideration
				float3 normalDirection;
				normalDirection.x = dot(i.tspace0, normalMap.xyz);
				normalDirection.y = dot(i.tspace1, normalMap.xyz);
				normalDirection.z = dot(i.tspace2, normalMap.xyz);
				normalDirection = normalize(normalDirection);
				//--------------------------- ADDITIONAL VECTORS ------------------------------- (some of these vectors need to take normals into account)
				float3 reflectionDirection = reflect(-viewDirection, normalDirection);
				float NdotL = dot(normalDirection, lightDirection);
				float NdotV = dot(normalDirection, viewDirection);
				float LdotH = dot(lightDirection, halfDirection);
				float HdotV = dot(halfDirection, viewDirection);
				//--------------------------- TEXTURES -------------------------------
				float4 albedo = tex2D(_MainTex, i.uv);
				float4 specular = float4(0, 0, 0, 0);
				float oneMinusReflectivity = 0.0f;
				float smoothness = _Smoothness;
				//alpha cutoff
				clip(albedo.a - _Cutoff);
				//--------------------------- LIGHTING -------------------------------
				float atten = LIGHT_ATTENUATION(i); // Light attenuation + shadows.
				float3 ambientColor = ShadeSH9(half4(normalDirection, 1));
				//_LightColor0
				float perceptualRoughness = SmoothnessToPerceptualRoughness(smoothness);
				float diffuseLighting = DisneyDiffuse(NdotV, NdotL, LdotH, perceptualRoughness);
				diffuseLighting = max(0.0f, diffuseLighting);
				float4 finalColor = float4(0, 0, 0, albedo.a);
				//--------------------------- COMBINE LIGHTING -------------------------------
				//finalColor.rgb += diffuseLighting * atten;
				finalColor.rgb += _LightColor0.rgb * atten;
				finalColor.rgb += ambientColor;
				finalColor.rgb *= albedo.rgb;
				// apply fog
				UNITY_APPLY_FOG(i.fogCoord, finalColor);
				return finalColor;
			}
			ENDCG
		}
		//SHADOW CASTER PASS
		Pass
		{
			Tags {"LightMode" = "ShadowCaster"}
			ZWrite On
			CGPROGRAM
			#pragma vertex vert_shadow
			#pragma fragment frag_shadow
			#pragma target 2.0
			#pragma multi_compile_shadowcaster
			#pragma multi_compile_instancing // allow instanced shadow pass for most of the shaders
			#include "UnityCG.cginc"
			#include "UnityLightingCommon.cginc"
			#include "UnityStandardBRDF.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"
			#include "UnityShadowLibrary.cginc"
			struct v2f_shadow
			{
				V2F_SHADOW_CASTER_NOPOS UNITY_POSITION(pos);
				float2  uv : TEXCOORD1;
				UNITY_VERTEX_OUTPUT_STEREO
			};
			v2f_shadow vert_shadow(appdata_tan v)
			{
				v2f_shadow o;
				v.vertex.xyz += GetWindNoise(v.texcoord, v.vertex);
				UNITY_SETUP_INSTANCE_ID(v);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
				TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
				o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
				return o;
			}
			float4 frag_shadow(v2f_shadow i) : SV_Target
			{
				fixed4 texcol = tex2D(_MainTex, i.uv);
				clip(texcol.a - _Cutoff);
				SHADOW_CASTER_FRAGMENT(i)
			}
			ENDCG
		}
	}
}
