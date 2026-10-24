# /// script
# requires-python = ">=3.10"
# dependencies = ["glfw", "PyOpenGL", "numpy"]
# ///
"""Offline compile + link of MinidoracatTesla_vehicle (vanilla vehicle_multiuv_noreflect as control) the way
ShaderUnit.java prepares them: #include "x" inlines x.h and adds x.glsl as an extra unit (:68-82,226-300); GL 2.1 mode
rewrites #version 330 -> 120, layout(...) in -> attribute (:296-350). Hidden GLFW window, compatibility context.
Also checks the reflection test: an empty texture unit 8 must read reflectionsOn = 0, a bound 4 x 4 texture 1.

  uv run scripts/shader/glcompile.py          (exit 1 on any compile / link failure; set PZ_DIR for another install)
"""
import os
import re, sys
from pathlib import Path
import glfw
from OpenGL import GL

VAN = Path(os.environ.get("PZ_DIR", "D:/SteamLibrary/steamapps/common/ProjectZomboid")) / "media/shaders"
MOD = Path(__file__).resolve().parents[2] / "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/shaders"


def find(name):
    for d in (MOD, VAN):
        if (d / name).exists():
            return d / name
    raise FileNotFoundError(name)


def prep(path, gl21, vert, extra):
    out = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        m = re.match(r'\s*#include\s+"([^"]+)"', line)
        if m:
            out.append(prep(find(m.group(1) + ".h"), gl21, vert, extra))
            g = m.group(1) + ".glsl"
            if g not in extra:
                extra.append(g)
            continue
        if gl21:
            if re.search(r"#version (330|110|130|140|430)", line):
                line = "#version 120"
            m = re.match(r"layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*in\s+(\w+)\s+(\w+);", line.strip()) if vert else None
            if m:
                line = f"attribute {m.group(2)} {m.group(3)};"
        out.append(line)
    return "\n".join(out)


def compile_(kind, src):
    s = GL.glCreateShader(kind)
    GL.glShaderSource(s, src)
    GL.glCompileShader(s)
    if not GL.glGetShaderiv(s, GL.GL_COMPILE_STATUS):
        raise RuntimeError(GL.glGetShaderInfoLog(s).decode())
    return s


def program(name, gl21, vsuffix="_static"):
    extra = []
    units = [compile_(GL.GL_VERTEX_SHADER, prep(find(name + vsuffix + ".vert"), gl21, True, []))]
    units.append(compile_(GL.GL_FRAGMENT_SHADER, prep(find(name + ".frag"), gl21, False, extra)))
    done = set()
    while extra:
        g = extra.pop(0)
        if g in done:
            continue
        done.add(g)
        units.append(compile_(GL.GL_FRAGMENT_SHADER, prep(find(g), gl21, False, extra)))
    p = GL.glCreateProgram()
    for u in units:
        GL.glAttachShader(p, u)
    GL.glLinkProgram(p)
    if not GL.glGetProgramiv(p, GL.GL_LINK_STATUS):
        raise RuntimeError(GL.glGetProgramInfoLog(p).decode())
    loc = {u: GL.glGetUniformLocation(p, u) for u in ("TextureRust", "TextureMask", "TexturePainColor", "Texture", "MatrixPalette", "Alpha")}
    return loc


glfw.init()
glfw.window_hint(glfw.VISIBLE, glfw.FALSE)
win = glfw.create_window(64, 64, "glsl", None, None)
glfw.make_context_current(win)
print("GL", GL.glGetString(GL.GL_VERSION).decode(), "|", GL.glGetString(GL.GL_RENDERER).decode())
bad = 0
for name, vs in (("vehicle_multiuv_noreflect", "_static"), ("MinidoracatTesla_vehicle", "_static"), ("MinidoracatTesla_vehicle", "")):
    for gl21 in (False, True):
        try:
            print("OK  ", name + vs, "GL2.1" if gl21 else "GL3.3", program(name, gl21, vs))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("FAIL", name, "GL2.1" if gl21 else "GL3.3", str(e)[:2000])
# unit 8 with nothing bound: textureSize must read <= 1 (the vertex shader's reflectionsOn = 0), with a 4 x 4 texture: 1
VS = "#version 330\nlayout(location=0) in vec2 p; uniform sampler2D T; varying float on;\nvoid main(){ on = textureSize(T,0).x > 1 ? 1.0 : 0.0; gl_Position = vec4(p,0,1); }"
FS = "#version 120\nvarying float on; void main(){ gl_FragColor = vec4(on, 0.0, 0.0, 1.0); }"
p = GL.glCreateProgram()
GL.glAttachShader(p, compile_(GL.GL_VERTEX_SHADER, VS))
GL.glAttachShader(p, compile_(GL.GL_FRAGMENT_SHADER, FS))
GL.glLinkProgram(p)
GL.glUseProgram(p)
GL.glUniform1i(GL.glGetUniformLocation(p, "T"), 8)
import numpy as np
vb = GL.glGenBuffers(1)
GL.glBindBuffer(GL.GL_ARRAY_BUFFER, vb)
GL.glBufferData(GL.GL_ARRAY_BUFFER, np.array([-1, -1, 3, -1, -1, 3], np.float32), GL.GL_STATIC_DRAW)
GL.glEnableVertexAttribArray(0)
GL.glVertexAttribPointer(0, 2, GL.GL_FLOAT, False, 0, None)
for bind in (False, True):
    GL.glActiveTexture(GL.GL_TEXTURE8)
    if bind:
        t = GL.glGenTextures(1)
        GL.glBindTexture(GL.GL_TEXTURE_2D, t)
        GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, 4, 4, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, None)
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)
    GL.glClear(GL.GL_COLOR_BUFFER_BIT)
    GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3)
    px = GL.glReadPixels(32, 32, 1, 1, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE)
    print("unit 8", "bound" if bind else "empty", "reflectionsOn =", px[0] / 255 if isinstance(px, bytes) else px)
glfw.terminate()
sys.exit(1 if bad else 0)
