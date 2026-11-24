#version 330

// MinidoracatTesla_jet: unlit gas, drawn here (no texture). u = 0 at the nozzle .. 1 at the far end; v around the
// cone: 0..1 the thin bright core, 2..3 the wider sheath (scripts/blender/props/thruster_jets.py). White mist as in the
// official footage (f2-kickflip-replay 11m27), a touch of pale cyan only near the nozzle. Noise stretched along the
// jet scrolls outward with time and eats the edge (low facing) more the further from the nozzle, so the outline frays
// and the tail breaks up into fog instead of narrowing to a clear tip; the start fades in over the first metre so a
// car on the ground shows no solid wedge under it (r2fx-sp-6b take-off). The blend is the vehicle's SRC_ALPHA,
// ONE_MINUS_SRC_ALPHA (no additive mode on this path); near-clear fragments are dropped so they write no depth.
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
	float sheath = step(1.5, texCoords.y);
	float v = fract(texCoords.y);
	float t = clamp(ReflectionParam.x, 0.0, 1.0);
	// two jet lengths a second outward; scroll by whole periods (16 / 32 cells) so t = 1 matches t = 0
	float n = 0.6 * noise(vec2(u * 8.0 - t * 16.0, v * 6.0), vec2(16.0, 6.0))
	        + 0.4 * noise(vec2(u * 16.0 - t * 32.0, v * 12.0), vec2(32.0, 12.0));
	float body = smoothstep(0.0, 0.25, u) * pow(1.0 - u, 0.7);
	float broken = mix(1.0, smoothstep(0.15 + 0.45 * u, 0.75, n), mix(0.3, 0.9, max(u, 0.6 * sheath)));
	float edge = smoothstep(0.15 + 0.4 * u, 0.7 + 0.25 * u, facing + (n - 0.5) * (0.7 + 1.0 * u));
	float a = body * broken * edge * mix(0.85, 0.5, sheath) * TexturePainColor.w;
	a *= step(-1.0, texture2D(TextureRust, vec2(0.5)).a); // always 1: keeps TextureRust live (see the top)
	if (a < 0.03)
		discard;
	vec3 tint = mix(vec3(0.78, 0.93, 1.0), vec3(1.0), smoothstep(0.0, 0.3, u)); // pale cyan only at the nozzle
	vec3 rgb = tint * mix(1.0, 0.82 + 0.18 * n, sheath); // the sheath's fog a little uneven grey-white
	gl_FragColor = vec4(rgb, a);
}
