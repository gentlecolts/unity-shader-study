// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Ocean_frag"
{
	Properties
	{
		[NoScaleOffset] _MainTex ("Texture", 2D) = "white" {}
	}
	CGINCLUDE
	#include "UnityCG.cginc"
	#include "Lighting.cginc"
	#include "AutoLight.cginc"

	float4 compute_displaced_vertex(appdata_tan v){
		return v.vertex+float4(0,sin(v.vertex.x+_Time.y),0,0);
	}

	struct v2f
	{
		float2 uv : TEXCOORD0;
		
		//#if defined (SHADOWS_DEPTH) && !defined (SPOT)
		unityShadowCoord4 _ShadowCoord : TEXCOORD1; // put shadows data into TEXCOORD1
		//#endif

		DECLARE_LIGHT_COORDS(2)
		UNITY_FOG_COORDS(3)
		fixed3 diff : COLOR0;
		fixed3 ambient : COLOR1;
		float4 pos : SV_POSITION;
	};

	v2f vertex_pass(appdata_tan v){

		v.vertex=compute_displaced_vertex(v);

		v2f o;
		o.pos = UnityObjectToClipPos(v.vertex);
		o.uv = v.texcoord;

		half3 worldNormal = UnityObjectToWorldNormal(v.normal);
		half nl = max(0, dot(worldNormal, _WorldSpaceLightPos0.xyz));
		o.diff = nl * _LightColor0.rgb;
		o.ambient = ShadeSH9(half4(worldNormal,1));
		return o;
	}

	sampler2D _MainTex;

	
	ENDCG
	SubShader
	{
		//base pass
		Pass
		{
			Tags {"LightMode"="ForwardBase"}
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#pragma multi_compile_fog
			#pragma multi_compile_fwdbase //nolightmap nodirlightmap nodynlightmap novertexlight


			//TODO: LIGHT_ATTENUATION macro necessitates this being duplicated, once this function matures, look into ways of de-duplicating code
			fixed4 frag_computation(v2f i){
				fixed4 col = tex2D(_MainTex, i.uv);
				// compute shadow attenuation (1.0 = fully lit, 0.0 = fully shadowed)

				fixed shadow=1;
				//#if defined (SHADOWS_DEPTH) && !defined (SPOT)
				shadow = LIGHT_ATTENUATION(i);
				//#endif

				// darken light's illumination with shadow, keep ambient intact
				fixed3 lighting = i.diff * shadow + i.ambient;
				col.rgb *= lighting;

				UNITY_APPLY_FOG(i.fogCoord, col);

				return col;
			}
	

			v2f vert (appdata_tan v)
			{
				v2f o=vertex_pass(v);

				TRANSFER_VERTEX_TO_FRAGMENT(o);
				UNITY_TRANSFER_FOG(o, o.pos);
				return o;
			}

			fixed4 frag (v2f i) : SV_Target
			{
				
				return frag_computation(i);
			}
			ENDCG
		}

		//forwardadd pass
		Pass
		{
			Tags {"LightMode"="ForwardAdd"}
			Blend One One
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#pragma multi_compile_fog
			#pragma multi_compile_fwdadd_fullshadows //nolightmap nodirlightmap nodynlightmap novertexlight


			//TODO: LIGHT_ATTENUATION macro necessitates this being duplicated, once this function matures, look into ways of de-duplicating code
			fixed4 frag_computation(v2f i){
				fixed4 col = tex2D(_MainTex, i.uv);
				// compute shadow attenuation (1.0 = fully lit, 0.0 = fully shadowed)

				fixed shadow=1;
				//#if defined (SHADOWS_DEPTH) && !defined (SPOT)
				shadow = LIGHT_ATTENUATION(i);
				//#endif

				// darken light's illumination with shadow, keep ambient intact
				fixed3 lighting = i.diff * shadow + i.ambient;
				col.rgb *= lighting;

				UNITY_APPLY_FOG(i.fogCoord, col);

				return col;
			}
	

			v2f vert (appdata_tan v)
			{
				v2f o=vertex_pass(v);

				UNITY_TRANSFER_FOG(o, o.pos);
				TRANSFER_VERTEX_TO_FRAGMENT(o);
				return o;
			}

			fixed4 frag (v2f i) : SV_Target
			{
				
				return frag_computation(i);
			}
			ENDCG
		}

		//shadow pass
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
				v.vertex=compute_displaced_vertex(v);

				v2f_shadow o;
				UNITY_SETUP_INSTANCE_ID(v);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
				TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
				//o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
				return o;
			}
			float4 frag_shadow(v2f_shadow i) : SV_Target
			{
				//fixed4 texcol = tex2D(_MainTex, i.uv);
				//clip(texcol.a - _Cutoff);
				SHADOW_CASTER_FRAGMENT(i)
			}
			ENDCG
		}
	}
	FallBack "Diffuse" //note: for passes: ForwardBase, ShadowCaster, ShadowCollector
}
