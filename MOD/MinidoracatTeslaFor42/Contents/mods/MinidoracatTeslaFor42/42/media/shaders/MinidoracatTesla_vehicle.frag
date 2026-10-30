#version 120

// Model Y body, doors, tailgate and frunk lid in one draw each: vanilla vehicle_multiuv.frag for the paint, plus the
// see-through glass and the 3-D cabin, told apart by UV1 (scripts/blender/skf/convert.py pieces):
//   UV1 u in [0, 1]  paint: vanilla vehicle_multiuv / _noreflect plus the paint sheen (SHEEN_* below)
//   UV1 u in [2+2k, 3+2k]  glass face of pane zone k (GLASS_ZONE below, convert.py GLASS_ZONES): UV1 - (2+2k, 0) is its
//                    damage UV; translucent per pane, a hole when the window is removed, open or smashed (uninstall
//                    matrices), cracks and blood turn it opaque where marked. The zone rides in UV1, not the mask:
//                    the mask is bilinear and only counts within 0.01 of a zone colour, so a glass edge read from it
//                    is a staircase of its 512 texels
//   UV1 u <= -2.5    cabin: palette cell = -2.5 - u (CABIN below; u, since the loader flips v, ImportedStaticMesh.java:
//                    59); lit with a floor so seats keep an outline at night, the screen glows. The shell's faces in a
//                    door opening carry door k + d = 1 - v (cabin.py SHELL_DOORS; d < 0 inside the opening, linear,
//                    so the cut follows the sill / arch / tailgate edge per pixel) and are dropped there while that
//                    door is open (bit k-1 of the paint hue's integer part, Liftgate.lua syncShell; every hue reader
//                    takes it mod 1) or removed (its uninstall slot, BaseVehicle.doDoorDamage / doOtherBodyWorkDamage)
// Inside one mesh the triangles draw in index order: paint, cabin, glass (pzveh.py order_faces), so the glass blends
// over the cabin and the seated characters drawn before the car.
// A mod shader name is never swapped for _noreflect (ModelManager.java:1298-1311): the vertex shader reports whether
// the reflection maps are bound (reflections on and GL 3.3, Model.java:556-570) and the reflection terms scale by it,
// which leaves exactly vehicle_multiuv_noreflect.frag when they are not.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;
varying vec2 texCoords1;
varying vec4 positionEye;
varying float reflectionsOn;
varying vec3 viewModel;

uniform sampler2D Texture0;
uniform vec4 TexturePainColor;
uniform sampler2D TextureRust;
uniform float TextureRustA;
uniform sampler2D TextureMask;
uniform sampler2D TextureLights;
uniform sampler2D TextureDamage1Overlay;
uniform sampler2D TextureDamage1Shell;
uniform sampler2D TextureDamage2Overlay;
uniform sampler2D TextureDamage2Shell;
uniform sampler2D TextureReflectionA;
uniform sampler2D TextureReflectionB;
uniform vec3 ReflectionParam; // x: 1-A, 0 - B; y - reflection windows; z - reflection body

uniform mat4 TextureUninstall1;
uniform mat4 TextureUninstall2;
uniform mat4 TextureLightsEnables1;
uniform mat4 TextureLightsEnables2;
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
#include "util/SphereMap"
#include "util/dommat4"

#include "vehicle_common.frag"

// glass calibration knobs: opacity per pane (alpha = share of the glass colour over the cabin), glass colour
// (game-readable, not the car's light transmission: the driver and the seats must read at default zoom by day)
const float A_WINDSCREEN = 0.22;   // WinT
const float A_FRONT_SIDE = 0.28;   // WinLH, WinRH
const float A_REAR = 0.40;         // WinLT, WinRT, WinH (privacy glass)
const float A_ROOF = 0.50;         // LightBar L (colZone25): the roof glass, unused by any Tesla light
const vec3 GLASS_TINT = vec3(0.06, 0.06, 0.07);
const vec3 SKY = vec3(0.50, 0.60, 0.75);
const float SKY_MIX = 0.30;        // vanilla windows mix 30 % reflection at refWindows 0.4 (vehicle_multiuv.frag:151)
// glass zone k (convert.py GLASS_ZONES): WinT, WinH, WinLH, WinLT, WinRH, WinRT, LightBar L (the roof glass)
const vec3 GLASS_ZONE[7] = vec3[7](colZone11, colZone12, colZone9, colZone10, colZone7, colZone8, colZone25);

// paint sheen (calibration knobs): the skin carries no highlight, so the gloss that moves as the car turns is drawn
// here, on paint texels only (skin alpha 254, convert.py PAINT_ALPHA). Blinn-Phong from the sky and from the nearby
// lights Light0-4, times refBody (ReflectionParam.z: 0.3, 0.1 on a rusty car, BaseVehicle.java:5987-5992) over its
// usual 0.3; Fresnel raises the sky reflection's share toward grazing angles.
// Model space (decoded in game, tesla-sheen-1027f): +X the car's right, +Y up, +Z forward, mirrored, so cross(up, x)
// turns the other way than in the world. The sky's direction is fixed in the world, built from the camera, which never
// turns: SHEEN_SUN = (camera left, up, toward the camera); scaled by AmbientColour, it fades with the daylight
const vec3 SHEEN_SUN = vec3(0.45, 0.85, -0.25);
const float SHEEN_POW = 16.0;      // lobe: half height about 17 degrees off the mirror direction
const float SHEEN_SKY = 0.22;      // peak added at full daylight
const float SHEEN_LAMP = 0.45;     // peak added per unit of a nearby light's colour
const float SHEEN_LAMP_UP = 0.5;   // a nearby light's direction gets this much up (its height is lost, below)
const float SHEEN_FRESNEL = 1.5;   // sky reflection share x (1 + SHEEN_FRESNEL x (1 - n.v)^5)
// finish flags in the skin alpha (convert.py PAINT_ALPHAS; Model Y / Model 3 paint is 254 = gloss above):
// 253 brushed stainless (Cybertruck): a tighter, brighter lobe and a stronger sky reflection, metal-like;
// 252 satin wrap film: a wide, weak lobe and no Fresnel boost
const float SHEEN_STEEL_POW = 40.0;
const float SHEEN_STEEL_GAIN = 1.2;  // 1.6: the hood read near white (tesla-ctbody-1030a)
const float SHEEN_STEEL_REF = 1.0;  // sky reflection share x (1 + this)
const float SHEEN_MATTE_POW = 6.0;
const float SHEEN_MATTE_GAIN = 0.35;

// a nearby light as the vehicle shader gets it: (right, forward, height) of the direction to it, the height taken
// at the ground (BaseVehicle.getLocalPos sets y 0, ModelSlotRenderData.java:256-262; Shader.setLight swaps y / z,
// :530-554; a lamp behind-left decoded (-0.82, -0.55, -0.07), tesla-sheen-1027f), so vanilla's diffuse lights the
// roof for a lamp ahead. Swapped back to (right, up, forward) here
vec3 lampSheen(vec3 dir, vec3 colour, vec3 n, vec3 v, float lobe)
{
	vec3 l = normalize(vec3(dir.x, max(dir.z, 0.0) + SHEEN_LAMP_UP, dir.y));
	return colour * SHEEN_LAMP * pow(max(dot(n, normalize(l + v)), 0.0), lobe);
}

// cabin palette, sRGB 0-255, in pzveh.py CABIN_CELLS order. Black interior a step lighter than life so the seats
// read against the floor through the glass (calibration knob)
const vec3 CABIN[10] = vec3[10](
	vec3(22.0, 22.0, 24.0),     // floor
	vec3(40.0, 40.0, 44.0),     // liner
	vec3(100.0, 100.0, 106.0),  // seat
	vec3(30.0, 30.0, 32.0),     // base
	vec3(58.0, 58.0, 62.0),     // dash
	vec3(112.0, 106.0, 98.0),   // trim
	vec3(46.0, 46.0, 50.0),     // console
	vec3(28.0, 28.0, 30.0),     // wheel
	vec3(16.0, 16.0, 18.0),     // screen_back
	vec3(170.0, 192.0, 214.0)); // screen: lit by itself
const int CABIN_SCREEN = 9;
const float NIGHT_FLOOR = 0.12;    // cabin's lowest lighting (calibration knob)

void main()
{
	float glassFace = step(1.5, texCoords1.x);
	float glassZone = glassFace * floor((texCoords1.x - 2.0) * 0.5);
	vec2 uv1 = texCoords1 - vec2(glassFace * (2.0 + 2.0 * glassZone), 0.0);

	vec3 normal = normalize(vertNormal);
	vec4 tex = texture2D(Texture0, texCoords);

	vec3 col = tex.xyz;
	float dotprod;

	vec4 texColorMask = texture2D(TextureMask, texCoords);
	if (glassFace > 0.5)
		texColorMask.xyz = GLASS_ZONE[int(glassZone)];
	vec4 texColorRust = texture2D(TextureRust, uv1);
	vec4 texColorLights = texture2D(TextureLights, texCoords);
	vec4 texColorDamage1Overlay = texture2D(TextureDamage1Overlay, uv1);
	vec4 texColorDamage1Shell = texture2D(TextureDamage1Shell, uv1);
	vec4 texColorDamage2Overlay = texture2D(TextureDamage2Overlay, uv1);
	vec4 texColorDamage2Shell = texture2D(TextureDamage2Shell, uv1);

	vec3 lighting = AmbientColour;
	dotprod = max(dot(normal, normalize(Light0Direction)), 0.0);
	quantise(dotprod, 3.0);
	lighting += Light0Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light1Direction)), 0.0);
	quantise(dotprod, 3.0);
	lighting += Light1Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light2Direction)), 0.0);
	quantise(dotprod, 3.0);
	lighting += Light2Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light3Direction)), 0.0);
	quantise(dotprod, 3.0);
	lighting += Light3Colour * dotprod;

	dotprod = max(dot(normal, normalize(Light4Direction)), 0.0);
	quantise(dotprod, 3.0);
	lighting += Light4Colour * dotprod;

	vec3 TintColourNew = desaturate(TintColour, 0.3);

	if (texCoords1.x < -1.0)
	{
		float kd = 1.0 - texCoords1.y;
		int door = int(floor(kd + 0.5));
		if (door > 0 && kd < float(door))
		{
			float open = mod(floor(floor(TexturePainColor.x) / exp2(float(door - 1))), 2.0);
			// uninstall slot i at [i % 4][i / 4] (uploaded transposed, Shader.setMatrix): 1, 8, 5, 12 and 2nd 10
			float gone = door == 1 ? TextureUninstall1[1][0] : door == 2 ? TextureUninstall1[0][2]
				: door == 3 ? TextureUninstall1[1][1] : door == 4 ? TextureUninstall1[0][3] : TextureUninstall2[2][2];
			if (open + gone > 0.5)
				discard;
		}
		int cell = int(-texCoords1.x - 2.0);
		vec3 c = CABIN[cell] / 255.0;
		vec3 lit = c * clamp(lighting, NIGHT_FLOOR, 1.0) * TintColourNew;   // util/math's overloads hide the vec3 builtins
		float glow = cell == CABIN_SCREEN ? 1.0 : 0.0;
		gl_FragColor = vec4(mix(lit, c * 0.85, glow), TexturePainColor.a);
		return;
	}

	lighting.x = clamp(lighting.x, 0.0, 1.0);
	lighting.y = clamp(lighting.y, 0.0, 1.0);
	lighting.z = clamp(lighting.z, 0.0, 1.0);

	mat4 texen1 = mat4( 0.0 );
	texen1[0][0] = (1.0-step(0.01,length(texColorMask.xyz-colZone1)));
	texen1[0][1] = (1.0-step(0.01,length(texColorMask.xyz-colZone2)));
	texen1[0][2] = (1.0-step(0.01,length(texColorMask.xyz-colZone3)));
	texen1[0][3] = (1.0-step(0.01,length(texColorMask.xyz-colZone4)));
	texen1[1][0] = (1.0-step(0.01,length(texColorMask.xyz-colZone5)));
	texen1[1][1] = (1.0-step(0.01,length(texColorMask.xyz-colZone6)));
	texen1[1][2] = (1.0-step(0.01,length(texColorMask.xyz-colZone7)));
	texen1[1][3] = (1.0-step(0.01,length(texColorMask.xyz-colZone8)));
	texen1[2][0] = (1.0-step(0.01,length(texColorMask.xyz-colZone9)));
	texen1[2][1] = (1.0-step(0.01,length(texColorMask.xyz-colZone10)));
	texen1[2][2] = (1.0-step(0.01,length(texColorMask.xyz-colZone11)));
	texen1[2][3] = (1.0-step(0.01,length(texColorMask.xyz-colZone12)));
	texen1[3][0] = (1.0-step(0.01,length(texColorMask.xyz-colZone13)));
	texen1[3][1] = (1.0-step(0.01,length(texColorMask.xyz-colZone14)));
	texen1[3][2] = (1.0-step(0.01,length(texColorMask.xyz-colZone15)));
	texen1[3][3] = (1.0-step(0.01,length(texColorMask.xyz-colZone16)));

	mat4 texen2 = mat4( 0.0 );
	texen2[0][0] = (1.0-step(0.01,length(texColorMask.xyz-colZone17)));
	texen2[0][1] = (1.0-step(0.01,length(texColorMask.xyz-colZone18)));
	texen2[0][2] = (1.0-step(0.01,length(texColorMask.xyz-colZone19)));
	texen2[0][3] = (1.0-step(0.01,length(texColorMask.xyz-colZone20)));
	texen2[1][0] = (1.0-step(0.01,length(texColorMask.xyz-colZone21)));
	texen2[1][1] = (1.0-step(0.01,length(texColorMask.xyz-colZone22)));
	texen2[1][2] = (1.0-step(0.01,length(texColorMask.xyz-colZone23)));
	texen2[1][3] = (1.0-step(0.01,length(texColorMask.xyz-colZone24)));
	texen2[2][0] = (1.0-step(0.01,length(texColorMask.xyz-colZone25)));
	texen2[2][1] = (1.0-step(0.01,length(texColorMask.xyz-colZone26)));
	texen2[2][2] = (1.0-step(0.01,length(texColorMask.xyz-colZone27)));

	float windowAlpha = clamp(texen1[1][2] + texen1[1][3] + texen1[2][0] + texen1[2][1] + texen1[2][2] + texen1[2][3], 0.0, 1.0);

	if (glassFace > 0.5)
	{
		// removed, open or smashed window: the pane is a hole onto the cabin
		if (dommat4(texen1, TextureUninstall1) + dommat4(texen2, TextureUninstall2) > 0.5)
			discard;

		// the roof glass (LightBar L) has no part, so no damage; the debug "Damage1/2 everywhere" options would
		// otherwise lay the untinted shell (its raw colour) over it (E2E TeslaCabin-modely-after-1024b Fwin-S-Damage2)
		float noDamage = 1.0 - texen2[2][0];
		float g2en = noDamage * step(0.5, dommat4(texen1, TextureDamage1Enables1) + dommat4(texen2, TextureDamage1Enables2));
		float g3en = noDamage * step(0.5, dommat4(texen1, TextureDamage2Enables1) + dommat4(texen2, TextureDamage2Enables2));

		float alpha = A_WINDSCREEN * texen1[2][2] + A_FRONT_SIDE * (texen1[1][2] + texen1[2][0])
			+ A_REAR * (texen1[1][3] + texen1[2][1] + texen1[2][3]) + A_ROOF * texen2[2][0];

		vec3 g = mix(GLASS_TINT, SKY, SKY_MIX);
		g = mix(g, texColorRust.xyz, texColorRust.a * TextureRustA);

		// blood under the cracks, as vanilla windows; cracked or bloody glass turns opaque where marked
		float gIntensity = dommat4(texen1, MatBlood1Enables1) + dommat4(texen2, MatBlood1Enables2);
		float gMaskAlpha = step(0.5, dommat4(texen1, MatBlood2Enables1) + dommat4(texen2, MatBlood2Enables2));
		vec3 bloodless = g;
		g = addBlood(texColorDamage2Overlay, texColorDamage1Overlay, gIntensity, gMaskAlpha, lighting, TintColourNew, g);
		float marked = clamp(length(g - bloodless) * 4.0, 0.0, 1.0);

		g = mix(g, texColorDamage1Shell.xyz, texColorDamage1Shell.a * g2en);
		g = mix(g, texColorDamage2Shell.xyz, texColorDamage2Shell.a * g3en);
		marked = max(marked, max(texColorDamage1Shell.a * g2en, texColorDamage2Shell.a * g3en));
		alpha = mix(alpha, 1.0, marked);

		gl_FragColor = vec4(g * lighting * TintColourNew, alpha * TexturePainColor.a);
		return;
	}

	float t1en = step(0.5, dommat4(texen1, TextureLightsEnables1) + dommat4(texen2, TextureLightsEnables2) );
	float t2en = step(0.5, dommat4(texen1, TextureDamage1Enables1) + dommat4(texen2, TextureDamage1Enables2) );
	float t3en = step(0.5, dommat4(texen1, TextureDamage2Enables1) + dommat4(texen2, TextureDamage2Enables2) );
	float t4en = step(0.5, dommat4(texen1, TextureUninstall1) + dommat4(texen2, TextureUninstall2) );

	float frontAlpha = clamp(texen1[0][0] + texen2[0][1] + texen2[0][2], 0.0, 1.0);
	float tailAlpha = clamp(texen1[0][1] + texen2[0][3] + texen2[1][0] + texen2[1][1] + texen2[1][2], 0.0, 1.0);
	float noTintAlpha = clamp(windowAlpha + frontAlpha + tailAlpha, 0.0, 1.0);

	vec3 fragHSV = rgb2hsv(col.rgb).xyz;
	fragHSV.x = TexturePainColor.x;
	fragHSV.y = clamp(fragHSV.y + TexturePainColor.y - 0.5, 0.0, 0.9999);
	fragHSV.z = clamp(fragHSV.z + TexturePainColor.z - 0.5, 0.0, 0.9999);
	fragHSV.xyz = mod(fragHSV.xyz, 1.0);
	col = mix(col, hsv2rgb(fragHSV), 1.0-tex.a);

	// vehicle_multiuv's reflection; reflectionsOn = 0 leaves vehicle_multiuv_noreflect
	float ref_en = texen1[1][2] + texen1[1][3] + texen1[2][0] + texen1[2][1] + texen1[2][2] + texen1[2][3];
	vec2 refTexCoord = SphereMap( normalize(normal), positionEye.xyz );
	vec3 texRefA = texture2D(TextureReflectionA, refTexCoord).xyz;
	vec3 texRefB = texture2D(TextureReflectionB, refTexCoord).xyz;
	vec3 texRef = mix(texRefB, texRefA, ReflectionParam.x);

	col = mix(col, texRef, reflectionsOn*ref_en*(0.1+ReflectionParam.y*0.5)); // 0.6 max 0.1 min
	float paint = clamp((1.0 - tex.a) * 255.0, 0.0, 1.0);
	float steel = 1.0 - clamp(abs(tex.a * 255.0 - 253.0), 0.0, 1.0);   // finish flags (above)
	float matte = 1.0 - clamp(abs(tex.a * 255.0 - 252.0), 0.0, 1.0);
	vec3 V = normalize(viewModel);
	float fresnel = pow(1.0 - max(dot(normal, V), 0.0), 5.0);
	col = mix(col, texRef/4.0, reflectionsOn*(1.0-ref_en)*(0.05 + ReflectionParam.z*0.3)
		* (1.0 + SHEEN_FRESNEL * paint * (1.0 - matte) * fresnel) * (1.0 + SHEEN_STEEL_REF * steel)); // 0.2 max (vanilla, before Fresnel)

	col = mix(col, texColorRust.xyz, texColorRust.a*TextureRustA);

	vec3 paintColor = TexturePainColor.xyz;

	float intensity = dommat4(texen1, MatBlood1Enables1) + dommat4(texen2, MatBlood1Enables2);
	float maskAlpha = step(0.5, dommat4(texen1, MatBlood2Enables1) + dommat4(texen2, MatBlood2Enables2));
	// Blood below damage on windows, ignore vehicle body.
	col = addBlood(texColorDamage2Overlay, texColorDamage1Overlay, intensity, maskAlpha * windowAlpha, lighting, TintColourNew, col);

	col = addDamage(col, texColorDamage1Shell, paintColor, lighting, TintColourNew, t2en*(1.0-noTintAlpha));
	col = mix(col, texColorDamage1Shell.xyz, texColorDamage1Shell.a*t2en*noTintAlpha);

	col = addDamage(col, texColorDamage2Shell, paintColor, lighting, TintColourNew, t3en*(1.0-noTintAlpha));
	col = mix(col, texColorDamage2Shell.xyz, texColorDamage2Shell.a*t3en*noTintAlpha);

	// Blood above damage on vehicle body, ignore windows.
	vec3 bloodless = col;
	col = addBlood(texColorDamage2Overlay, texColorDamage1Overlay, intensity, maskAlpha * (1.0 - windowAlpha), lighting, TintColourNew, col);
	float marked = clamp(length(col - bloodless) * 4.0, 0.0, 1.0);

	col = mix(col, vec3(0.2), t4en);

	col *= lighting * TintColourNew;

	// sheen: bare paint only (not lamps, removed parts, rust, damage shells, blood)
	paint *= (1.0 - noTintAlpha) * (1.0 - t4en) * (1.0 - texColorRust.a * TextureRustA) * (1.0 - marked)
		* (1.0 - texColorDamage1Shell.a * t2en) * (1.0 - texColorDamage2Shell.a * t3en);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 toCam = normalize(V - up * dot(V, up));
	vec3 sun = normalize(SHEEN_SUN.x * cross(up, toCam) + SHEEN_SUN.y * up + SHEEN_SUN.z * toCam);
	float lobe = mix(mix(SHEEN_POW, SHEEN_STEEL_POW, steel), SHEEN_MATTE_POW, matte);
	float gain = mix(mix(1.0, SHEEN_STEEL_GAIN, steel), SHEEN_MATTE_GAIN, matte);
	vec3 sheen = AmbientColour * SHEEN_SKY * pow(max(dot(normal, normalize(sun + V)), 0.0), lobe)
		+ lampSheen(Light0Direction, Light0Colour, normal, V, lobe) + lampSheen(Light1Direction, Light1Colour, normal, V, lobe)
		+ lampSheen(Light2Direction, Light2Colour, normal, V, lobe) + lampSheen(Light3Direction, Light3Colour, normal, V, lobe)
		+ lampSheen(Light4Direction, Light4Colour, normal, V, lobe);
	col += sheen * gain * TintColourNew * paint * ReflectionParam.z / 0.3;

	// Do this after ambient lighting so active headlights and taillights aren't dimmed.
	col = mix(col, texColorLights.xyz, texColorLights.a*t1en);

	col = colorDebug(col, texen1, texen2, windowAlpha, frontAlpha, tailAlpha, noTintAlpha, texColorMask);

	gl_FragColor = vec4(col, TexturePainColor.a);
}
