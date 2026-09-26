#!/usr/bin/env python3
"""Synthesises the slice's placeholder audio (M9b): combat SFX, foley, UI, ambience and music
loops. Standard library only and seeded, so re-running produces identical files.

    python3 tools/audio/make_placeholder_audio.py            # writes assets/audio/placeholder/

SFX are 16-bit mono 44.1 kHz WAV. Loops (ambience, music) are written as WAV and, when ffmpeg is
on PATH, converted to Ogg Vorbis (much smaller); the WAV is then removed. The WAVs are
byte-identical run to run; the Ogg files differ only in the encoder's random stream serial, so
restore them with git if you didn't mean to change a loop. Every file is original
and released as CC0 (see assets/LICENSES.md). They stand in until sourced or composed audio
(PLAN §4.4) replaces them under the same event names (resources/audio/sound_bank.tres).
"""

import math
import os
import random
import shutil
import struct
import subprocess
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "placeholder")


# --- Building blocks ----------------------------------------------------------------------------

def silence(seconds):
    return [0.0] * int(seconds * RATE)


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * RATE))]


def lowpass(samples, cutoff):
    """One-pole low-pass; `cutoff` is a Hz value or a per-sample callable."""
    out, y = [], 0.0
    for i, x in enumerate(samples):
        c = cutoff(i) if callable(cutoff) else cutoff
        a = 1.0 - math.exp(-2.0 * math.pi * max(c, 1.0) / RATE)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [x - l for x, l in zip(samples, low)]


def envelope(n, attack, decay, hold=0.0):
    """Linear attack, optional hold, exponential decay (seconds; decay = time constant)."""
    a, h = int(attack * RATE), int(hold * RATE)
    env = []
    for i in range(n):
        if i < a:
            env.append(i / max(a, 1))
        elif i < a + h:
            env.append(1.0)
        else:
            env.append(math.exp(-(i - a - h) / (decay * RATE)))
    return env


def bell(n, peak=0.5):
    """Smooth rise and fall over n samples, peaking at `peak` (fraction)."""
    p = max(1, int(n * peak))
    return [math.sin(0.5 * math.pi * i / p) ** 2 if i < p else math.cos(0.5 * math.pi * (i - p) / max(n - p, 1)) ** 2 for i in range(n)]


def sine(seconds, freq, phase=0.0):
    """`freq` may be a callable of time (s) for sweeps."""
    out, ph = [], phase
    for i in range(int(seconds * RATE)):
        f = freq(i / RATE) if callable(freq) else freq
        ph += 2.0 * math.pi * f / RATE
        out.append(math.sin(ph))
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def mix(*tracks):
    n = max(len(t) for t, _ in tracks)
    out = [0.0] * n
    for track, gain in tracks:
        for i, x in enumerate(track):
            out[i] += x * gain
    return out


def ring(seconds, partials, rng, detune=0.0):
    """Inharmonic metal: [(freq, amplitude, decay)]."""
    n = int(seconds * RATE)
    out = [0.0] * n
    for freq, amp, decay in partials:
        f = freq * (1.0 + rng.uniform(-detune, detune))
        tone = sine(seconds, f, rng.uniform(0, math.tau))
        env = envelope(n, 0.001, decay)
        for i in range(n):
            out[i] += tone[i] * env[i] * amp
    return out


def thump(seconds, start, end, decay):
    tone = sine(seconds, lambda t: end + (start - end) * math.exp(-t / 0.05))
    return mul(tone, envelope(len(tone), 0.002, decay))


def click(rng, seconds=0.006, cutoff=6000):
    burst = highpass(noise(seconds, rng), cutoff)
    return mul(burst, envelope(len(burst), 0.0005, seconds / 3))


def normalise(samples, peak_db=-3.0):
    peak = max(1e-9, max(abs(x) for x in samples))
    gain = 10 ** (peak_db / 20.0) / peak
    return [x * gain for x in samples]


def fade_out(samples, seconds=0.01):
    n = min(len(samples), int(seconds * RATE))
    for i in range(n):
        samples[-1 - i] *= i / n
    return samples


def write_wav(name, samples, peak_db=-3.0):
    samples = normalise(samples, peak_db)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767)) for x in samples))
    return path


def write_loop(name, samples, peak_db=-6.0):
    path = write_wav(name, samples, peak_db)
    if shutil.which("ffmpeg"):
        ogg = path[:-4] + ".ogg"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
        os.remove(path)


def circular_add(buffer, event, at):
    """Adds `event` into a loop buffer starting at sample `at`, wrapping past the end."""
    n = len(buffer)
    for i, x in enumerate(event):
        buffer[(at + i) % n] += x


# --- Sounds -------------------------------------------------------------------------------------

def whoosh(rng, seconds, low, high, weight):
    n = int(seconds * RATE)
    sweep = lambda i: low + (high - low) * math.sin(math.pi * i / n) ** 1.5
    body = lowpass(highpass(noise(seconds, rng), 200), sweep)
    return mul(body, [e ** weight for e in bell(n, 0.4)])


def impact(rng, heavy=False):
    length = 0.45 if heavy else 0.28
    body = lowpass(noise(length, rng), 1600 if heavy else 2400)
    body = mul(body, envelope(len(body), 0.001, 0.06 if heavy else 0.04))
    return fade_out(mix((click(rng), 0.9), (thump(length, 140, 48 if heavy else 62, 0.14 if heavy else 0.09), 1.0), (body, 0.7)))


def block(rng):
    metal = ring(0.35, [(880, 0.5, 0.09), (1370, 0.4, 0.07), (2210, 0.3, 0.05)], rng, detune=0.04)
    return fade_out(mix((click(rng, cutoff=3000), 0.8), (thump(0.35, 120, 70, 0.06), 0.8), (metal, 0.7)))


def parry(rng, pitch):
    partials = [(1480 * pitch, 0.6, 0.55), (2330 * pitch, 0.45, 0.4), (3960 * pitch, 0.3, 0.25), (5150 * pitch, 0.2, 0.15)]
    return fade_out(mix((click(rng, 0.004, 5000), 1.0), (ring(1.0, partials, rng, 0.005), 0.9)), 0.05)


def posture_break(rng):
    crash = mul(lowpass(noise(1.0, rng), 1200), envelope(int(RATE), 0.004, 0.25))
    metal = ring(1.0, [(420, 0.4, 0.4), (655, 0.35, 0.3), (1110, 0.25, 0.2)], rng, 0.01)
    return fade_out(mix((thump(1.0, 110, 34, 0.35), 1.0), (crash, 0.6), (metal, 0.5), (click(rng), 0.6)), 0.05)


def footstep(rng, kind):
    if kind == "grass":
        body = mul(highpass(noise(0.14, rng), 1800), bell(int(0.14 * RATE), 0.25))
        return fade_out(lowpass(body, 6000))
    if kind == "gravel":
        n = int(0.16 * RATE)
        out = [0.0] * n
        for _ in range(26):                                   # grains of crunch
            at = int(rng.betavariate(1.5, 4.0) * n * 0.8)
            circular_add(out, [x * rng.uniform(0.3, 1.0) for x in click(rng, 0.004, 2500)], at)
        return fade_out(mix((out, 1.0), (thump(0.16, 90, 60, 0.03), 0.4)))
    if kind == "wood":                                        # hollow plank knock
        knock = ring(0.16, [(210, 0.6, 0.05), (470, 0.35, 0.03), (910, 0.2, 0.02)], rng, 0.03)
        return fade_out(mix((click(rng, 0.005, 2200), 0.5), (knock, 0.9), (thump(0.16, 130, 95, 0.03), 0.5)))
    return fade_out(mix((click(rng, 0.008, 1800), 0.7), (thump(0.12, 150, 90, 0.025), 0.8)))   # stone


def glint(rng, unblockable):
    n = int(0.6 * RATE)
    if unblockable:
        tone = mix((sine(0.6, 1800), 0.5), (sine(0.6, 1907), 0.5), (sine(0.6, 2710), 0.25))
        tremolo = [0.6 + 0.4 * math.sin(2 * math.pi * 18 * i / RATE) for i in range(n)]
        return fade_out(mul(mul(tone, tremolo), envelope(n, 0.005, 0.18)))
    tone = mix((sine(0.6, 2637), 0.6), (sine(0.6, 3951), 0.35), (sine(0.6, 5274), 0.15))
    return fade_out(mul(tone, envelope(n, 0.01, 0.2)))


def ignite(rng):
    n = int(1.3 * RATE)
    swell = lowpass(noise(1.3, rng), lambda i: 300 + 2500 * (i / n))
    swell = mul(swell, [math.sin(math.pi * min(i / (0.7 * n), 1.0) * 0.5) * math.exp(-max(0, i - 0.7 * n) / (0.15 * RATE)) for i in range(n)])
    hum = mul(mix((sine(1.3, 110), 0.5), (sine(1.3, 165), 0.3)), bell(n, 0.6))
    return fade_out(mix((swell, 0.8), (hum, 0.5)), 0.05)


def gate(rng):
    n = int(1.0 * RATE)
    rattle = [0.5 + 0.5 * math.sin(2 * math.pi * 34 * i / RATE) for i in range(n)]
    grind = mul(mul(lowpass(highpass(noise(1.0, rng), 300), 2200), rattle), bell(n, 0.3))
    clank = [0.0] * n
    circular_add(clank, block(rng), int(0.78 * RATE))          # the portcullis lands
    return fade_out(mix((grind, 0.6), (clank, 0.9)), 0.03)


def roar(rng):
    n = int(1.6 * RATE)
    growl = sine(1.6, lambda t: 70 + 12 * math.sin(2 * math.pi * 7 * t) - 15 * t)
    growl = [math.tanh(3.0 * x) for x in growl]                                  # grit
    breath = lowpass(noise(1.6, rng), 900)
    return fade_out(mul(mix((growl, 0.8), (breath, 0.6)), bell(n, 0.25)), 0.05)


def ui(up):
    tone = sine(0.1, (lambda t: 880 + 4400 * t) if up else (lambda t: 660 - 2200 * t))
    return fade_out(mul(tone, envelope(len(tone), 0.003, 0.03)))


def wind_loop(rng, seconds=12.0):
    n = int(seconds * RATE)
    cutoff = lambda i: 380 + 260 * math.sin(2 * math.pi * i / n) + 120 * math.sin(6 * math.pi * i / n + 1.0)
    body = lowpass(noise(seconds + 1.0, rng), cutoff)
    swell = [0.65 + 0.35 * math.sin(2 * math.pi * 2 * i / n + 0.5) for i in range(n)]
    loop = mul(body[:n], swell)
    tail = body[n:n + int(RATE)]                              # crossfade the extra second in
    for i, x in enumerate(tail):
        w = i / len(tail)
        loop[i] = loop[i] * w + x * (1.0 - w) * swell[i]
    return loop


def drum_loop(rng, bpm, bars, boss):
    beat = 60.0 / bpm
    n = int(beat * 4 * bars * RATE)
    out = [0.0] * n
    taiko = lambda: mul(thump(0.9, 160, 55, 0.22), [1.0] * int(0.9 * RATE))
    for bar in range(bars):
        for step in range(16):                                 # sixteenth grid
            at = int(((bar * 4) + step / 4.0) * beat * RATE)
            if step in (0, 6, 10) or (boss and step == 14):
                circular_add(out, [x * (1.0 if step == 0 else 0.7) for x in taiko()], at)
            if step % 4 == 2 or (boss and step % 2 == 1):
                circular_add(out, [x * 0.35 for x in click(rng, 0.02, 2500)], at)
    drone_freqs = (55.0, 58.3) if boss else (55.0, 82.4)
    drone = mix(*[(sine(n / RATE, f), 0.12) for f in drone_freqs])
    return mix((out, 1.0), (drone, 1.0))


def victory(rng):
    notes = [440.0, 523.25, 587.33, 659.25, 783.99, 880.0]
    n = int(3.2 * RATE)
    out = [0.0] * n
    for k, f in enumerate(notes):
        tone = mix((sine(2.4, f), 0.6), (sine(2.4, f * 2.76), 0.25), (sine(2.4, f * 5.4), 0.1))
        circular_add(out, mul(tone, envelope(len(tone), 0.004, 0.6)), int(k * 0.16 * RATE))
    return fade_out(out, 0.3)


# --- Main ---------------------------------------------------------------------------------------

def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(20260926)
    for i in range(3):
        write_wav(f"whoosh_light_{i + 1}", whoosh(rng, 0.24 + 0.03 * i, 500, 3200 + 400 * i, 1.0))
        write_wav(f"whoosh_heavy_{i + 1}", whoosh(rng, 0.42 + 0.04 * i, 250, 1500 + 200 * i, 0.8))
        write_wav(f"hit_{i + 1}", impact(rng))
        write_wav(f"block_{i + 1}", block(rng))
        write_wav(f"parry_{i + 1}", parry(rng, 1.0 + 0.06 * (i - 1)))
    write_wav("hit_heavy", impact(rng, heavy=True))
    write_wav("posture_break", posture_break(rng))
    for kind in ("grass", "gravel", "stone"):
        for i in range(4):
            write_wav(f"step_{kind}_{i + 1}", footstep(rng, kind), -6.0)
    write_wav("glint_gold", glint(rng, False), -6.0)
    write_wav("glint_red", glint(rng, True), -6.0)
    write_wav("shrine_ignite", ignite(rng))
    write_wav("gate", gate(rng))
    write_wav("roar", roar(rng))
    write_wav("ui_confirm", ui(True), -8.0)
    write_wav("ui_back", ui(False), -8.0)
    write_loop("ambience_wind", wind_loop(rng), -9.0)
    write_loop("music_combat", drum_loop(rng, 96, 4, boss=False))
    write_loop("music_boss", drum_loop(rng, 118, 4, boss=True))
    write_wav("music_victory", victory(rng), -4.0)
    wood = random.Random(20260927)          # its own seed, so adding it left the files above unchanged
    for i in range(4):
        write_wav(f"step_wood_{i + 1}", footstep(wood, "wood"), -6.0)
    print("wrote", len(os.listdir(OUT)), "files to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
