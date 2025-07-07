#include "UnityCG.cginc"
#include "Autolight.cginc"
#include "CustomTessellation.cginc"
#include "UnityLightingCommon.cginc"

float _BendRotationRandom;

float _BladeHeight;
float _BladeHeightRandom;	
float _BladeWidth;
float _BladeWidthRandom;

sampler2D _WindDistortionMap;
float4 _WindDistortionMap_ST;

float2 _WindFrequency;

float _WindStrength;

float3 _PlayerPos;
float _PlayerRadius;

            
float4 _TopColor;
float4 _BottomColor;

float _TranslucentGain;

uniform float4 _Players[100];

// Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
// Extended discussion on this function can be found at the following link:
// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
// Returns a number in the 0...1 range.
float rand(float3 co)
{
	return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
}

struct grassGeometryOutput
{
	float4 pos : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 normal : NORMAL;
	unityShadowCoord4 _ShadowCoord : TEXCOORD1;
};

grassGeometryOutput VertexOutput(float3 pos, float2 uv,float3 normal)
{
	grassGeometryOutput o;
	o.pos = UnityObjectToClipPos(pos);
	o.uv = uv;
	o._ShadowCoord = ComputeScreenPos(o.pos);
	o.normal = UnityObjectToWorldNormal(normal);
	#if UNITY_PASS_SHADOWCASTER
	// Applying the bias prevents artifacts from appearing on the surface.
	o.pos = UnityApplyLinearShadowBias(o.pos);
	#endif
	return o;
}

float3 GetPerpendicularVector(float3 v)
{
    float3 perp = float3(-v.y, v.x, 0); // 简单交换 x 和 y
    if (length(perp) < 0.001) {         // 如果 perp 太小，调整 z 分量
        perp = float3(0, -v.z, v.y);
    }
    return normalize(perp);
}


// Construct a rotation matrix that rotates around the provided axis, sourced from:
// https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
float3x3 AngleAxis3x3(float angle, float3 axis)
{
	float c, s;
	sincos(angle, s, c);

	float t = 1 - c;
	float x = axis.x;
	float y = axis.y;
	float z = axis.z;

	return float3x3(
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c
		);
}
	
float4 nearestPlayer(float3 vetexPos)
{
	float4 res = float4(0,0,0,0);
	float minDis = 100000;
	for(int i = 0;i < 100;i++)
	{
		float3 pos = float3(_Players[i].x,_Players[i].y,_Players[i].z);
		float3 disDir = pos-vetexPos;
		if(length(disDir)<_Players[i].w)
		{
			return float4(pos,_Players[i].w);
		}
		if(length(disDir)<minDis)
		{
			minDis = length(disDir);
			res = float4(pos,_Players[i].w);
		}
	}
	return res;
}
[maxvertexcount(3)]
void grassGeo(triangle vertexOutput IN[3], inout TriangleStream<grassGeometryOutput> triStream)
{
    float3 pos = IN[0].vertex;
	float3 vNormal = IN[0].normal;
	float4 vTangent = IN[0].tangent;
	float3 vBinormal = cross(vNormal, vTangent) * vTangent.w;
	float3x3 tangentToLocal = float3x3(
		vTangent.x, vBinormal.x, vNormal.x,
		vTangent.y, vBinormal.y, vNormal.y,
		vTangent.z, vBinormal.z, vNormal.z
	);
	float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));
	float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1, 0, 0));

	float3 worldPos = mul(unity_ObjectToWorld, float4(pos, 1)).xyz;
	float2 uv = worldPos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
	float4 Player = nearestPlayer(worldPos);
	float3 PlayerPos = Player.xyz;
	float PlayerRadius = Player.w;
	float3 playerDir = normalize(PlayerPos - worldPos);
	float playerDistance = distance(PlayerPos, worldPos);
	float3 playerAixs = GetPerpendicularVector(float3(playerDir.x,playerDir.z,playerDir.y));
	//float3 playerAixs = GetPerpendicularVector(playerDir);
	float playerSample = max(PlayerRadius - playerDistance,0);
	float3x3 playerRotationMatrix = AngleAxis3x3(UNITY_PI * playerSample, playerAixs);

	float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
	float3 wind = normalize(float3(windSample.x, windSample.y, 0));
	float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);


    float3x3 transformationMatrix = mul(mul(mul(mul(tangentToLocal, windRotation),playerRotationMatrix), facingRotationMatrix), bendRotationMatrix);
	//在transformationMatrix下边构建一个用于底部顶点的矩阵
	float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);

	float height = (rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
	float width = (rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
	float3 tangentNormal = float3(0, -1, 0);
	float3 localNormal = mul(transformationMatrixFacing, tangentNormal);

	// 应用在底部的两个顶点
	triStream.Append(VertexOutput(pos + mul(transformationMatrixFacing, float3(width, 0, 0)), float2(0, 0),localNormal));
	triStream.Append(VertexOutput(pos + mul(transformationMatrixFacing, float3(-width, 0, 0)), float2(1, 0),localNormal));
	localNormal = mul(transformationMatrix, tangentNormal);
	triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(0, 0, height)), float2(0.5, 1),localNormal));

}

//LZX-Rider-2025-05-27-001

//||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
//||||--==||||||||||||||||------==||||||||||----------==||||
//||||--==||||||||||||||------------==||||||------------==||
//||||--==|||||||||||||---==||||----==||||||--==||||----==||
//||||--==|||||||||||||---==||||||||||||||||--------------||
//||||--==|||||||||||||---==||||----==||||||----------==||||
//||||------------==||||------------==||||||--==||||||||||||
//||||------------==||||||------==||||||||||--==||||||||||||
//||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
//|||||||||||||||||LZX.Celluloid.Project||||||||||||||||||||
