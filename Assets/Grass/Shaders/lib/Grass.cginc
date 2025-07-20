#include "UnityCG.cginc"
#include "Autolight.cginc"
#include "CustomTessellation.cginc"
#include "UnityLightingCommon.cginc"

float _BendRotationRandom;

float _BladeHeight;			// 这玩意越大越平整
float _BladeHeightRandom;	// 这玩意越大越随机
float _BladeWidth;
float _BladeWidthRandom;

sampler2D _WindDistortionMap;
float4 _WindDistortionMap_ST; // Unity 自动为每个 2D 纹理生成一个 _ST 变量，表示贴图的 Tiling（缩放）和 Offset， _ST = float4(tiling.x, tiling.y, offset.x, offset.y) 这样你就可以通过材质面板控制风贴图的缩放与偏移。

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
	); // 在切线空间中，顶点的切线方向为x轴，法线方向为z轴，副切线方向（切线方向和法线方向的叉积）为y轴
	float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1)); // 绕z轴随机旋转（0，2Π），模拟草的随机朝向
    float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1, 0, 0)); // 绕x轴随机旋转（0，2Π），模拟草的随机弯曲

	float3 worldPos = mul(unity_ObjectToWorld, float4(pos, 1)).xyz;
	// _WindDistortionMap_ST控制风贴图的缩放与平移，我们先默认这里不考虑缩放与平移，即（1，1，0，0）
	// 则 uv = worldPos.xz + _WindFrequency * _Time.y;
	// _WindFrequency表示采样坐标在水平和垂直方向上的偏移速度，_Time.y表示时间*2，得到的uv坐标随时间移动，以表示动态风场的扰动
    float2 uv = worldPos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
	float4 Player = nearestPlayer(worldPos); // 计算最近的xyz坐标和碰撞体半径
	float3 PlayerPos = Player.xyz;
	float PlayerRadius = Player.w;
	float3 playerDir = normalize(PlayerPos - worldPos);
	float playerDistance = distance(PlayerPos, worldPos);
	// 这个地方采用世界坐标系可能有问题？如果地面不位于xoz平面上的话？
    float3 playerAixs = GetPerpendicularVector(float3(playerDir.x, playerDir.z, playerDir.y)); // 根据碰撞体的相对方向计算草叶的旋转轴（弯曲方向），这个轴垂直于相对方向且位于xoz平面上（世界坐标系）
	//float3 playerAixs = GetPerpendicularVector(playerDir);
	float playerSample = max(PlayerRadius - playerDistance,0);
	float3x3 playerRotationMatrix = AngleAxis3x3(UNITY_PI * playerSample, playerAixs); // 计算草叶碰撞弯曲的矩阵，注意根据unity左手坐标系得到的结果是朝外部弯曲

	float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength; // 根据采样坐标得到纹理值，并映射到（-1，1），如果uv坐标值太大，将由纹理的wrap mode决定如何采样，这里是repeat
	float3 wind = normalize(float3(windSample.x, windSample.y, 0)); // 计算风刮动时草的弯曲旋转轴（切线空间）
	float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);


    float3x3 transformationMatrix = mul(mul(mul(mul(tangentToLocal, windRotation),playerRotationMatrix), facingRotationMatrix), bendRotationMatrix);
	//在transformationMatrix下边构建一个用于底部顶点的矩阵
	float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);

	float height = (rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
	float width = (rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
    float3 tangentNormal = float3(0, -1, 0); // 这里切线空间中顶点的法向量为(0, -1, 0)
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
