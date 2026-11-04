# CROOKED DOUBLE

A crooked artificial double tracker for vocals. VST3 + AU, native Apple Silicon, JUCE 8 + CMake.

It makes a second, slightly late, slightly out of tune copy of your vocal that wanders like an imperfect
tape machine and occasionally stumbles. It is an expressive artificial double, not a second performance:
it cannot change phrasing, pronunciation or breaths the way a real second take does.

## Build on your Mac (one command)

You need the Xcode Command Line Tools (the script offers to install them) and an internet connection.
CMake is downloaded automatically if you don't have it. No GitHub account needed.

```bash
bash ~/Downloads/CrookedDouble-mac-build.sh
```

The script writes this project to `~/CrookedDouble`, downloads JUCE 8.0.17, builds the arm64 VST3 and AU,
installs them to `~/Library/Audio/Plug-Ins/VST3` and `~/Library/Audio/Plug-Ins/Components`, ad-hoc signs
them and runs Apple's `auval` check. Add `--test` to also build and run the DSP and state tests.

### Manual build (if you already have the project folder)

```bash
cd ~/CrookedDouble
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release            # arm64 by default
cmake --build build --config Release -j 8                  # builds VST3 + AU and copies them into ~/Library/Audio/Plug-Ins
codesign --force --deep --sign - ~/Library/Audio/Plug-Ins/VST3/"CROOKED DOUBLE.vst3"
codesign --force --deep --sign - ~/Library/Audio/Plug-Ins/Components/"CROOKED DOUBLE.component"
killall -9 AudioComponentRegistrar 2>/dev/null; auval -v aufx Crkd Ldsa
```

Options: `-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"` for a universal build, `-DCROOKED_JUCE_DIR=/path/to/JUCE`
to use a local JUCE, `-DCROOKED_BUILD_TESTS=ON` for the test executables (`CrookedEngineTests`, `CrookedStateTests`).

## Ableton Live 12

1. Settings > Plug-Ins: turn on **Use VST3 Plug-In System Folders** (and **Use Audio Units v2** for the AU).
2. Click **Rescan** (hold Option while clicking for a full rescan if it doesn't appear).
3. Browser > Plug-Ins > **LDS Audio** > **CROOKED DOUBLE**. Drop it straight on the vocal track (not a return).
4. Use either the VST3 or the AU, not both on one track. Both save their full state in the Live Set.

## Controls

| Control | What it does |
|---|---|
| DOUBLE | Level of the artificial double. The dry lead is never turned down. Default -9 dB. Fully left = Off. |
| DISTANCE | Base delay of the double, 8 to 65 ms (default 24). Short = close and thick, long = a distinct second voice. Moving it glides like tape (small pitch bend), never jumps. |
| DRIFT | How far the double wanders in pitch and timing (three layered, bounded random curves; no sine LFO). |
| NERVES | How fast and restless the wandering is, independent of how far. |
| CROOKED | Occasional stumbles: the double lags and goes flat, or rushes and goes sharp, then recovers to exactly where it was. 0 = no events. |
| WEAR | Tape colour on the double only: soft asymmetric saturation, a gentle forward mid bell (around 1.35 kHz), low cut and a duller top (never below about 4.4 kHz). Adds no noise. |
| WIDTH | 0 = one double in the centre. Up = a second, related voice appears and the pair spreads L/R with constant power. No polarity tricks. |
| OUTPUT | Final trim of lead + double. CLIP lights when the output goes over 0 dBFS (click to clear). No limiter. |
| DOUBLE ONLY | Mutes the dry lead (smooth 25 ms fade) to audition or print the double alone. |
| POLISH / BROKEN | Polish = restrained. Broken = deeper, lopsided drift (lags further than it rushes), short tape snags, bigger stumbles. Morphs over about a second, no clicks. |
| TAPE HISS + LEVEL | Optional hiss, off by default. When off it is exact digital silence. |

The MOVEMENT window plots each wet voice's real current position: left/right = rushing or dragging versus
the DISTANCE setting, up/down = pitch in cents, red ring = a crooked event in progress, strip = stereo position.

## Presets

Default, Studio Double, Crooked John, Worn Reel, Second Take, Losing the Plot, Ghost Beside Me.
Presets leave TAPE HISS as you set it. Creative names only, not recreations of any artist's chain.

## How it works

* Dry path: input × OUTPUT. Never filtered, gated or delayed. Stereo input keeps its image.
* Wet path: mono sum of the input into one delay line read by two heads (voice A, voice B).
  4-point Hermite interpolation; delay is clamped to 2.5 to 160 ms and slew limited, so pitch movement
  can never exceed about ±50 cents and reads can never leave the buffer.
* All pitch movement comes from delay modulation. There is no separate pitch shifter, so no granular artefacts.
  Consequence: a "lean" can't be held forever; every lean is paired with a recovery that returns the double
  to its place, which is also what makes it sound like a singer correcting.
* No feedback, no repeats, zero latency reported (the doubling delay is the effect and is not compensated).
* Gains use C1 smooth two-stage ramps that land exactly on target, so DOUBLE Off + OUTPUT 0 dB is bit-identical to the input.
* Host bypass ramps to the exact input over 15 ms and back.

## Verified (on Linux, in the cloud build machine)

* Engine tests (`CrookedEngineTests`): silence in gives exactly zero out with hiss off (all rates, all
  extremes); the tail after a vocal decays to exact digital zero; DOUBLE Off + OUTPUT 0 dB is bit exact
  for mono>mono, mono>stereo and stereo>stereo, including after automating down; no latency on the dry;
  808 extreme corner renders at 44.1/48/88.2/96/192 kHz with random block sizes (1 to 2048) stay finite,
  bounded, inside the delay buffer and within the pitch limit; NaN/Inf, DC, full scale noise and impulse
  inputs stay finite and recover; random per-block automation fuzz; click detector (8 kHz+ residual)
  shows no transients for mode switching, every knob jumping min to max, DOUBLE ONLY, bypass/resume;
  mono fold-down of full width loses about 1 to 2 dB of double, L/R balance within 0.2 dB; same delay and
  pitch statistics at every sample rate; no periodic repeat in 120 s of movement; CROOKED 0 = zero events;
  hiss level calibrated and exactly silent when switched off.
* State tests (`CrookedStateTests`, real plugin code): every preset applies exactly and restores with its
  program index; 50 random settings including switches restore exactly; garbage state is ignored; bus
  layouts; processing at 44.1 to 96 kHz in every layout; editor builds and renders.
* pluginval 1.0.4 at strictness 10 on the Linux VST3: pass (state, programs, automation, fuzz,
  thread safety, editor, sample rates 44.1 to 96 kHz, block sizes 32 to 2048).

## Not verified yet (needs your Mac and ears)

* The macOS build itself: it could not be compiled here (no macOS SDK in the cloud machine).
* The AU (auval runs at the end of the build script) and loading in Live 12.
* How it actually sounds on your vocals. Numbers say the movement is bounded and non-repeating; only listening says it is musical.
* CPU use on Apple Silicon (expected to be low: two read heads and a few filters per sample).

## Limitations

* The double is built from the mono sum, so a stereo source's double is not stereo-imaged like the source
  (the dry image is untouched). Anti-phase stereo content cancels in the double.
* Large fast DISTANCE moves glide over up to about 2 s with a pitch bend (by design, no jumps).
* No independent formant or pitch processing, so it can't make the double sound like a different singer.
