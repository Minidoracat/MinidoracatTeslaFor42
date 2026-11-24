#version 330

// MinidoracatTesla_jet: unlit gas. The gradient (u = 0 at the nozzle) gives colour and alpha; the white core shows
// where the cone faces the camera, its silhouette fades out so the column has no hard edge. The blend is the
// vehicle's SRC_ALPHA, ONE_MINUS_SRC_ALPHA (no additive mode on this path); near-clear fragments are dropped so
// they write no depth.

varying vec2 texCoords;
varying float facing;

uniform sampler2D Texture;
uniform float Alpha;

void main()
{
	vec4 c = texture2D(Texture, texCoords);
	float a = c.a * Alpha * smoothstep(0.05, 0.7, facing);
	if (a < 0.04)
		discard;
	vec3 rgb = mix(c.rgb, vec3(1.0), facing * facing * (1.0 - texCoords.x) * 0.6);
	gl_FragColor = vec4(rgb, a);
}
