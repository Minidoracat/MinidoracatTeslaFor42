# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy>=1.26", "scipy>=1.11"]
# ///
"""Cut Tesla's own recordings into the MOD's .ogg files.

    uv run scripts/sound/build_sounds.py [source dir]     (default temp/sound-src/)

Sources: Tesla "Normal Operating Sounds" page (Model Y DIY guide)
  https://service.tesla.com/docs/Public/diy/modely/en_us/GUID-AA58ED67-9C93-4EE6-8B19-9FDABE018787.html
  files under https://service.tesla.com/docs/Public/om_media/<name>. curl gets 403; fetch them from a
  browser tab on that page (references/sound.md "音檔").
Outputs (overwritten): media/sound/MinidoracatTesla/*.ogg, mono 44.1 kHz Vorbis.
Loops: the tail after the cut is equal-power cross-faded into the head, so sample N-1 runs straight
into sample 0. The seam check asserts the wrap step is no bigger than the signal's own steps and
the RMS around the seam matches the loop body.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
import scipy.io.wavfile as wavfile
from scipy.signal import butter, sosfiltfilt

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "MOD", "MinidoracatTeslaFor42", "Contents", "mods", "MinidoracatTeslaFor42", "42",
                   "media", "sound", "MinidoracatTesla")
SR = 44100

# name: (source file, start s, end s, loop cross-fade s or 0 for one-shot, high-pass Hz, target dBFS, mode)
# mode "rms" sets the body RMS (loops, so Lua/clip volumes mean the same thing for every loop);
# "peak" sets the peak (one-shots). Times come from the 100 ms RMS envelopes in references/sound.md.
CUTS = {
    "Hum":        ("coolant_pump_motor_humming.mp3",           0.40, 3.40,  0.50, 60,  -20, "rms"),
    "Motor":      ("high_pitched_noise_when_accelerating.mp4", 0.40, 3.70,  0.60, 80,  -18, "rms"),
    "PWSForward": ("pws_drive_forward.mp3",                    0.40, 4.40,  0.50, 110, -18, "rms"),
    "PWSReverse": ("pedestrian_speaker.mp3",                   1.00, 2.983, 0.25, 80,  -18, "rms"),  # 8 pulses of 0.248 s
    "Contactors": ("hv_contactors.mp3",                        0.85, 1.95, 0,    40,  -3,  "peak"),
    "ParkBrake":  ("epb_enable.mp4",                           0.42, 1.95, 0,    40,  -3,  "peak"),
    "KeyAlert":   ("autopilot_alert.mp3",                      0.00, 0.40, 0,    40,  -3,  "peak"),
    "NoPower":    ("autopilot_unavailable.mp3",                0.00, 0.73, 0,    40,  -3,  "peak"),
}
EDGE = 0.008  # one-shot fade in/out (s): no click at start/end


def decode(path):
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, "x.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", str(SR), "-c:a", "pcm_f32le", wav],
                       check=True)
        return wavfile.read(wav)[1].astype(np.float64)


def loop(x, a, b, fade):
    """y = x[a:b] with x[b:b+fade] cross-faded into its head: y[-1] -> y[0] continues x[b-1] -> x[b]."""
    n, f = int(b * SR) - int(a * SR), int(fade * SR)
    a0 = int(a * SR)
    body, tail = x[a0:a0 + n].copy(), x[a0 + n:a0 + n + f]
    if len(tail) < f:
        sys.exit(f"loop tail runs past the source end ({b}+{fade} s)")
    t = np.linspace(0, np.pi / 2, f, endpoint=False)
    body[:f] = body[:f] * np.sin(t) + tail * np.cos(t)
    return body


def seam_check(name, y):
    step = np.abs(np.diff(y))
    wrap = abs(y[0] - y[-1])
    w = int(0.05 * SR)
    around = np.sqrt(np.mean(np.concatenate([y[-w:], y[:w]]) ** 2))
    body = np.sqrt(np.mean(y ** 2))
    ratio_db = 20 * np.log10(around / body)
    print(f"  seam: wrap step {wrap:.4f} (signal p99 {np.percentile(step, 99):.4f}, max {step.max():.4f}),"
          f" RMS around seam {ratio_db:+.1f} dB vs body")
    assert wrap <= step.max(), f"{name}: wrap step larger than any step inside the loop"
    assert abs(ratio_db) < 3, f"{name}: loudness dips or jumps at the seam"


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "temp", "sound-src")
    os.makedirs(OUT, exist_ok=True)
    for name, (file, a, b, fade, hp, target, mode) in CUTS.items():
        x = decode(os.path.join(src, file))
        x = sosfiltfilt(butter(4, hp, "highpass", fs=SR, output="sos"), x)
        if fade:
            y = loop(x, a, b, fade)
        else:
            y = x[int(a * SR):int(b * SR)].copy()
            e = int(EDGE * SR)
            y[:e] *= np.linspace(0, 1, e)
            y[-e:] *= np.linspace(1, 0, e)
        level = np.sqrt(np.mean(y ** 2)) if mode == "rms" else np.abs(y).max()
        y *= 10 ** (target / 20) / level
        assert np.abs(y).max() < 1.0, f"{name}: clips after normalising"
        out = os.path.join(OUT, name + ".ogg")
        with tempfile.TemporaryDirectory() as d:
            wav = os.path.join(d, "y.wav")
            wavfile.write(wav, SR, y.astype(np.float32))
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", out], check=True)
        dec = decode(out)
        print(f"{name}.ogg  {len(dec) / SR:.2f} s  {os.path.getsize(out)} B  peak {20 * np.log10(np.abs(dec).max()):.1f} dBFS"
              f"  rms {20 * np.log10(np.sqrt(np.mean(dec ** 2))):.1f} dBFS")
        if fade:
            assert len(dec) == len(y), f"{name}: decoded length {len(dec)} != {len(y)} (the loop would gain a gap)"
            seam_check(name, dec)


if __name__ == "__main__":
    main()
