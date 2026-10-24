#version 330

// Model Y see-through glass, skinned: the door windows and the rear glass (static = false, meshes in the doors FBX on
// their door's bone; the engine loads <name>.vert, ShaderProgram.java:278-286). Same outputs as
// MinidoracatTesla_glass_static.vert; the bones come from the door's AnimationPlayer, which the window part borrows
// as the door's child (BaseVehicle.java:11844-11850). Attribute locations follow ImportedSkinnedMesh: position,
// normal, bone weights, bone indices, UV0, UV1.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;
varying vec2 texCoords1;

layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec4 boneWeights;
layout (location = 3) in vec4 boneIndices;
layout (location = 4) in vec2 uv;
layout (location = 5) in vec2 uv2;

uniform mat4 ModelViewProjection;
uniform mat4 MatrixPalette[60];
uniform float targetDepth = 0.5;

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

	vec4 o = ModelViewProjection * position;
	float clip = (o.z + 1.0) / 2.0 + targetDepth - 0.5;
	o.z = clip * 2.0 - 1.0;
	gl_Position = o;
}
