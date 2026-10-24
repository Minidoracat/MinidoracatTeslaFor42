#version 330

// MinidoracatTesla_vehicle, skinned (static = false: the doors, tailgate and frunk lid on VehicleSkeleton; the engine
// loads <name>.vert, ShaderProgram.java:278-286). Attribute locations follow ImportedSkinnedMesh: position, normal,
// bone weights, bone indices, UV0, UV1. Same outputs as MinidoracatTesla_vehicle_static.vert.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;
varying vec2 texCoords1;
varying vec4 positionEye;
varying float reflectionsOn;

layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec4 boneWeights;
layout (location = 3) in vec4 boneIndices;
layout (location = 4) in vec2 uv;
layout (location = 5) in vec2 uv2;

uniform mat4 ModelViewProjection;
uniform mat4 MatrixPalette[60];
uniform float targetDepth = 0.5;
uniform sampler2D TextureReflectionA;

void main()
{
	mat4 skin = mat4(0.0);
	if (boneWeights.x > 0.0) skin += MatrixPalette[int(boneIndices.x)] * boneWeights.x;
	if (boneWeights.y > 0.0) skin += MatrixPalette[int(boneIndices.y)] * boneWeights.y;
	if (boneWeights.z > 0.0) skin += MatrixPalette[int(boneIndices.z)] * boneWeights.z;
	if (boneWeights.w > 0.0) skin += MatrixPalette[int(boneIndices.w)] * boneWeights.w;

	vec4 position = skin * vec4(vertex.xyz, 1.0);
	texCoords = uv.st;
	texCoords1 = uv2.st;
	vertNormal = (skin * vec4(normal.xyz, 0.0)).xyz;
	vertColour = vec3(1.0, 1.0, 1.0);

	// the reflection map (the 512 x 512 sky, SkyBox.java:207) is bound only with reflections on in GL 3.3 (Model.java:
	// 556-570); unit 8 is empty otherwise, and an empty unit reads 1 x 1 on NVIDIA (0 x 0 elsewhere). GL 2.1 mode
	// rewrites this file to #version 120 (ShaderUnit.java:302-308), which has no textureSize
#if __VERSION__ >= 130
	reflectionsOn = textureSize(TextureReflectionA, 0).x > 1 ? 1.0 : 0.0;
#else
	reflectionsOn = 0.0;
#endif

	vec4 o = ModelViewProjection * position;
	positionEye = o - vec4(-0.2, 0.2, 0.2, 0.0);
	float clip = (o.z + 1.0) / 2.0 + targetDepth - 0.5;
	o.z = clip * 2.0 - 1.0;
	gl_Position = o;
}
