#version 120

// Model Y see-through glass: the body's panes (GloveBox model "Glass", static) and each door's window (the Window /
// WindshieldRear part model, skinned on the door's bone), all drawn after the cabin. Based on vanilla
// vehicle_multiuv.frag.
// It samples TextureRust, so the engine binds the parent car's skin / mask / damage / uninstall state (vehicle shader
// path, Shader.java:149,719-721; Model.java:534-590): cracks, blood, removed and open windows follow the mask zones.
// No reflection maps: a mod shader name is never swapped for _noreflect (ModelManager.java:1302-1311), so with
// reflections off or GL 2.1 those units are unbound (Model.java:558,566); a constant sky tint stands in, dimmed by the
// same lighting as the body.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;
varying vec2 texCoords1;

uniform vec4 TexturePainColor;
uniform sampler2D TextureRust;
uniform float TextureRustA;
uniform sampler2D TextureMask;
uniform sampler2D TextureDamage1Overlay;
uniform sampler2D TextureDamage1Shell;
uniform sampler2D TextureDamage2Overlay;
uniform sampler2D TextureDamage2Shell;

uniform mat4 TextureUninstall1;
uniform mat4 TextureUninstall2;
uniform mat4 TextureDamage1Enables1;
uniform mat4 TextureDamage1Enables2;
uniform mat4 TextureDamage2Enables1;
uniform mat4 TextureDamage2Enables2;
uniform mat4 MatBlood1Enables1;
uniform mat4 MatBlood1Enables2;
uniform mat4 MatBlood2Enables1;
uniform mat4 MatBlood2Enables2;

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

#include "util/math"
#include "util/dommat4"

#include "vehicle_common.frag"

// calibration knobs: opacity per pane (alpha = share of the glass colour over the cabin), glass colour
// (game-readable, not the car's light transmission: the driver and the seats must read at default zoom by day)
const float A_WINDSCREEN = 0.22;   // WinT
const float A_FRONT_SIDE = 0.28;   // WinLH, WinRH
const float A_REAR = 0.40;         // WinLT, WinRT, WinH (privacy glass)
const float A_ROOF = 0.50;         // LightBar L (colZone25): the roof glass, unused by any Tesla light
const vec3 GLASS_TINT = vec3(0.06, 0.06, 0.07);
const vec3 SKY = vec3(0.50, 0.60, 0.75);
const float SKY_MIX = 0.30;        // vanilla windows mix 30 % reflection at refWindows 0.4 (vehicle_multiuv.frag:151)
const vec3 FRIT = vec3(0.03);      // texels in no glass zone: the black band round the pane

float zone(vec4 m, vec3 c)
{
	return 1.0 - step(0.01, length(m.xyz - c));
}

float quantLight(vec3 normal, vec3 dir)
{
	float d = max(dot(normal, normalize(dir)), 0.0);
	quantise(d, 3.0);
	return d;
}

void main()
{
	vec4 texColorMask = texture2D(TextureMask, texCoords);

	// mask zones of the panes and of the uninstall / damage matrices (vehicle_multiuv.frag:93-127)
	mat4 texen1 = mat4(0.0);
	texen1[0][0] = zone(texColorMask, colZone1);
	texen1[0][1] = zone(texColorMask, colZone2);
	texen1[0][2] = zone(texColorMask, colZone3);
	texen1[0][3] = zone(texColorMask, colZone4);
	texen1[1][0] = zone(texColorMask, colZone5);
	texen1[1][1] = zone(texColorMask, colZone6);
	texen1[1][2] = zone(texColorMask, colZone7);
	texen1[1][3] = zone(texColorMask, colZone8);
	texen1[2][0] = zone(texColorMask, colZone9);
	texen1[2][1] = zone(texColorMask, colZone10);
	texen1[2][2] = zone(texColorMask, colZone11);
	texen1[2][3] = zone(texColorMask, colZone12);
	texen1[3][0] = zone(texColorMask, colZone13);
	texen1[3][1] = zone(texColorMask, colZone14);
	texen1[3][2] = zone(texColorMask, colZone15);
	texen1[3][3] = zone(texColorMask, colZone16);
	mat4 texen2 = mat4(0.0);
	texen2[0][0] = zone(texColorMask, colZone17);
	texen2[0][1] = zone(texColorMask, colZone18);
	texen2[0][2] = zone(texColorMask, colZone19);
	texen2[0][3] = zone(texColorMask, colZone20);
	texen2[1][0] = zone(texColorMask, colZone21);
	texen2[1][1] = zone(texColorMask, colZone22);
	texen2[1][2] = zone(texColorMask, colZone23);
	texen2[1][3] = zone(texColorMask, colZone24);
	texen2[2][0] = zone(texColorMask, colZone25);
	texen2[2][1] = zone(texColorMask, colZone26);
	texen2[2][2] = zone(texColorMask, colZone27);

	// removed or open window: the pane is a hole onto the cabin
	if (dommat4(texen1, TextureUninstall1) + dommat4(texen2, TextureUninstall2) > 0.5)
		discard;

	float t2en = step(0.5, dommat4(texen1, TextureDamage1Enables1) + dommat4(texen2, TextureDamage1Enables2));
	float t3en = step(0.5, dommat4(texen1, TextureDamage2Enables1) + dommat4(texen2, TextureDamage2Enables2));

	float window = clamp(texen1[1][2] + texen1[1][3] + texen1[2][0] + texen1[2][1] + texen1[2][2] + texen1[2][3], 0.0, 1.0);
	float glass = clamp(window + texen2[2][0], 0.0, 1.0);
	float alpha = A_WINDSCREEN * texen1[2][2] + A_FRONT_SIDE * (texen1[1][2] + texen1[2][0])
		+ A_REAR * (texen1[1][3] + texen1[2][1] + texen1[2][3]) + A_ROOF * texen2[2][0];
	alpha = mix(1.0, alpha, glass);

	vec3 normal = normalize(vertNormal);
	vec3 lighting = AmbientColour;
	lighting += Light0Colour * quantLight(normal, Light0Direction);
	lighting += Light1Colour * quantLight(normal, Light1Direction);
	lighting += Light2Colour * quantLight(normal, Light2Direction);
	lighting += Light3Colour * quantLight(normal, Light3Direction);
	lighting += Light4Colour * quantLight(normal, Light4Direction);
	lighting = clamp(lighting, 0.0, 1.0);
	vec3 TintColourNew = desaturate(TintColour, 0.3);

	vec3 col = mix(FRIT, mix(GLASS_TINT, SKY, SKY_MIX), glass);

	vec4 texColorRust = texture2D(TextureRust, texCoords1);
	col = mix(col, texColorRust.xyz, texColorRust.a * TextureRustA);

	// blood under the cracks, as vanilla windows; cracked or bloody glass turns opaque where marked
	vec4 texColorBlood2 = texture2D(TextureDamage2Overlay, texCoords1);
	vec4 colmask = texture2D(TextureDamage1Overlay, texCoords1);
	float intensity = dommat4(texen1, MatBlood1Enables1) + dommat4(texen2, MatBlood1Enables2);
	float maskAlpha = step(0.5, dommat4(texen1, MatBlood2Enables1) + dommat4(texen2, MatBlood2Enables2));
	vec3 bloodless = col;
	col = addBlood(texColorBlood2, colmask, intensity, maskAlpha * glass, lighting, TintColourNew, col);
	float marked = clamp(length(col - bloodless) * 4.0, 0.0, 1.0);

	vec4 shell1 = texture2D(TextureDamage1Shell, texCoords1);
	vec4 shell2 = texture2D(TextureDamage2Shell, texCoords1);
	col = mix(col, shell1.xyz, shell1.a * t2en);
	col = mix(col, shell2.xyz, shell2.a * t3en);
	marked = max(marked, max(shell1.a * t2en, shell2.a * t3en));
	alpha = mix(alpha, 1.0, marked);

	col *= lighting * TintColourNew;

	gl_FragColor = vec4(col, alpha * TexturePainColor.a);
}
