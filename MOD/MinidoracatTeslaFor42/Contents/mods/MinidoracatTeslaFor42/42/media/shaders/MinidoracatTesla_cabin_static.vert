#version 330

// Model Y cabin (GloveBox model "Cabin", static = true): vanilla vehiclewheel_static.vert reading UV0. An FBX static
// mesh binds UV0 to location 2 and UV1 to 3 (ImportedStaticMesh.java:29-35); vehiclewheel's own vert reads 3.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;

layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec2 uv;

uniform mat4 ModelViewProjection;
uniform mat4 transform;
uniform float targetDepth = 0.5;

void main()
{
	texCoords = uv.st;
	vertNormal = (transform * vec4(normal.xyz, 0.0)).xyz;
	vertColour = vec3(1.0, 1.0, 1.0);

	vec4 o = ModelViewProjection * transform * vec4(vertex.xyz, 1.0);
	float clip = (o.z + 1.0) / 2.0 + targetDepth - 0.5;
	o.z = clip * 2.0 - 1.0;
	gl_Position = o;
}
