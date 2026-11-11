"""Model Y L source prep, run once before convert.py (CAR=model_yl): BloxBloger's "2025 Tesla Model Y" (the standard
car, Sketchfab, CC BY-NC 4.0; CREDITS.md) -> the six-seat long-wheelbase Model Y L at the owner's manual's size
(temp/plan-yl-1111 specs.md: length 4,969 without the plate bracket, width 1,920 without mirrors, height 1,668,
wheelbase 3,040, front overhang 889, rear 1,040; tyres 255/45 R19 front, 275/45 R19 rear), by one continuous
displacement field (no cuts: every source object and component keeps its triangles, so the config's CUT / GATE_COMPS
keys hold) plus one new object, the blade spoiler. Against the source (a Model Y 4,789 long, 1,944 wide over the rear
arch trims, front overhang 911, wheelbase 2,902, tyres 369 mm):
- width scaled about the centre line onto FIELD width;
- the bumper ahead of the front arch shortened onto the front overhang (FIELD nose);
- the front end lowered onto the official SIDE (FIELD nose_drop), the mirrors moved down and forward (FIELD mirror), the
  front splitter in its own lighter black (FIELD splitter);
- the rear wheel and its arch moved back onto the wheelbase, turned along itself (FIELD turn: a round arch stays round)
  so the rear door's rear edge, kept where the source has it (FIELD edge), meets it at about ten o'clock like the
  official SIDE render; the rear door's lower half, the sill and the quarter panel round the arch take the stretch: a
  harmonic (smoothest) field between those fixed parts (lower_grid), so the door's edge has no kinks; the arch's
  upper part grown a little (FIELD arch_grow);
- the doors onto the official SIDE through its fitted camera (FIELD fit: the front door's rear half, the B pillar,
  the rear door and its rear edge forward, the arch's front turned on with it; nothing behind the C pillar moves);
  the window line's black trim deepened (FIELD belt), the front handle and the fender's side camera lowered (sink);
- the tail moved back onto the rear overhang (FIELD tail, upper); the roof raised from the B pillar back (FIELD roof)
  and a little more ahead of the blade (crown);
- the roof rails pulled up to the glass roof's crown (FIELD rail), the rail's panel joint behind the rear door slid
  back along it (joint), the quarter window's tip moved back (quarter_tip);
- the source's duck lip moved forward (FIELD lip) and the spoiler built over it (blade(): a gloss blade on a body
  colour ducktail down to the tail lamps, its own object, convert.py puts it on the tailgate by GATE_OBJS);
- the tail lamps' lower half raised (FIELD lamp);
- the rear bumper's lower black cladding: its corner fins pulled in onto the bumper (FIELD fins);
- the tyres (dropped by convert.py, only measured for the wheel) scaled about their centres to FIELD tyre (front,
  rear), the rear axle raised by the difference (both tyres stand on the ground, the body stays level), and the car
  set on them (the lowest tyre point = ground 0).
Normals: each corner's by the field's Jacobian, inverse transpose (finite differences).
Frame here: the OBJ's own (the importer leaves its axes in each object's rotation): x along the car, front -x,
metres; y up, ground 0; z across. u = metres behind the nose, h = height. Check: scripts/blender/skf/side_iou.py
against yl_MTY87_PN01_SIDE.png; the numbers: .claude/skills/tesla-dev/references/models-model-yl.md.
"""
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_yl", "src", "source")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
src, out = (args + [os.path.join(SRC_DIR, "tesla.obj"), os.path.join(SRC_DIR, "model_yl.obj")][len(args):])[:2]

PLATES = ("Object_11", "Object_12")
TYRES = "Object005"
MIRRORS = ("Plane.046", "Plane.047", "Plane.048", "Plane.049", "Plane.050")
WHEEL = ("Object005", "Circle", "Cylinder", "Line0", "Object43")     # tyres, covers, rotors, calipers: moved whole
NOT_BODY = WHEEL + PLATES + MIRRORS + ("Interior", "Hyundai_KONA", "Plane.067")   # (convert.py DROP) for the width
# the field (metres; u behind the source's nose, h over the ground). Source landmarks: rear wheel centre u 3.812
# h 0.354, its arch trim radius 0.505 (the paint's opening 0.487); rear door u 2.57-3.70, its rear edge from the window
# corner (3.66, 1.18) down to the arch at (3.62, 0.81); belt h 1.06; roof glass ends u 3.74, tail u 4.79 (the lower
# cladding's corner fins; the bumper 4.73). Calibration knobs, fitted on side_iou and the official SIDE render
FIELD = dict(
    width=1.920,                    # without mirrors, over the rear arch trims (the widest part)
    tyre=(0.356, 0.365),            # tyre radius front 255/45 R19, rear 275/45 R19 (cars/model_yl.py TIRES: a wheel
    #                                 model each); the rear axle sits 9 mm higher on the body, the bottoms level
    front=0.889,                    # front overhang: the bumper ahead of u nose[1] shortened, ramp from nose[0]
    nose=(0.02, 0.40),
    # the front end sat high against the official SIDE (hood edge, light bar 40-45 mm, lower lamp slot 30 mm, nose's
    # bottom 15 mm, front arch top 25 mm; the sill and the belt match): down d[0] + d[1] x s(h over h), fading out over
    # u (the windscreen's foot stays)
    nose_drop=dict(u=(0.75, 1.20), h=(0.30, 0.80), d=(0.016, 0.026)),
    # the front splitter (the lower cladding ahead of the front arches, source u < u, h < h) in its own material: the
    # official FRONT34 reads it as a lit grey lip under the near-black intake, the source's black ran on as one band
    splitter=dict(objs=("Plane.021",), u=0.37, h=0.33, mat="splitter_black"),
    # the mirror (cap, arm, glass ring, glass): forward, down onto the official SIDE's (it sat 31 mm high, 12 mm back),
    # x s(|z| over z): the arm's foot on the door (and the sail) stays, the arm shears, the head moves whole; and
    # squeezed lengthwise to sx[1] behind source u sx[0] (the cap's front): its rear edge sat 1-3 px behind the
    # official SIDE's through the fitted camera (PPSW 1, PN01 2-3), its front on it; and the cap / black base border
    # tilted up rearward by tilt["d"] per metre behind sx[0] (a tent over h: 0 at the base's bottom and the cap's top,
    # all of it at the border; the official's border climbs 3 px to the rear, the source's was level, so its cap read
    # long under the glass)
    mirror=dict(objs=("Plane.046", "Plane.048", "Plane.049", "Plane.050"), d=(-0.012, -0.030), z=(0.78, 0.86),
                sx=(1.586, 0.975), tilt=dict(h=(1.050, 1.095, 1.216), d=0.053)),
    wheelbase=3.040,
    wheel=(0.354, 0.505),           # rear arch centre h (u: the tyres'), the trim's outer radius: moved whole inside
    # the rear arch trim 3-5 px low all round on the official SIDE through the fitted camera (5-7 px on its flanks):
    # inside the disc, points past r[0] out by d (smoothstep to r[1]; the liner's foot and the wheel stay), all of it
    # within a[0] deg of the top, none past a[1] (grown lower down, the trim's feet set the body's lowest point lower
    # and the bumper's corner behind the arch slid off its cladding: daylight in the side view)
    arch_grow=(0.40, 0.48, 0.016, (55.0, 85.0)),
    turn=(-23.3, -9.5, 110.0),      # inside: a point at angle phi (deg from the top, + rearward) turned to phi + d,
    #                                 d = turn[1] at turn[0] (the door's corner), 0 past +-turn[2]
    door=(2.75, 3.45, 0.030),       # everything (all h) behind the rear door's front ramps door[2] back (the doors
    #                                 themselves then come forward again by `fit`)
    edge=((3.642, 0.870), (3.658, 0.930), (3.673, 0.985), (3.688, 1.041), (3.695, 1.071), (3.704, 1.100)),
    edge_du=(0.020, 1.00, 1.06),    # rear door's rear edge (source vertices): the lower field there edge_du[0] under h
    #                                 edge_du[1], 0 over edge_du[2] (with `door`: upright like the official's)
    fixed=2.75,                     # the lower field is 0 ahead of this u (the rear door's front edge, sill)
    # the doors onto the official SIDE through the fitted camera (work/camfit; the `door` / `edge` shifts came off the
    # de-perspective overlay, which read the near side's features long): forward by `lo` (source u, metres) under the
    # belt, then each `over` level ((h over which it takes over, knots)): the rear edge's belt kink (its top sat back,
    # the seam under it leaning), the window corner and the window bar, the window tops and the roof (back to 0 at the
    # rear glass's frame: the roof's few big triangles tilt with their front ends, lowering the 3rd row's headroom); 0
    # from the last knot back (the C pillar, the quarter window, the arch's rear half and the tail keep their places).
    # Official SIDE same camera, before: B pillar seam 4 px (16 mm) back, front handle 5, the B pillar's trim 3, rear
    # handle 9-10, window bar 5, rear edge 10-13. Round the rear arch (fit_grid): the arch's front turned on by `turn`
    # degrees at the door's corner (turn[0], tapering to 0 at -turn[2] and at the arch's top), so the edge still meets
    # it at ten o'clock (the official's meets it 16 px lower forward), and a harmonic field in a band `free` round the
    # arch and behind the edge (the quarter) between them
    fit=dict(lo=((1.80, 0.0), (2.30, -0.020), (2.62, -0.017), (3.35, -0.039), (3.56, -0.040), (3.70, -0.043),
                 (3.885, 0.0)),
             over=(((1.04, 1.10), ((1.80, 0.0), (2.30, -0.020), (2.62, -0.017), (3.35, -0.039), (3.56, -0.040),
                                   (3.70, -0.054), (3.885, 0.0))),
                   ((1.10, 1.16), ((1.80, 0.0), (2.30, -0.014), (2.84, -0.014), (3.58, -0.020), (3.68, -0.028),
                                   (3.78, 0.0), (3.885, 0.0))),
                   ((1.22, 1.32), ((1.80, 0.0), (2.30, -0.014), (2.84, -0.014), (3.58, -0.020), (3.62, -0.023),
                                   (3.72, 0.0), (3.885, 0.0)))),
             turn=-9.5, free=0.10),
    tail=(4.70, 0.95, 0.116),      # behind u tail[0], under h tail[1]: the bumper moves whole, tail[2] more than the
    #                                 arch (rear overhang 1,040)
    band=(0.86, 1.06),              # lower field below h band[0], upper shift above band[1]
    upper=(3.62, 4.20, 0.184),      # upper shift (over `door`) ramps over u (window bar -> behind the quarter window's
                                    # tip: the Y L's quarter window is that much longer than the Y's; on to the tail
                                    # lamps a plain shift)
    # the quarter window's lower edge brought down to the official SIDE's (it sits 2.5-6.5 cm high after the stretch):
    # down d x a bump over source u (up over u[0..1], down over u[2..3]) x a tent over the height after the other
    # terms (up over h[0..1], down over h[2..3]: the belt and the roof rail stay) x the side (|z| over z: the rear
    # glass, |z| <= 0.55, stays)
    quarter=dict(u=(3.64, 3.85, 4.02, 4.14), h=(1.12, 1.30, 1.40, 1.56), z=(0.555, 0.605), d=0.065),
    # its tip (source (4.046, 1.345), the frame's) 70 mm short and 20 mm low on the official SIDE through the fitted
    # camera (the earlier de-perspective overlay scaled the official about the image centre, so it read the near side's
    # tip that much forward): moved d x a bump (smoothstep in the ellipse's radius: u ahead / behind, h) x the side
    quarter_tip=dict(c=(4.046, 1.345), u=(0.35, 0.25), h=0.14, z=(0.555, 0.605), d=(0.070, 0.020)),
    roof=((2.30, 0.0), (2.55, 0.008), (2.90, 0.031), (3.30, 0.067), (3.66, 0.097), (3.95, 0.112), (4.20, 0.100),
          (4.40, 0.085), (4.60, 0.050), (4.80, 0.035)),   # raise at the top (source u)
    roof_h=1.00,                    # the raise fades to 0 at this height (under the belt): top(u) gets all of it
    # the roof rails up to the glass: the source's glass crowns 30-35 mm over its body-colour rails, so the official
    # FRONT34 / REAR34 (cameras at roof height) see a rail band 25-30 mm taller and no glass over it (SIDE: the band
    # over the side windows 11-15 px, the source's 7-9). Each (u, |z|) column moved up whole by k of the rail top's way
    # to the crown (top(u) + roof; the rail top: the upper envelope at |z| >= z[1], after the roof raise) x a bump over
    # u (the glass roof's length) x the band (h over the rail top + h[0]..h[1]: the side windows and their frame stay)
    # x the side (|z| over z: the glass's middle stays). Whole, not k of each point's own way up: that squashed the
    # rail's 10 mm inner lip over the glass's edge to 6, and convert.py's seal strip behind the lip's flange (SEAL,
    # ~10 mm deep) stood out over the far rail as a black line with daylight under it
    rail=dict(u=(2.15, 2.40, 3.70, 3.95), h=(-0.030, -0.012), z=(0.30, 0.55), k=0.8),
    # the roof rail's panel joint behind the rear door (a crack inside the body's paint at source u 3.705-3.72; the rear
    # door's frame ends at the window bar, the rail is body): the official SIDE (fitted camera) has it 23 px (top) to
    # 34 px (outer foot) further back, so leaning back. The paint (`objs`) in the rail band slid back along the rail
    # before the field (joint()): d (outer foot, top) x a bump over u, each point keeping its place across the band
    # between the rail's outer lower edge (`low`, (u, h) knots) and its top (rprof) (the frames, the glass, the window
    # tip stay; the 3rd row sits under the glass, |z| < z[0])
    joint=dict(objs=("Plane",), u=(3.40, 3.70, 3.72, 3.98), d=(0.135, 0.045), z=(0.50, 0.53), tau=(-0.15, 0.0),
               low=((3.34, 1.524), (3.52, 1.490), (3.705, 1.4455), (3.95, 1.375), (4.04, 1.342), (4.11, 1.320),
                    (4.17, 1.291), (4.24, 1.262), (4.29, 1.235))),
    # the window line's black trim: on the official SIDE (fitted camera) the black under the side glass reaches 6-7 px
    # (25-28 mm) lower than here, along both doors and behind the mirror (the source's trim lip shows 10-12 mm). Its
    # seam with the paint (source h per u, `seam` knots) down by d (u knots) x a tent over h round the seam (h[0]
    # under it to 0: the shoulder squeezed; h[1] over it to 0: the glass's visible foot stays) x the side (|z| over
    # z: the cowl and the windscreen stay)
    belt=dict(seam=((1.40, 1.040), (1.60, 1.051), (2.70, 1.111), (3.10, 1.137), (3.40, 1.157), (3.60, 1.172)),
              h=(-0.060, 0.024), z=(0.70, 0.74),
              d=((1.45, 0.0), (1.60, 0.019), (2.00, 0.022), (2.30, 0.019), (3.40, 0.019), (3.62, 0.022), (3.74, 0.0))),
    # parts sitting high on the official SIDE: each down d, whole over u[1]..u[2] and within h[1] of h[0], to 0 by
    # u[0], u[3] and h[2] off, x the side (|z| over z): the front door's handle (source u 2.30-2.55, h 0.95-0.99; the
    # rear one within 1 px) 5 px (20 mm), the fender's side camera (Plane.030, u 1.22-1.37, h 0.82-0.87) 7 px
    sink=(dict(u=(2.14, 2.27, 2.58, 2.71), h=(0.972, 0.030, 0.080), z=(0.60, 0.70), d=0.022),
          dict(u=(1.08, 1.20, 1.38, 1.50), h=(0.843, 0.040, 0.090), z=(0.60, 0.70), d=0.027)),
    # the roof's tail into the blade dipped 3-8 px (12-32 mm) under the official SIDE's line (final u 4.52-4.77), the
    # refit REAR34 2-4 px, FRONT34 5-10 px over: the points within h of the crown (top(u)) up d x a bump over u, a
    # compromise (SIDE 8 -> 5 px, REAR34 within 2). It ends ahead of the blade's root (raised under the root, the
    # blade's top showed through the rear glass as a dark sliver); a deep band, so the glass and its frame rise as one
    crown=dict(u=(4.20, 4.36, 4.44, 4.52), h=(-0.40, -0.30), d=0.020),
    lip=(4.60, 4.73, 1.15, 1.22, 0.030),   # the duck lip (the tailgate's top edge under the blade) back to the Y L's:
    #                                 points behind u lip[0]..[1] and over h lip[2]..[3] (source) lip[4] forward. (The
    #                                 tailgate's top stays at the source's height: lowered 70 mm, fitted through the
    #                                 old cameras, the glass's end sat 6-8 px under the camfit REAR34's, 7-15 px SIDE)
    lamp=(4.20, 4.32, 0.90, 0.97, 1.08, 0.025),   # the tail lamps' lower half up onto the Y L's (official SIDE: the
    #                                 lamp's foot 16-28 mm higher; REAR34's corner lamps sit ~45 mm low top and bottom
    #                                 alike, its camera pitch is less sure: SIDE wins): behind u lamp[0]..[1], h
    #                                 lamp[2]..[4] (source) up by lamp[5] at h lamp[3] (their bottom), the shelf kept
    # the spoiler (blade()): a gloss black blade over a body colour ducktail (official REAR34 / SIDE in all six
    # colours: the blade's trailing face and top are the same black in each, the face under it down to the tail lamps
    # takes the paint), from the rear glass frame's end (BLADE_ROOT, final frame) to the trailing edge. Final u, h
    # (metres), z across: half span; the trailing edge's u, its top and its bottom h, each (middle, x z^2); the chord
    # at most `chord` (the root follows the glass's end, which curves forward much more than the trailing edge); the
    # root's thickness over the body (the top goes on from the glass, no step: official REAR34 reads glass and blade
    # top as one gloss); past |z| droop[0] the trailing edge drops droop[1] to the tips and its face thins to droop[2]
    # (official REAR34: a thin black line running down onto the near sail), the top past |z| paint_z in body colour
    # (the ends' stems run up into it there: PN01 dark grey, PPSW white); the top's strips split at `sheen` (fractions
    # of the chord: BLADE_TOP shades, front to back); the ducktail's rear face from the trailing edge's bottom down to
    # its foot at h `foot` (the tail lamps' top, found from behind, at most `reach` ahead of the trailing edge: the
    # ends overhang the narrowing tail) in `rows` strips, hollowed `concave` forward at mid height. Trailing edge to
    # the tips as f = (1 - |z / span| ^ tip[0]) ^ tip[1] (rounded in plan); stations each side. Fitted through the
    # camfit cameras: REAR34 trailing face y 391-406 in the middle (official 391-407), its bottom 410-412 at x
    # 1286-1334 (official 409-415), top silhouette within 4 px; SIDE tip x 1546 at y 392 (official 1550), the roof
    # line within 2 px from x 1516. From the game's 30 deg camera the trailing edge, 4 cm lower than before, hides
    # the light bar's middle third (the official's would too: it overhangs the lamps 12-15 cm)
    blade=dict(span=0.69, te=(4.95, -0.18), chord=0.21, top=(1.302, -0.04), bot=(1.249, -0.06), root=0.010,
               droop=(0.58, 0.05, 0.3), paint_z=0.58, sheen=(0.55, 0.85), foot=1.150, reach=0.08, concave=0.030,
               rows=4, tip=(30.0, 0.5), n=12),
    # dark strips inside door gaps that one sees through from the side (blackout()): the rear door's rear edge where
    # it runs over the quarter's shoulder, above the belt (the two panels end in return flanges 3 mm apart, so one sees
    # between them into the cabin; convert.py's panel-gap strips lie along the flanges, edge-on), and the lower ends
    # of the B pillar's gap and the front door's front gap, under the cabin's floor. Source (u, h, |z|) of each gap's
    # outer edge; a strip `inset` inboard of it, `half` either side of it along u
    blackout=dict(lines=(((3.636, 1.215, 0.728), (3.6456, 1.1817, 0.7359), (3.6852, 1.145, 0.7538),
                          (3.7045, 1.0998, 0.8549), (3.6952, 1.0712, 0.8702), (3.6878, 1.0412, 0.8849),
                          (3.6729, 0.9851, 0.9123)),
                         ((2.5735, 0.578, 0.910), (2.5728, 0.4884, 0.925), (2.5813, 0.4183, 0.904),
                          (2.5902, 0.3491, 0.882), (2.598, 0.3006, 0.874), (2.598, 0.27, 0.870)),
                         ((1.4025, 0.5456, 0.941), (1.4182, 0.4002, 0.928), (1.4235, 0.3604, 0.919),
                          (1.429, 0.3204, 0.911), (1.4343, 0.2785, 0.902), (1.436, 0.25, 0.898))),
                  inset=0.04, half=0.025),
    # the rear bumper's lower cladding's corner lip stuck 5-10 cm out past the bumper in the side view (a spike): its
    # points behind u zone[0], h zone[1]..zone[2] held at most `margin` behind the reference parts' rearmost point
    # within `near` (h, z) of them (source frame, before the field). (The diffuser's lip, Plane.026, the other spike
    # and the teeth under the bumper seen low from behind: cars/model_yl.py DROP)
    fins=dict(objs=("Plane.021",), ref=("Plane", "Plane.022"), zone=(4.40, 0.15, 0.70), near=(0.03, 0.05),
              margin=0.01),
    # lit trim on the bumper's black (official REAR34: the licence plate recess's raised frame and the diffuser lip's
    # highlight, a lighter grey than the cladding; the source's bumper is one smooth black face): strips `w` wide
    # along polylines of final (h, z) metres (mirrored to -z), laid on `objs` from behind, `off` out, material `mat`
    trim=dict(objs=("Plane.021", "Plane.022"), w=0.012, off=0.003, mat="bumper_lit", lines=(
        ((0.43, 0.0), (0.43, 0.16), (0.55, 0.16), (0.55, 0.0)),                       # the plate recess's frame
        ((0.395, 0.0), (0.395, 0.18), (0.385, 0.34), (0.36, 0.50), (0.33, 0.60), (0.30, 0.68)))),   # the lip
    # holes in the source's paint filled with triangles on its own vertices (source (u, h, |z|) of each corner, both
    # sides): the front bumper's corner, where its rear edge and the fender's front return flange part 2-3 cm up to
    # h 0.55 (the bumper-fender seam): convert.py's seal strips and the panels' backs filled that gap dark, a blot
    # and a line on the official FRONT34's smooth corner. And strips (two chains, a quad per step): the source's
    # liftgate outline up the C pillar from the quarter window's tip to the blade's corner, a 0.5-1.5 mm crack left
    # inside the body (the gate's cut runs behind it): at the closest zoom the seal behind it was a dotted line where
    # the official REAR34 has a smooth shoulder
    patch=dict(objs=("Plane",), tris=(((0.3197, 0.3801, 0.8619), (0.3397, 0.3901, 0.8395), (0.3232, 0.4212, 0.8722)),
                                      ((0.3232, 0.4212, 0.8722), (0.3397, 0.3901, 0.8395), (0.3690, 0.5291, 0.8666)),
                                      ((0.3232, 0.4212, 0.8722), (0.3690, 0.5291, 0.8666), (0.3651, 0.5607, 0.8866)),
                                      ((0.3651, 0.5607, 0.8866), (0.3690, 0.5291, 0.8666), (0.3745, 0.5502, 0.8689))),
               strips=((((4.0427, 1.3427, 0.6179), (4.1082, 1.3196, 0.6186), (4.1699, 1.2907, 0.6222),
                         (4.2365, 1.2622, 0.6288), (4.2808, 1.2361, 0.6356), (4.2850, 1.2333, 0.6365)),
                        ((4.0432, 1.3423, 0.6183), (4.1090, 1.3199, 0.6185), (4.1701, 1.2917, 0.6218),
                         (4.2403, 1.2617, 0.6283), (4.2838, 1.2353, 0.6357), (4.2850, 1.2347, 0.6358))),)),
)
GRID = (2.40, 5.20, -0.10, 1.10, 0.01)   # lower_grid: u0, u1, h0, h1, step
BLADE_ROOT = "Plane.006"           # the rear glass frame: the blade's leading edge along its rear end
BLADE_MAT = "spoiler_black"        # cars/model_yl.py MAT_RGB: the trailing face
BLADE_TOP = ("spoiler_top", "spoiler_mid", "spoiler_sheen")   # the top's strips, front to back (MAT_RGB: the gloss
#                                    top reads as the glass it goes on from, lighter towards the trailing edge's crest)
BLADE_PAINT = "Material_#2125765635"   # the body paint (cars/model_yl.py PAINT_MAT): the ducktail under the blade
BLADE_HULL = ("Plane", "Plane.006", "Plane.011", "Plane.034", "Plane.041", "Plane.043")   # what blade() sits on
BLACKOUT_MAT = "black_base"        # the source's black trim


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def top_profile(a, b):
    """Source top height per u: the upper envelope of the edges (a, b: their ends, (u, h) rows) in 2 cm bins, each
    edge sampled every cm (the roof is a few big triangles: its vertices alone left most bins on the cabin below),
    smoothed over 10 cm."""
    n = np.maximum(np.ceil(np.abs(b[:, 0] - a[:, 0]) / 0.01).astype(int), 1)
    k = np.repeat(np.arange(len(a)), n + 1)
    t = np.concatenate([np.arange(m + 1) / m for m in n])
    p = a[k] + (b[k] - a[k]) * t[:, None]
    edges = np.arange(-0.05, p[:, 0].max() + 0.07, 0.02)
    i = np.clip(np.digitize(p[:, 0], edges) - 1, 0, len(edges) - 2)
    top = np.full(len(edges) - 1, -np.inf)
    np.maximum.at(top, i, p[:, 1])
    ok = np.isfinite(top)
    top = np.interp(np.arange(len(top)), np.flatnonzero(ok), top[ok])
    top = np.convolve(np.pad(top, 2, mode="edge"), np.ones(5) / 5, "valid")
    return edges[:-1] + 0.01, top


def door(u):
    f = FIELD["door"]
    return f[2] * s(u, f[0], f[1])


def upper(u):
    f = FIELD["upper"]
    return f[2] * s(u, f[0], f[1])


def turn(u, h, uw, rear):
    """(du, dh) of the arch disc: moved `rear` back, a point at angle phi turned to phi + d(phi) about the centre,
    and out by arch_grow."""
    hw = FIELD["wheel"][0]
    pc, pd, pe = FIELD["turn"]
    g0, g1, gd, (ga, gb) = FIELD["arch_grow"]
    du0, dh0 = u - uw, h - hw
    r = np.hypot(du0, dh0)
    phi = np.degrees(np.arctan2(du0, dh0))
    d = np.where(phi < pc, pd * s(phi, -pe, pc), pd * (1 - s(phi, pc, pe)))
    p2 = np.radians(phi + d)
    r2 = r + gd * s(r, g0, g1) * (1 - s(np.abs(phi), ga, gb))
    return rear + r2 * np.sin(p2) - du0, r2 * np.cos(p2) - dh0


def harmonic(fs, fix):
    """Each field in fs (grid arrays, changed in place) harmonic between its `fix` nodes and the grid's top row and
    ends; the ground row free (mirrored). Red-black SOR."""
    red = (np.add.outer(np.arange(fix.shape[0]), np.arange(fix.shape[1])) % 2 == 0)
    for f in fs:
        for it in range(4000):
            last = f.copy() if it % 200 == 0 else None
            for colour in (red, ~red):
                nb = np.zeros_like(f)
                nb[1:-1, 1:-1] = (f[:-2, 1:-1] + f[2:, 1:-1] + f[1:-1, :-2] + f[1:-1, 2:]) / 4
                nb[0, 1:-1] = (2 * f[1, 1:-1] + f[0, :-2] + f[0, 2:]) / 4   # the ground row: mirrored (no flux)
                upd = colour & ~fix
                upd[-1] = upd[:, 0] = upd[:, -1] = False
                f[upd] += 1.9 * (nb[upd] - f[upd])
            if last is not None and np.abs(f - last).max() < 1e-7:
                break


def lower_grid(uw, rear):
    """The field under the band on a grid: harmonic (du, dh) between the fixed parts (Dirichlet): nothing ahead of
    `fixed`, the arch disc (turn()), the rear door's edge (0), the bumper (rear + tail[2]), the band's top (upper());
    the ground row free (mirrored)."""
    u0, u1, h0, h1, st = GRID
    U, H = np.meshgrid(np.arange(u0, u1 + st / 2, st), np.arange(h0, h1 + st / 2, st))
    fu, fh = np.zeros_like(U), np.zeros_like(U)
    fix = U <= FIELD["fixed"]
    dd = door(U)                                           # (field() adds it on top)
    t0, t1, t2 = FIELD["tail"]
    m = (U >= t0) & (H <= t1)
    fu[m], fix = (rear + t2 - dd)[m], fix | m
    m = np.hypot(U - uw, H - FIELD["wheel"][0]) <= FIELD["wheel"][1]
    fu[m], fh[m] = turn(U[m], H[m], uw, rear)
    fu[m] -= dd[m]
    fix |= m
    e, (ev, e0, e1) = np.array(FIELD["edge"]), FIELD["edge_du"]
    for (ua, ha), (ub, hb) in zip(e[:-1], e[1:]):          # the edge's nodes: within a cell of its segments
        t = np.clip(((U - ua) * (ub - ua) + (H - ha) * (hb - ha)) / ((ub - ua) ** 2 + (hb - ha) ** 2), 0, 1)
        m = np.hypot(U - ua - t * (ub - ua), H - ha - t * (hb - ha)) <= st * 0.75
        fu[m], fh[m], fix = ev * (1 - s(H[m], e0, e1)), 0, fix | m
    fu[-1], fh[-1] = upper(U[-1]), 0
    fix[-1] = True
    fix[:, -1] = True
    fu[:, -1] = np.where(H[:, -1] <= t1, rear + t2 - dd[:, -1], upper(U[:, -1]))
    harmonic((fu, fh), fix)
    return U[0], H[:, 0], fu, fh


def smooth(u, knots):
    """Through the knots ((u, value) rows, u ascending) by a smoothstep each span; flat past the ends (exactly the
    last value behind the last knot)."""
    x, v = np.array(knots).T
    i = np.clip(np.searchsorted(x, u) - 1, 0, len(x) - 2)
    return v[i] + (v[i + 1] - v[i]) * s(u, x[i], x[i + 1])


def fit_du(u, h):
    """The FIELD fit shift (du, rearward) away from the rear arch: `lo`, each `over` level taking over above it."""
    f = FIELD["fit"]
    d = smooth(u, f["lo"])
    for hh, k in f["over"]:
        d = d + (smooth(u, k) - d) * s(h, *hh)
    return d


def fit_grid(uw):
    """FIELD fit on the lower_grid grid: fit_du() held everywhere but in the arch disc (turned on by fit turn, on top
    of turn()) and the `free` band round it and behind the rear door's edge (the quarter), harmonic there; (du, dh).
    Nodes from the last knot back hold 0."""
    f = FIELD["fit"]
    u0, u1, h0, h1, st = GRID
    U, H = np.meshgrid(np.arange(u0, u1 + st / 2, st), np.arange(h0, h1 + st / 2, st))
    fu, fh = fit_du(U, H), np.zeros_like(U)
    hw, rw = FIELD["wheel"]
    pc, pd, pe = FIELD["turn"]
    r = np.hypot(U - uw, H - hw)
    phi = np.degrees(np.arctan2(U - uw, H - hw))
    d = np.where(phi < pc, pd * s(phi, -pe, pc), pd * (1 - s(phi, pc, pe)))      # turn()'s
    d2 = f["turn"] * np.where(phi < pc, s(phi, -pe, pc), 1 - s(phi, pc, 0))       # 0 from the arch's top back
    a, b = np.radians(phi + d), np.radians(phi + d + d2)
    disc = r <= rw
    fu[disc], fh[disc] = (r * (np.sin(b) - np.sin(a)))[disc], (r * (np.cos(b) - np.cos(a)))[disc]
    e = np.array(FIELD["edge"])
    free = ~disc & (U < f["lo"][-1][0]) & ((r < rw + f["free"]) | (U > np.interp(H, e[:, 1], e[:, 0])))
    harmonic((fu, fh), ~free)
    return U[0], H[:, 0], fu, fh


def with_fit(fld, gf):
    """fld (u, h, az) -> (du, dh) plus FIELD fit: its grid gf (fit_grid()) where that reaches, fit_du() past it."""
    def f(u, h, az):
        du, dz = fld(u, h, az)
        fu, fh = sample(gf, u, h)
        on = (u >= gf[0][0]) & (h <= gf[1][-1])
        return du + np.where(on, fu, fit_du(u, h)), dz + np.where(on, fh, 0)
    return f


def sample(g, u, h):
    """Bilinear sample of a lower_grid field (us, hs, fu, fh) at points (u, h), clamped to the grid."""
    us, hs, fu, fh = g
    st = us[1] - us[0]
    x = np.clip((u - us[0]) / st, 0, len(us) - 1.000001)
    y = np.clip((h - hs[0]) / st, 0, len(hs) - 1.000001)
    i, j = x.astype(int), y.astype(int)
    a, b = x - i, y - j
    out = []
    for f in (fu, fh):
        out.append(f[j, i] * (1 - a) * (1 - b) + f[j, i + 1] * a * (1 - b) + f[j + 1, i] * (1 - a) * b
                   + f[j + 1, i + 1] * a * b)
    return out


def field(u, h, az, prof, g, nose, rprof):
    """(du, dh): rearward and upward displacement of points (u, h, |z - zc| = az)."""
    f = FIELD
    lu, lh = sample(g, u, h)
    w = s(h, *f["band"])
    l0, l1, h0, h1, ld = f["lip"]
    du = nose * (1 - s(u, *f["nose"])) + door(u) + lu * (1 - w) + upper(u) * w - ld * s(u, l0, l1) * s(h, h0, h1)
    ru, rz = np.array(f["roof"]).T
    top = np.interp(u, *prof)
    nd = f["nose_drop"]
    m0, m1, mh0, mhm, mh1, md = f["lamp"]
    dz = lh * (1 - w) + np.interp(u, ru, rz) * np.clip((h - f["roof_h"]) / np.maximum(top - f["roof_h"], 0.05), 0, 1) \
        - (nd["d"][0] + nd["d"][1] * s(h, *nd["h"])) * (1 - s(u, *nd["u"])) \
        + md * s(u, m0, m1) * s(h, mh0, mhm) * (1 - s(h, mhm, mh1))
    q = f["quarter"]
    h1 = h + dz
    dz = dz - q["d"] * s(u, *q["u"][:2]) * (1 - s(u, *q["u"][2:])) * s(h1, *q["h"][:2]) * (1 - s(h1, *q["h"][2:])) \
        * s(az, *q["z"])
    qt = f["quarter_tip"]
    qb = s(np.hypot((u - qt["c"][0]) / np.where(u < qt["c"][0], *qt["u"]), (h - qt["c"][1]) / qt["h"]), 1, 0) \
        * s(az, *qt["z"])
    du, dz = du + qt["d"][0] * qb, dz + qt["d"][1] * qb
    r = f["rail"]
    t = top + np.interp(u, ru, rz)                        # the crown after the roof raise
    rt = np.interp(u, *rprof)
    rt = rt + np.interp(u, ru, rz) * np.clip((rt - f["roof_h"]) / np.maximum(top - f["roof_h"], 0.05), 0, 1)
    dz = dz + r["k"] * (t - rt) * s(u, *r["u"][:2]) * (1 - s(u, *r["u"][2:])) \
        * s(h + dz, rt + r["h"][0], rt + r["h"][1]) * s(az, *r["z"])
    b = f["belt"]
    x = h - np.interp(u, *np.array(b["seam"]).T)
    dz = dz - smooth(u, b["d"]) * np.where(x < 0, s(x, b["h"][0], 0), 1 - s(x, 0, b["h"][1])) * s(az, *b["z"])
    for k in f["sink"]:
        dz = dz - k["d"] * s(u, *k["u"][:2]) * (1 - s(u, *k["u"][2:])) \
            * (1 - s(np.abs(h - k["h"][0]), *k["h"][1:])) * s(az, *k["z"])
    c = f["crown"]
    dz = dz + c["d"] * s(u, *c["u"][:2]) * (1 - s(u, *c["u"][2:])) * s(h, top + c["h"][0], top + c["h"][1])
    return du, dz


def joint(u, h, az, rprof):
    """FIELD joint: (u, h) of the rail band's paint slid back along the rail (source frame, before the field)."""
    j = FIELD["joint"]
    lo = np.array(j["low"]).T
    lw, tp = np.interp(u, *lo), np.interp(u, *rprof)
    tau = (h - lw) / np.maximum(tp - lw, 0.01)
    w = s(u, *j["u"][:2]) * (1 - s(u, *j["u"][2:])) * s(tau, *j["tau"]) * s(az, *j["z"])
    u2 = u + w * (j["d"][0] + (j["d"][1] - j["d"][0]) * np.clip(tau, 0, 1))
    lw2, tp2 = np.interp(u2, *lo), np.interp(u2, *rprof)
    return u2, h + (lw2 - lw) + tau * ((tp2 - lw2) - (tp - lw))     # exactly h where w is 0


def base(o):
    return o.name.split("_Mesh")[0]


def fins(co, nose):
    """Pull the FIELD fins points in (co: object -> OBJ points, changed in place). Returns how many moved."""
    f = FIELD["fins"]
    u0, h0, h1 = f["zone"]
    u0 += nose
    ref = np.concatenate([c for o, c in co.items() if base(o) in f["ref"]])
    ref = ref[ref[:, 0] > u0 - 0.2]
    n = 0
    for o, c in co.items():
        if base(o) not in f["objs"]:
            continue
        for i in np.flatnonzero((c[:, 0] > u0) & (c[:, 1] > h0) & (c[:, 1] < h1)):
            m = (np.abs(ref[:, 1] - c[i, 1]) < f["near"][0]) & (np.abs(ref[:, 2] - c[i, 2]) < f["near"][1])
            if m.any() and c[i, 0] > ref[m, 0].max() + f["margin"]:
                c[i, 0] = ref[m, 0].max() + f["margin"]
                n += 1
    return n


def patch(obs, nose, zc):
    """Add the FIELD patch triangles (tris, and two triangles per step between each strip's two chains) to their
    objects (the vertices exist; their normals: the mesh's own), each facing like its corners' normals. Returns how
    many."""
    import bmesh
    f, n = FIELD["patch"], 0
    tris = list(f["tris"])
    for a, b in f["strips"]:
        for i in range(len(a) - 1):
            tris += [(a[i], a[i + 1], b[i + 1]), (a[i], b[i + 1], b[i])]
    for o in obs:
        if base(o) not in f["objs"]:
            continue
        me = o.data
        p = np.array([v.co[:] for v in me.vertices])
        vn = np.array([v.normal[:] for v in me.vertices])
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        ref = bm.faces[0]
        for tri in tris:
            for side in (1, -1):
                q = np.array([(nose + u, h, zc + side * az) for u, h, az in tri])
                d = np.linalg.norm(p[None] - q[:, None], axis=2)
                i = d.argmin(1)
                assert d[np.arange(3), i].max() < 1e-3, ("patch corner not found", o.name, tri)
                if np.cross(p[i[1]] - p[i[0]], p[i[2]] - p[i[0]]) @ vn[i].sum(0) < 0:
                    i = i[[0, 2, 1]]
                face = bm.faces.new([bm.verts[k] for k in i], ref)     # ref: its material, smooth flag
                face.smooth = True
                n += 1
        bm.to_mesh(me)
        bm.free()
    return n


def trim(nose, zc, bvh):
    """The FIELD trim strips, both sides (final frame, OBJ axes; bvh: its objs as prepped): (vertices, faces)."""
    from mathutils import Vector
    t = FIELD["trim"]
    V, F = [], []
    for line in t["lines"]:
        for side in (-1, 1):
            q = np.array(line) * (1, side)
            for a0, b0 in zip(q[:-1], q[1:]):
                n = (np.array((-(b0 - a0)[1], (b0 - a0)[0])) / np.hypot(*(b0 - a0))) * t["w"] / 2   # across, (h, z)
                k = int(np.ceil(np.hypot(*(b0 - a0)) / 0.02))   # 2 cm pieces: the bumper bulged over longer ones
                s_ = a0 + (b0 - a0) * np.arange(k + 1)[:, None] / k
                for a, b in zip(s_[:-1], s_[1:]):
                    o = len(V)
                    for c in (a - n, a + n, b + n, b - n):
                        p = bvh.ray_cast(Vector((nose + 6.0, c[0], zc + c[1])), Vector((-1, 0, 0)))[0]
                        if p is None:
                            raise SystemExit(f"trim: no bumper behind (h, z) {np.round(c, 3).tolist()}")
                        V.append((p.x + t["off"], c[0], p.z))
                    e = np.array(V[o:o + 3])
                    F.append((o, o + 1, o + 2, o + 3)[::1 if np.cross(e[1] - e[0], e[2] - e[0])[0] > 0 else -1])
    return np.array(V), F


def blackout(fld, wk, lift, nose, zc):
    """The strips inside the FIELD blackout gaps, both sides (final frame, OBJ axes): (vertices, faces)."""
    b = FIELD["blackout"]
    V, F = [], []
    for line in b["lines"]:
        p = np.array(line)
        for side in (-1, 1):
            o = len(V)
            for u, h, z in p:
                for du0 in (-b["half"], b["half"]):
                    du, dz = fld(np.array([u + du0]), np.array([h]), np.array([z]))
                    V.append((nose + u + du0 + du[0], h + dz[0] + lift, zc + side * (z - b["inset"]) * wk))
            for i in range(len(p) - 1):
                q = (o + 2 * i, o + 2 * i + 1, o + 2 * i + 3, o + 2 * i + 2)
                F.append(q if side > 0 else q[::-1])
    return np.array(V), F


def new_nose(new):
    return min(p2[:, 0].min() for o, (p2, n) in new.items() if not o.name.startswith(PLATES))


def blade(frame, nose, zc, bvh):
    """The spoiler's mesh (final frame, OBJ axes): stations across, a section each, a blade over a body colour
    ducktail. Root on the rear glass frame's end (frame: that object's points), a little into the body (bvh: the body as
    prepped); the blade's top on to the trailing edge in strips (BLADE_TOP, split at `sheen`), its blunt trailing face
    (BLADE_MAT); under it the ducktail's concave rear face in `rows` strips down to its foot on the tail lamps' top
    (found from behind, a little in), each row kept 6 mm behind the tailgate's own surface (with one row at mid height
    the tailgate's top lip poked through the strips below it: grey blotches in the lit renders); open at the bottom,
    inside the body. End caps. Returns (vertices, faces, material index per face: 0 BLADE_MAT, 1 BLADE_PAINT, 2..
    BLADE_TOP)."""
    from mathutils import Vector
    b = FIELD["blade"]
    u, h, z = frame[:, 0] - nose, frame[:, 1], frame[:, 2] - zc
    zs = b["span"] * np.linspace(-1, 1, 2 * b["n"] + 1)
    pts = []                                    # the frame's rear end across the glass, its bottom edge (the side
    h0 = h[(np.abs(z) < 0.05) & (u > 4.3)].min()   # pieces run up the C pillars): u as a quadratic in z
    for x in np.linspace(-0.5, 0.5, 21):
        m = (np.abs(z - x) < 0.04) & (u > 4.3) & (h > 1.1) & (h < h0 + 0.03)
        if m.any():
            k = np.flatnonzero(m)[np.argmax(u[m])]
            pts.append((z[k], u[k], h[k]))
    q = np.array(pts)
    te = b["te"][0] + b["te"][1] * zs ** 2
    ru = np.maximum(np.polyval(np.polyfit(q[:, 0] ** 2, q[:, 1], 1), zs ** 2) - 0.020, te - b["chord"])
    f = (1 - np.abs(zs / b["span"]) ** b["tip"][0]) ** b["tip"][1]     # the tips rounded in plan
    te = ru + (te - ru) * np.maximum(f, 0.15)
    dr = s(np.abs(zs), b["droop"][0], b["span"])     # the ends drooping onto the sail, thinner
    tt = b["top"][0] + b["top"][1] * zs ** 2 - b["droop"][1] * dr
    tb = tt - (tt + b["droop"][1] * dr - b["bot"][0] - b["bot"][1] * zs ** 2) * np.maximum(f, 0.3) \
        * (1 - (1 - b["droop"][2]) * dr)

    def hit(o, d):
        p = bvh.ray_cast(Vector(o), Vector(d))[0]
        if p is None:
            raise SystemExit(f"blade: no body from {np.round(o, 3).tolist()} along {d}")
        return p
    rh = np.array([hit((nose + a, 2.5, zc + c), (0, -1, 0)).y for a, c in zip(ru, zs)]) - 0.015
    fu = np.array([hit((nose + 6.0, b["foot"], zc + c), (-1, 0, 0)).x - nose for c in zs]) - 0.010
    fu = np.maximum(fu, te - b["reach"])       # the ends overhang the narrowing tail: their foot on the lamps' top
    lt = np.stack([ru - 0.004, rh + 0.015 + b["root"]])
    sec = [np.stack([ru, rh]), lt]              # L, LT, the top's splits, TT, TB, the ducktail's rows, S: (u, h)
    sec += [lt + (np.stack([te, tt]) - lt) * t for t in b["sheen"]] + [np.stack([te, tt]), np.stack([te - 0.002, tb])]
    for t in np.arange(1, b["rows"]) / b["rows"]:   # hollowed `concave` at mid height, behind the tailgate's surface
        rh_ = tb + (b["foot"] - tb) * t
        gu = [bvh.ray_cast(Vector((nose + 6.0, a, zc + c)), Vector((-1, 0, 0)))[0] for a, c in zip(rh_, zs)]
        sec.append(np.stack([np.maximum(te + (fu - te) * t - 4 * t * (1 - t) * b["concave"],
                                        [p.x - nose + 0.006 if p else -9 for p in gu]), rh_]))
    sec.append(np.stack([fu, np.full_like(zs, b["foot"])]))
    nt = len(b["sheen"]) + 1                    # strips: leading face (paint where it shows, at the ends), the top's,
    mats = [1] + [2 + i for i in range(nt)] + [0] + [1] * b["rows"]   # the trailing face, the rear face (paint)
    m = len(zs)
    V, F, mi = [], [], []

    def row(p):                                 # a (u, h) row's vertices -> the index of its first
        V.append(np.stack([p[0] + nose, p[1], zs + zc], 1))
        return (len(V) - 1) * m
    idx = [row(sec[0])]
    for i, mt in enumerate(mats):               # no bottom (inside the body)
        a = idx[-1]
        if i and mt != mats[i - 1]:             # a colour change: no shared vertex, so the unwrap puts each strip on
            d = sec[i + 1] - sec[i]             # its own island and an island's edge draws the colour's edge (across
            d = d / np.maximum(np.hypot(*d), 1e-6)   # one island it came out in texel steps, 1-2 cm): this one starts
            a = row(sec[i] - 0.006 * d + 0.0003 * np.stack([d[1], -d[0]]))   # 6 mm early, 0.3 mm inside, under the
        idx.append(row(sec[i + 1]))             # last's edge (rays grazing the top passed through a shorter overlap)
        c = idx[-1]
        F += [(a + k, a + k + 1, c + k + 1, c + k) for k in range(m - 1)]
        zm = np.abs(zs[:-1] + zs[1:]) / 2       # the top past |z| paint_z body colour (official REAR34: the ends'
        mi += [1 if mt > 1 and q > b["paint_z"] else mt for q in zm]   # stems run up into it, PN01 dark grey there)
    for k, w in ((0, 1), (m - 1, -1)):          # end caps, a fan from L round the section: paint (the official SIDE:
        for i in range(1, len(sec) - 1):        # body colour where the blade ends)
            F.append(tuple(np.array((idx[0], idx[i], idx[i + 1]))[::w] + k))
            mi.append(1)
    return np.concatenate(V), F, mi


def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=src, forward_axis="NEGATIVE_Z", up_axis="Y")
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    co = {o: np.array([v.co[:] for v in o.data.vertices]) for o in obs}      # OBJ coordinates (x, y up, z)
    allc = np.concatenate([c for o, c in co.items() if not o.name.startswith(PLATES)])
    nose = allc[:, 0].min()
    zc = (allc[:, 2].min() + allc[:, 2].max()) / 2
    body = np.concatenate([c for o, c in co.items() if not o.name.startswith(NOT_BODY)])
    wk = FIELD["width"] / (2 * np.abs(body[:, 2] - zc).max())
    nfin = fins(co, nose)
    npatch = patch(obs, nose, zc)
    tyre = np.concatenate([c for o, c in co.items() if o.name.startswith(TYRES)])
    ax = {k: (tyre[m, 0].min() + tyre[m, 0].max()) / 2 - nose for k, m in
          (("f", tyre[:, 0] - nose < 2.5), ("r", tyre[:, 0] - nose >= 2.5))}
    hw = {k: (tyre[m, 1].min() + tyre[m, 1].max()) / 2 for k, m in
          (("f", tyre[:, 0] - nose < 2.5), ("r", tyre[:, 0] - nose >= 2.5))}
    rad = {k: np.ptp(tyre[m, 1]) / 2 for k, m in (("f", tyre[:, 0] - nose < 2.5), ("r", tyre[:, 0] - nose >= 2.5))}
    tk = {k: FIELD["tyre"][i] / rad[k] for i, k in enumerate("fr")}
    hc = {"f": hw["f"], "r": hw["f"] - FIELD["tyre"][0] + FIELD["tyre"][1]}   # axle heights: the bottoms level
    shorten = ax["f"] - FIELD["front"]                      # the nose moves this far back
    rear = ax["f"] + FIELD["wheelbase"] - ax["r"]           # the rear axle this far
    ends, eaz = [], []
    for o, c in co.items():
        if not o.name.startswith(PLATES):
            e = np.empty(len(o.data.edges) * 2, np.int64)
            o.data.edges.foreach_get("vertices", e)
            ce = c[e.reshape(-1, 2)]
            ends.append(ce[:, :, :2] - (nose, 0))
            eaz.append(np.abs(ce[:, :, 2] - zc).min(1))
    ends, eaz = np.concatenate(ends), np.concatenate(eaz)
    prof = top_profile(ends[:, 0], ends[:, 1])
    side = eaz >= FIELD["rail"]["z"][1]
    rprof = top_profile(ends[side, 0], ends[side, 1])       # the roof rails' top (field() rail)
    g = lower_grid(ax["r"], rear)
    fld = lambda u, h, az: field(u, h, az, prof, g, shorten, rprof)
    E = 1e-4
    new = {}
    fld = with_fit(fld, fit_grid(ax["r"]))
    for o in obs:
        me = o.data
        p = co[o]
        u, h, az = p[:, 0] - nose, p[:, 1], np.abs(p[:, 2] - zc)
        J = np.zeros((len(p), 3, 3))
        J[:, 2, 2] = wk
        if o.name.startswith(WHEEL):        # wheels: moved whole with their axle; the tyres scaled to FIELD tyre
            k = "f" if u.mean() < 2.5 else "r"
            sc = tk[k] if o.name.startswith(TYRES) else 1.0
            du = (ax[k] + (u - ax[k]) * sc - u) + (rear if k == "r" else 0)
            dz = (hc[k] + (h - hw[k]) * sc) - h
            J[:, 0, 0] = J[:, 1, 1] = sc
        else:
            sl = (0.0, 0.0)
            if base(o) in FIELD["joint"]["objs"]:    # slid along the rail first, the field taken at the new place (the
                u2, h2 = joint(u, h, az, rprof)      # Jacobian skips the slide: it runs along the surface)
                sl, u, h = (u2 - u, h2 - h), u2, h2
            du, dz = fld(u, h, az)
            if o.name.startswith(FIELD["mirror"]["objs"]):   # the Jacobian skips it: the arm's shear is black trim
                mr = FIELD["mirror"]
                k = s(az, *mr["z"])
                back = np.maximum(u - mr["sx"][0], 0)
                du = du + k * (mr["d"][0] - (1 - mr["sx"][1]) * back)
                dz = dz + k * (mr["d"][1] + mr["tilt"]["d"] * back * np.interp(h, mr["tilt"]["h"], (0, 1, 0)))
            # Jacobian of (x, y, z) -> (x + du, y + dz, z wk) by central differences
            dxu = [(a - b) / (2 * E) for a, b in zip(fld(u + E, h, az), fld(u - E, h, az))]
            dxh = [(a - b) / (2 * E) for a, b in zip(fld(u, h + E, az), fld(u, h - E, az))]
            dxz = [(a - b) / (2 * E) for a, b in zip(fld(u, h, az + E), fld(u, h, az - E))]
            J[:, 0, 0], J[:, 0, 1], J[:, 0, 2] = 1 + dxu[0], dxh[0], dxz[0] * np.sign(p[:, 2] - zc)
            J[:, 1, 0], J[:, 1, 1], J[:, 1, 2] = dxu[1], 1 + dxh[1], dxz[1] * np.sign(p[:, 2] - zc)
            du, dz = du + sl[0], dz + sl[1]
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        n = np.einsum("lij,li->lj", np.linalg.inv(J)[lv], cn.reshape(-1, 3))   # n' = J^-T n (row vector n J^-1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        p2 = p.copy()
        p2[:, 0] += du
        p2[:, 1] += dz
        p2[:, 2] = zc + (p[:, 2] - zc) * wk
        new[o] = (p2, n)
    # the ground: the lowest tyre vertex (the script's wheels and the seat heights take the ground as the tyres'
    # bottom, seat_head.py's depth reference)
    lift = -min(p2[:, 1].min() for o, (p2, n) in new.items() if o.name.startswith(TYRES))
    for o, (p2, n) in new.items():
        me = o.data
        p2[:, 1] += lift
        me.vertices.foreach_set("co", p2.ravel())
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", n.astype(np.float32).ravel())
        me.update()
    sp = FIELD["splitter"]
    for o in obs:
        if base(o) in sp["objs"]:
            me, c = o.data, co[o]
            me.materials.append(bpy.data.materials.get(sp["mat"]) or bpy.data.materials.new(sp["mat"]))
            for poly in me.polygons:
                q = c[list(poly.vertices)].mean(0)
                if q[0] - nose < sp["u"] and q[1] < sp["h"]:
                    poly.material_index = len(me.materials) - 1
    from mathutils.bvhtree import BVHTree

    def bvh_of(names):                          # those objects as prepped
        hull = [o for o in obs if base(o) in names]
        k = np.cumsum([0] + [len(new[o][0]) for o in hull])
        return BVHTree.FromPolygons([tuple(v) for o in hull for v in new[o][0]],
                                    [[i + k0 for i in p.vertices] for o, k0 in zip(hull, k) for p in o.data.polygons])
    for name, (bv, bf, mi), mats in (
            ("Blade_YL", blade(new[[o for o in obs if base(o) == BLADE_ROOT][0]][0], new_nose(new), zc,
                               bvh_of(BLADE_HULL)), (BLADE_MAT, BLADE_PAINT) + BLADE_TOP),
            ("Blackout_YL", blackout(fld, wk, lift, nose, zc) + (None,), (BLACKOUT_MAT,)),
            ("Trim_YL", trim(new_nose(new), zc, bvh_of(FIELD["trim"]["objs"])) + (None,), (FIELD["trim"]["mat"],))):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in bv], [], bf)
        for mat in mats:
            me.materials.append(bpy.data.materials.get(mat) or bpy.data.materials.new(mat))
        if mi is not None:                      # the ducktail's faces smooth (its concave face read faceted)
            me.polygons.foreach_set("material_index", mi)
            me.polygons.foreach_set("use_smooth", [bool(m == 1 and len(f) == 4) for m, f in zip(mi, bf)])
        me.update()
        bo = bpy.data.objects.new(name, me)
        bo.matrix_world = obs[0].matrix_world.copy()          # the importer's axes, as every source object
        bpy.context.scene.collection.objects.link(bo)
        obs.append(bo)
    print("PREP nose %.4f back, rear axle %.4f back, width x %.5f, tyres x %.4f / %.4f (source r %.4f / %.4f, axle h "
          "%.4f / %.4f -> %.4f / %.4f), lifted %.4f, fins %d points, patch %d faces"
          % (shorten, rear, wk, tk["f"], tk["r"], rad["f"], rad["r"], hw["f"], hw["r"], hc["f"], hc["r"], lift, nfin,
             npatch))
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.ops.wm.obj_export(filepath=out, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=False, export_normals=True, export_materials=True, apply_modifiers=False,
                          export_triangulated_mesh=False)
    print("PREP ->", out)


if __name__ == "__main__":
    main()
