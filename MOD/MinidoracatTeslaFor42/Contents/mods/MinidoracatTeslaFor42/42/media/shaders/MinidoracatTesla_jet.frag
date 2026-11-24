#version 330

// MinidoracatTesla_jet: unlit gas, drawn here (no texture). u = 0 at the nozzle .. 1 at the far end; v around the
// cone: 0..1 the thin bright core, 2..3 the wider sheath, both 4 higher on the lift columns
// (scripts/blender/props/thruster_jets.py). Soft white steam with a cold cyan tint as in the official footage
// (f2-kickflip-replay 11m27): the density is continuous, thinning toward the end, and only gently modulated by a slow,
// coarse noise that scrolls outward with time (finer noise read as shattered ice, r2fx-sp-8). The edge fades over a
// wide band of `facing` that the same noise bends, so neither the cone's straight outline nor a clear tip shows; the
// start fades in so a car on the ground shows no solid wedge under it (r2fx-sp-6b take-off). The lift columns (the
// user's pick V2 of r2fx-sp-12) also carry a mid-frequency noise that shades them and pushes their outline in and out,
// more so lower down, fade in over a third of their length (no solid white at the nozzle) and are fainter.
// The blend is the vehicle's SRC_ALPHA, ONE_MINUS_SRC_ALPHA (no additive mode on this path); near-clear fragments are
// dropped so they write no depth.
//
// Time: declaring and reading TextureRust makes this a vehicle shader (Shader.isVehicleShader, Shader.java:719-721);
// only that path of Model.DrawVehicle sets ReflectionParam (Model.java:534-590), whose x is SkyBox.getTextureShift()
// (SkyBox.java:273-277): 0..1 over each skybox redraw, about a second (UpdateLimit(1000), SkyBox.java:29). With the
// skybox off (perfSkybox 2) it is 1 - night: the noise stands still, the jets keep their frayed look. The same path
// binds the car's skin to unit 0, so nothing here samples a texture of its own.

varying vec2 texCoords;
varying float facing;

uniform sampler2D TextureRust;
uniform vec4 TexturePainColor; // w: the vehicle's alpha (Model.java:585)
uniform vec3 ReflectionParam;

float hash(vec2 p)
{
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// value noise, periodic in both axes so the scroll wraps without a jump when x goes back from 1 to 0
float noise(vec2 p, vec2 period)
{
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(mod(i, period));
	float b = hash(mod(i + vec2(1.0, 0.0), period));
	float c = hash(mod(i + vec2(0.0, 1.0), period));
	float d = hash(mod(i + vec2(1.0, 1.0), period));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main()
{
	float u = texCoords.x;
	float lift = step(3.5, texCoords.y);
	float ly = texCoords.y - 4.0 * lift;
	float sheath = step(1.5, ly);
	float v = fract(ly);
	float t = clamp(ReflectionParam.x, 0.0, 1.0);
	// one jet length a second outward; scroll by whole periods (6 / 12 / 20 cells) so t = 1 matches t = 0
	float n = 0.65 * noise(vec2(u * 3.0 - t * 6.0, v * 3.0), vec2(6.0, 3.0))
	        + 0.35 * noise(vec2(u * 6.0 - t * 12.0, v * 6.0), vec2(12.0, 6.0));
	float bend = (n - 0.5) * (0.6 + 0.6 * u); // the noise bends the cone's outline
	float a;
	if (lift > 0.5) {
		float nMid = noise(vec2(u * 10.0 - t * 20.0, v * 8.0), vec2(20.0, 8.0));
		float body = smoothstep(0.0, 0.35, u) * pow(1.0 - u, mix(1.1, 0.8, sheath));
		float puff = (0.6 + 0.4 * n) * (0.85 + 0.3 * (nMid - 0.5));
		float edge = smoothstep(0.0, 0.7, facing + bend + (nMid - 0.5) * (0.5 + 0.8 * u));
		a = body * puff * edge * mix(0.6, 0.5, sheath) * 0.7;
	} else {
		float body = smoothstep(0.0, 0.2, u) * pow(1.0 - u, mix(1.1, 0.8, sheath));
		float puff = mix(0.55, 0.25, sheath) + mix(0.45, 0.75, sheath) * n; // billows: denser and thinner patches
		a = body * puff * smoothstep(0.0, 0.6, facing + bend) * mix(0.95, 0.6, sheath);
	}
	a *= TexturePainColor.w;
	a *= step(-1.0, texture2D(TextureRust, vec2(0.5)).a); // always 1: keeps TextureRust live (see the top)
	if (a < 0.03)
		discard;
	vec3 tint = mix(vec3(0.80, 0.94, 1.0), vec3(0.92, 0.97, 1.0), smoothstep(0.0, 0.5, u)); // white, cold cyan tint
	vec3 rgb = tint * (0.84 + 0.16 * n); // a billow's thick part a little brighter, so the lumps read
	gl_FragColor = vec4(rgb, a);
}
