#version 330

// MinidoracatTesla_jet (TeslaThruster's Lift / Side / Rear cones, scripts/blender/props/thruster_jets.py): a vehicle
// shader (the fragment reads TextureRust), so Model.DrawVehicle's vehicle path sets the uniforms; static, so transform
// is the identity (Model.java:586-587). facing = how squarely the cone's side faces the camera (1) or grazes (0).

varying vec2 texCoords;
varying float facing;

layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec2 uv;

uniform mat4 ModelViewProjection;
uniform mat4 transform;
uniform float targetDepth = 0.5;

void main()
{
	texCoords = uv.st;
	mat4 m = ModelViewProjection;   // the camera's direction in model space, as MinidoracatTesla_vehicle_static.vert
	vec3 view = normalize(cross(vec3(m[0][0], m[1][0], m[2][0]), vec3(m[0][1], m[1][1], m[2][1])));
	facing = abs(dot(normalize((transform * vec4(normal.xyz, 0)).xyz), view));

	vec4 o = m * transform * vec4(vertex.xyz, 1);
	float clip = (o.z + 1.0) / 2.0 + targetDepth - 0.5;
	o.z = clip * 2.0 - 1.0;
	gl_Position = o;
}
