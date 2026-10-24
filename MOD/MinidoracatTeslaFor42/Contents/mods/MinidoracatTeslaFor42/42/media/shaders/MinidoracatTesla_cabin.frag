#version 120

// Model Y cabin (GloveBox model "Cabin"): vanilla vehiclewheel.frag (palette texture, 3-step lighting, tint) plus
// two things the cabin needs behind tinted glass: a light floor so the seats keep an outline at night, and the
// centre screen (the only palette texel brighter than SCREEN_MIN) lit by itself. Not a vehicle-path shader (no
// TextureRust): the engine binds Texture and Alpha (VehicleSubModelInstance).

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;

uniform sampler2D Texture;

uniform vec3 TintColour;

uniform vec3 AmbientColour;
uniform vec3 Light0Direction;
uniform vec3 Light0Colour;
uniform vec3 Light1Direction;
uniform vec3 Light1Colour;
uniform vec3 Light2Direction;
uniform vec3 Light2Colour;
uniform vec3 Light3Direction;
uniform vec3 Light3Colour;
uniform vec3 Light4Direction;
uniform vec3 Light4Colour;

uniform float Alpha;

#include "util/math"

const float NIGHT_FLOOR = 0.12;   // calibration knob: lowest lighting
const float SCREEN_MIN = 0.55;    // palette texels brighter than this glow (build.py CABIN_RGB "screen")

float quantLight(vec3 normal, vec3 dir)
{
	float d = max(dot(normal, normalize(dir)), 0.0);
	quantise(d, 3.0);
	return d;
}

void main()
{
	vec3 normal = normalize(vertNormal);
	vec3 col = texture2D(Texture, texCoords).xyz;

	vec3 lighting = AmbientColour;
	lighting += Light0Colour * quantLight(normal, Light0Direction);
	lighting += Light1Colour * quantLight(normal, Light1Direction);
	lighting += Light2Colour * quantLight(normal, Light2Direction);
	lighting += Light3Colour * quantLight(normal, Light3Direction);
	lighting += Light4Colour * quantLight(normal, Light4Direction);
	lighting = clamp(lighting, NIGHT_FLOOR, 1.0);   // util/math's overloads hide the vec3 builtins
	vec3 TintColourNew = desaturate(TintColour, 0.3);

	vec3 lit = col * lighting * TintColourNew;
	float glow = step(SCREEN_MIN, max(col.x, max(col.y, col.z)));
	gl_FragColor = vec4(mix(lit, col * 0.85, glow), Alpha);
}
