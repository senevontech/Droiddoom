"""Synthesizes Droidoom's fallback sound effects (P1-13 / P1-22, v2 "realistic").

Original procedural sounds, so there are no licence questions. Deterministic:
the same script always writes the same files.

v2 builds each sound like a real recording is made up:
  - transient: a 1-3 ms crack (what makes a gunshot read as a gunshot),
  - body: band-limited noise and low-frequency punch, soft-saturated,
  - detail: mechanical clicks, metallic modes (inharmonic partials), debris,
  - space: early street reflections + a short diffuse reverb tail.

Real recordings always win: AudioManager plays `<name>.ogg` or `<name>.wav`
from game/assets/audio/sfx_real/ instead of these when such a file exists
(see tools/README_SFX.md).

Usage (repo root):  py -3 tools/gen_sfx.py
Output: game/assets/audio/sfx/<name>.wav (44.1 kHz, mono, 16-bit)
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "audio" / "sfx"


class Sig:
    """A mono buffer with synthesis helpers. Times are in seconds."""

    def __init__(self, seconds: float, seed: int):
        self.n = int(seconds * RATE)
        self.s = [0.0] * self.n
        self.rng = random.Random(seed)

    # --- sources -----------------------------------------------------------
    def noise(self, gain, env, lowpass=1.0, highpass=0.0, start=0.0, length=None):
        """Filtered white noise. lowpass/highpass are one-pole coefficients 0..1."""
        i0 = int(start * RATE)
        i1 = self.n if length is None else min(self.n, i0 + int(length * RATE))
        lp = hp_state = 0.0
        for i in range(i0, i1):
            x = self.rng.uniform(-1.0, 1.0)
            lp += lowpass * (x - lp)
            y = lp
            if highpass > 0.0:
                hp_state += highpass * (y - hp_state)
                y -= hp_state
            self.s[i] += y * gain * env((i - i0) / RATE)
        return self

    def tone(self, gain, f0, f1, env, start=0.0, length=None, shape="sine"):
        """Oscillator gliding f0 → f1 (exponential glide)."""
        i0 = int(start * RATE)
        i1 = self.n if length is None else min(self.n, i0 + int(length * RATE))
        dur = max(1, i1 - i0)
        phase = 0.0
        for i in range(i0, i1):
            k = (i - i0) / dur
            f = f0 * (f1 / f0) ** k if f0 > 0 and f1 > 0 else f0 + (f1 - f0) * k
            phase += 2.0 * math.pi * f / RATE
            if shape == "sine":
                v = math.sin(phase)
            elif shape == "saw":
                v = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
            else:
                v = math.tanh(3.0 * math.sin(phase))
            self.s[i] += v * gain * env((i - i0) / RATE)
        return self

    def modes(self, gain, f0, ratios, decay, start=0.0, length=0.6):
        """Struck-metal ring: inharmonic partials, higher ones die faster."""
        for k, r in enumerate(ratios):
            amp = gain / (1.0 + k * 0.7)
            rate = decay * (1.0 + k * 0.8)
            self.tone(amp, f0 * r, f0 * r, lambda t, rate=rate: math.exp(-t * rate), start, length)
        return self

    def crack(self, gain, start=0.0, ms=2.0):
        """The 1-3 ms supersonic snap at the front of a gunshot."""
        i0 = int(start * RATE)
        for i in range(i0, min(self.n, i0 + int(ms * RATE / 1000.0))):
            t = (i - i0) / RATE
            self.s[i] += self.rng.uniform(-1.0, 1.0) * gain * math.exp(-t * 900.0)
        return self

    def clicks(self, gain, count, start, spread, decay):
        """Sparse tiny clicks (debris, sparks, gravel)."""
        for _ in range(count):
            t0 = start + self.rng.random() ** 1.7 * spread
            amp = gain * math.exp(-(t0 - start) * decay) * self.rng.uniform(0.3, 1.0)
            i0 = int(t0 * RATE)
            for i in range(i0, min(self.n, i0 + int(0.004 * RATE))):
                self.s[i] += self.rng.uniform(-1.0, 1.0) * amp * math.exp(-(i - i0) / RATE * 1500.0)
        return self

    # --- processing ----------------------------------------------------------
    def saturate(self, drive):
        """Soft clipping: denser, louder-sounding body."""
        self.s = [math.tanh(v * drive) / math.tanh(drive) for v in self.s]
        return self

    def lowpass(self, coef):
        y = 0.0
        for i in range(self.n):
            y += coef * (self.s[i] - y)
            self.s[i] = y
        return self

    def space(self, wet, size=1.0, damp=0.35):
        """Street acoustics: early reflections + a small comb/allpass reverb."""
        dry = self.s[:]
        out = dry[:]
        # Early reflections off facades (ms, gain).
        for ms, g in ((23, 0.45), (41, 0.35), (67, 0.3), (103, 0.22), (151, 0.15)):
            d = int(ms * size * RATE / 1000.0)
            for i in range(d, self.n):
                out[i] += dry[i - d] * g * wet
        # Diffuse tail: four damped feedback combs into two allpasses.
        tail = [0.0] * self.n
        for ms, fb in ((29.7, 0.80), (37.1, 0.79), (41.1, 0.77), (43.7, 0.76)):
            d = max(1, int(ms * size * RATE / 1000.0))
            buf = [0.0] * d
            idx = 0
            lp = 0.0
            for i in range(self.n):
                y = buf[idx]
                lp = y * (1.0 - damp) + lp * damp
                buf[idx] = dry[i] + lp * fb
                idx = (idx + 1) % d
                tail[i] += y * 0.25
        for ms, g in ((5.0, 0.5), (1.7, 0.5)):
            d = max(1, int(ms * RATE / 1000.0))
            buf = [0.0] * d
            idx = 0
            for i in range(self.n):
                b = buf[idx]
                y = -tail[i] + b
                buf[idx] = tail[i] + b * g
                idx = (idx + 1) % d
                tail[i] = y
        self.s = [out[i] + tail[i] * wet for i in range(self.n)]
        return self

    def write(self, name: str) -> None:
        peak = max(1e-6, max(abs(v) for v in self.s))
        gain = 0.9 / peak
        fade = int(0.01 * RATE)
        frames = bytearray()
        for i, v in enumerate(self.s):
            if i >= self.n - fade:
                v *= (self.n - i) / fade
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v * gain)) * 32767))
        OUT.mkdir(parents=True, exist_ok=True)
        with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(bytes(frames))
        print(f"{name}.wav  {self.n / RATE:.2f} s")


def exp(rate):
    return lambda t: math.exp(-t * rate)


def ad(attack, rate):
    """Attack then exponential decay."""
    return lambda t: (t / attack if t < attack else math.exp(-(t - attack) * rate))


def flat(_t):
    return 1.0


METAL = (1.0, 2.76, 5.40, 8.93)  # struck plate/bar partial ratios


def build() -> None:
    # --- Player weapons ---------------------------------------------------
    (  # Pulse Rifle: crack + muzzle blast + bolt click + street slap.
        Sig(0.7, 1)
        .crack(1.0)
        .noise(0.9, exp(55), 0.35, 0.02)
        .tone(0.8, 150, 60, exp(40))
        .saturate(2.2)
        .clicks(0.25, 3, 0.045, 0.01, 40)
        .space(0.35, 0.9)
        .write("shot_rifle")
    )
    (  # Scattergun: heavier, wider blast, pump rack.
        Sig(1.0, 2)
        .crack(1.0, ms=3)
        .noise(1.0, exp(22), 0.22, 0.01)
        .tone(1.0, 110, 40, exp(18))
        .saturate(2.8)
        .clicks(0.3, 4, 0.32, 0.06, 10)
        .space(0.45, 1.0)
        .write("shot_scatter")
    )
    (  # Beam Laser tick: electric buzz with crackle (sci-fi by nature).
        Sig(0.12, 3)
        .tone(0.5, 880, 760, flat, shape="saw")
        .tone(0.3, 1760, 1520, flat)
        .noise(0.25, flat, 0.9, 0.5)
        .write("shot_laser")
    )
    (  # Railgun: short charge whine, hard crack, ringing rail, long tail.
        Sig(1.4, 4)
        .tone(0.3, 900, 3200, ad(0.05, 60), length=0.06)
        .crack(1.0, start=0.05, ms=3)
        .noise(0.7, exp(40), 0.5, 0.0, start=0.05)
        .modes(0.35, 620, METAL, 5.0, start=0.05, length=1.2)
        .tone(0.6, 90, 40, exp(9), start=0.05)
        .saturate(1.8)
        .space(0.5, 1.2)
        .write("shot_rail")
    )
    (  # Rocket launch: ignition pop, roaring exhaust with flutter, tail.
        Sig(1.3, 5)
        .crack(0.7, ms=2)
        .noise(1.0, lambda t: ad(0.03, 2.8)(t) * (0.8 + 0.2 * math.sin(t * 90.0)), 0.12)
        .noise(0.4, ad(0.02, 6), 0.6, 0.2)
        .tone(0.6, 70, 45, exp(5))
        .saturate(1.6)
        .space(0.4, 1.1)
        .write("shot_rocket")
    )
    (  # Grenade launcher: hollow tube "thoonk" + light tail.
        Sig(0.6, 6)
        .tone(1.0, 140, 70, exp(22))
        .noise(0.5, exp(45), 0.25)
        .modes(0.12, 300, (1.0, 2.1, 3.3), 25.0, length=0.3)
        .saturate(1.5)
        .space(0.3, 0.8)
        .write("shot_grenade")
    )
    # --- AXIOM ------------------------------------------------------------
    (  # Energy bolt: descending zap with a hiss (sci-fi by nature).
        Sig(0.35, 7)
        .tone(1.0, 1500, 360, exp(9), shape="square")
        .noise(0.25, exp(20), 0.8, 0.4)
        .space(0.2, 0.7)
        .write("shot_bolt")
    )
    (  # Droid death: spark crackle, metal clang, thud, power-down.
        Sig(1.2, 8)
        .clicks(0.8, 40, 0.0, 0.35, 6)
        .modes(0.5, 410, METAL, 9.0, length=0.8)
        .tone(0.8, 120, 50, exp(14))
        .tone(0.25, 900, 120, exp(3.5), length=0.6, shape="square")
        .noise(0.4, exp(12), 0.3)
        .saturate(1.5)
        .space(0.35, 1.0)
        .write("droid_death")
    )
    # --- World ------------------------------------------------------------
    (  # Explosion: crack, deep boom, sub, debris rain, long street tail.
        Sig(2.6, 9)
        .crack(1.0, ms=3)
        .noise(1.2, ad(0.005, 4.5), 0.06)
        .noise(0.6, ad(0.01, 9.0), 0.35)
        .tone(1.2, 60, 28, exp(3.2))
        .saturate(2.4)
        .clicks(0.35, 90, 0.15, 1.6, 2.2)
        .space(0.55, 1.4, damp=0.5)
        .write("explosion")
    )
    (  # Round hitting a droid: sharp tick + armour-plate ring.
        Sig(0.35, 10)
        .crack(0.8, ms=1)
        .noise(0.4, exp(80), 0.9, 0.3)
        .modes(0.45, 1850, METAL, 22.0, length=0.3)
        .space(0.15, 0.6)
        .write("impact_metal")
    )
    (  # Round hitting concrete: dull thud + grit.
        Sig(0.3, 11)
        .noise(0.9, exp(45), 0.18)
        .clicks(0.35, 10, 0.0, 0.08, 25)
        .space(0.2, 0.6)
        .write("impact_world")
    )
    # --- HOLLOW / UI ---------------------------------------------------------
    (  # Dash: servo whine + air rush + footstep-like stamp.
        Sig(0.45, 12)
        .noise(0.9, lambda t: math.sin(math.pi * min(1.0, t / 0.32)) ** 2, 0.2)
        .tone(0.25, 220, 620, lambda t: math.sin(math.pi * min(1.0, t / 0.32)), shape="saw")
        .tone(0.6, 90, 50, exp(25), start=0.02)
        .lowpass(0.6)
        .write("dash")
    )
    (  # Neural Sync: heartbeat thump, slowed whoosh, chime.
        Sig(1.8, 13)
        .tone(1.0, 70, 45, exp(12))
        .tone(0.8, 70, 45, exp(12), start=0.32)
        .noise(0.5, ad(0.3, 2.0), 0.08)
        .tone(0.5, 220, 110, ad(0.1, 1.6))
        .tone(0.3, 1320, 1320, ad(0.01, 2.5), start=0.05)
        .space(0.5, 1.5, damp=0.55)
        .write("neural_sync")
    )
    (  # HOLLOW hit: heavy plate clang + thud.
        Sig(0.6, 14)
        .crack(0.6, ms=1)
        .modes(0.5, 260, METAL, 10.0, length=0.5)
        .tone(0.9, 110, 55, exp(20))
        .saturate(1.4)
        .space(0.2, 0.7)
        .write("hollow_hit")
    )
    (  # Wave start: alarm-like two-tone chime.
        Sig(0.9, 15)
        .tone(0.6, 660, 660, ad(0.01, 5))
        .tone(0.6, 990, 990, ad(0.01, 5), start=0.18)
        .space(0.35, 1.0)
        .write("wave_start")
    )
    (  # Reload: mag out click, mag in clack, charging handle.
        Sig(0.5, 16)
        .crack(0.5, ms=1)
        .modes(0.3, 2400, METAL, 40.0, length=0.08)
        .crack(0.8, start=0.17, ms=1.5)
        .modes(0.4, 1900, METAL, 35.0, start=0.17, length=0.1)
        .noise(0.3, exp(60), 0.6, 0.2, start=0.3, length=0.06)
        .crack(0.7, start=0.36, ms=1)
        .write("reload")
    )


if __name__ == "__main__":
    build()
