#version 330

// MinidoracatTesla_vehicle, static (the body with its cabin and glass): vanilla vehicle_multiuv_static.vert plus
// reflectionsOn and viewModel, see MinidoracatTesla_vehicle.vert.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;
varying vec2 texCoords1;
varying vec4 positionEye;
varying float reflectionsOn;
varying vec3 viewModel;

layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec2 uv;
layout (location = 3) in vec2 uv2;

uniform mat4 ModelViewProjection;
uniform mat4 transform;
uniform float targetDepth = 0.5;
uniform sampler2D TextureReflectionA;

void main()
{
	vec4 position = vec4(vertex.xyz, 1);
	vec4 normal = vec4(normal.xyz, 0);

	texCoords = uv.st;
	texCoords1 = uv2.st;

	vertNormal = (transform * normal).xyz;
	mat4 m = ModelViewProjection;   // vertNormal is already in transform's output space
	vec3 r2 = vec3(m[0][2], m[1][2], m[2][2]);
	viewModel = normalize(cross(vec3(m[0][0], m[1][0], m[2][0]), vec3(m[0][1], m[1][1], m[2][1])));
	viewModel *= -sign(dot(viewModel, r2));
	vertColour = vec3(1,1,1);

#if __VERSION__ >= 130
	reflectionsOn = textureSize(TextureReflectionA, 0).x > 1 ? 1.0 : 0.0;
#else
	reflectionsOn = 0.0;
#endif

	positionEye = (ModelViewProjection * transform * position) - vec4(-0.2, 0.2, 0.2, 0);

	vec4 o = ModelViewProjection * transform * position;
	float clip = ((o.z+1.0) / 2.0); // -1,+1 -> 0,2 -> 0,1
	clip += targetDepth - 0.5;
	o.z = (clip*2)-1; // 0-1 -> 0-2 -> -1,+1
	gl_Position = o;
}
