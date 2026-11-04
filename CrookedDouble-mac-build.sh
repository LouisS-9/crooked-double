#!/bin/bash
# CROOKED DOUBLE - one-shot macOS build + install (native Apple Silicon VST3 and AU)
#
#   bash CrookedDouble-mac-build.sh            build and install
#   bash CrookedDouble-mac-build.sh --test     also build and run the DSP and state tests
#   bash CrookedDouble-mac-build.sh --extract-only   just write the source project
#
# Project goes to ~/CrookedDouble (override with CROOKED_DIR=/some/path).
# Needs: macOS 11+, Xcode Command Line Tools, internet (downloads JUCE 8.0.17, and CMake if missing).
set -euo pipefail

MODE="${1:-}"
DEST="${CROOKED_DIR:-$HOME/CrookedDouble}"
say() { printf '\n==> %s\n' "$*"; }

write_sources() {
mkdir -p "$DEST/Source/dsp" "$DEST/tests"
cat > "$DEST/CMakeLists.txt" <<'CROOKED_DOUBLE_EOF'
cmake_minimum_required(VERSION 3.22)

# ---- macOS: native Apple Silicon by default (pass -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" for universal) ----
if(APPLE)
    if(NOT CMAKE_OSX_ARCHITECTURES)
        set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "" FORCE)
    endif()
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS")
endif()

project(CrookedDouble VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(CROOKED_BUILD_TESTS "Build the offline DSP and state tests" OFF)
set(CROOKED_JUCE_DIR "" CACHE PATH "Optional local JUCE checkout. Empty = download JUCE automatically")

# ---- JUCE ----
if(CROOKED_JUCE_DIR)
    add_subdirectory(${CROOKED_JUCE_DIR} JUCE)
else()
    include(FetchContent)
    if(POLICY CMP0135)
        cmake_policy(SET CMP0135 NEW)
    endif()
    FetchContent_Declare(JUCE
        GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
        GIT_TAG        8.0.17-security
        GIT_SHALLOW    TRUE
        GIT_PROGRESS   TRUE)
    FetchContent_MakeAvailable(JUCE)
endif()

# ---- plugin ----
set(CROOKED_FORMATS VST3)
if(APPLE)
    list(APPEND CROOKED_FORMATS AU)
endif()

juce_add_plugin(CrookedDouble
    PRODUCT_NAME "CROOKED DOUBLE"
    COMPANY_NAME "LDS Audio"
    BUNDLE_ID "com.ldsaudio.crookeddouble"
    VERSION ${PROJECT_VERSION}
    PLUGIN_MANUFACTURER_CODE Ldsa
    PLUGIN_CODE Crkd
    FORMATS ${CROOKED_FORMATS}
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    VST3_CATEGORIES Fx Delay
    AU_MAIN_TYPE kAudioUnitType_Effect
    DESCRIPTION "Crooked artificial double tracking for vocals"
    COPY_PLUGIN_AFTER_BUILD ${APPLE})

set(CROOKED_SOURCES
    Source/dsp/CrookedEngine.cpp
    Source/PluginProcessor.cpp
    Source/PluginEditor.cpp)

target_sources(CrookedDouble PRIVATE ${CROOKED_SOURCES})
target_include_directories(CrookedDouble PRIVATE Source)

target_compile_definitions(CrookedDouble PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_REPORT_APP_USAGE=0)

target_link_libraries(CrookedDouble
    PRIVATE
        juce::juce_audio_utils
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)

# ---- tests ----
if(CROOKED_BUILD_TESTS)
    add_executable(CrookedEngineTests tests/EngineTests.cpp Source/dsp/CrookedEngine.cpp)
    target_include_directories(CrookedEngineTests PRIVATE Source)

    juce_add_console_app(CrookedStateTests PRODUCT_NAME "CrookedStateTests")
    target_sources(CrookedStateTests PRIVATE tests/StateTests.cpp ${CROOKED_SOURCES})
    target_include_directories(CrookedStateTests PRIVATE Source)
    target_compile_definitions(CrookedStateTests PRIVATE JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0 JUCE_MODAL_LOOPS_PERMITTED=1)
    target_link_libraries(CrookedStateTests PRIVATE juce::juce_audio_utils juce::juce_recommended_config_flags)
endif()
CROOKED_DOUBLE_EOF
cat > "$DEST/README.md" <<'CROOKED_DOUBLE_EOF'
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
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/dsp/DspUtils.h" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - small real-time-safe DSP building blocks (no JUCE dependency)
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace cd
{
constexpr float  kPi  = 3.14159265358979323846f;
constexpr double kPiD = 3.14159265358979323846;

inline float clampf (float v, float lo, float hi) noexcept { return std::min (hi, std::max (lo, v)); }
inline float lerpf (float a, float b, float t) noexcept   { return a + (b - a) * t; }
inline float dbToGain (float db) noexcept                 { return std::pow (10.0f, db * 0.05f); }
inline float smoothstep01 (float x) noexcept              { x = clampf (x, 0.0f, 1.0f); return x * x * (3.0f - 2.0f * x); }

/** Flush tiny filter states so silence decays to true zero even without FTZ. */
inline void killDenormal (float& v) noexcept { if (std::abs (v) < 1.0e-20f) v = 0.0f; }

//==============================================================================
/** xorshift64* : fast, allocation free, deterministic once seeded. */
struct Rng
{
    uint64_t s = 0x9E3779B97F4A7C15ull;

    void seed (uint64_t v) noexcept
    {
        s = v ? v : 0x9E3779B97F4A7C15ull;
        for (int i = 0; i < 8; ++i) next();
    }

    uint64_t next() noexcept
    {
        s ^= s >> 12; s ^= s << 25; s ^= s >> 27;
        return s * 2685821657736338717ull;
    }

    float uni() noexcept                  { return (float) ((double) (next() >> 40) * (1.0 / 16777216.0)); } // [0,1)
    float bi() noexcept                   { return uni() * 2.0f - 1.0f; }                                    // [-1,1)
    float range (float a, float b) noexcept { return a + (b - a) * uni(); }
    float expo (float mean) noexcept      { return -mean * std::log (1.0f - 0.999999f * uni()); }
};

//==============================================================================
/** Bounded, smoothly varying random signal.
    Uniform cubic B-spline through random control points in [-1, 1]. A B-spline
    never leaves the convex hull of its control points, so the output is
    strictly bounded to [-1, 1] and is C2 continuous (no steps in value, slope
    or curvature, so no clicks and no pitch steps when it drives a delay).
    Each segment gets a random duration multiplier ("irregularity"), smoothed so
    the speed change itself is continuous. Result: wandering that never cycles. */
class SmoothRandom
{
public:
    void init (Rng& r) noexcept
    {
        for (auto& p : pts) p = r.bi();
        u = r.uni();
        mult = multTarget = 1.0f;
    }

    /** rateHz = control points per second, irregularity 0..1, multCoef = one-pole coef for speed changes */
    float tick (float rateHz, float invSr, float irregularity, float multCoef, Rng& r) noexcept
    {
        mult += (multTarget - mult) * multCoef;
        u += rateHz * mult * invSr;

        if (u >= 1.0f)
        {
            u -= 1.0f;
            if (u >= 1.0f) u = 0.0f; // only possible with absurd rates, keep bounded
            pts[0] = pts[1]; pts[1] = pts[2]; pts[2] = pts[3];
            pts[3] = r.bi();
            multTarget = std::exp2 (irregularity * 1.25f * r.bi()); // ~0.42x .. 2.4x segment speed
        }

        const float u2 = u * u, u3 = u2 * u;
        const float omu = 1.0f - u;
        const float b0 = omu * omu * omu;
        const float b1 = 3.0f * u3 - 6.0f * u2 + 4.0f;
        const float b2 = -3.0f * u3 + 3.0f * u2 + 3.0f * u + 1.0f;
        const float b3 = u3;
        value = (b0 * pts[0] + b1 * pts[1] + b2 * pts[2] + b3 * pts[3]) * (1.0f / 6.0f);
        return value;
    }

    float value = 0.0f;

private:
    float pts[4] {};
    float u = 0.0f, mult = 1.0f, multTarget = 1.0f;
};

//==============================================================================
/** One-pole parameter smoother that snaps exactly onto its target once close,
    so unity / zero gains become bit-exact. */
struct Smoother
{
    float cur = 0.0f, target = 0.0f, coef = 1.0f, snap = 1.0e-6f;

    void setTime (float seconds, double sr) noexcept
    {
        coef = seconds <= 0.0f ? 1.0f : (float) (1.0 - std::exp (-1.0 / (seconds * sr)));
    }
    void reset (float v) noexcept { cur = target = v; }
    float next() noexcept
    {
        cur += (target - cur) * coef;
        if (std::abs (target - cur) < snap) cur = target;
        return cur;
    }
    bool settled() const noexcept { return cur == target; }
};

/** Two cascaded one-poles: C1 smooth gain ramps (no corner at the start of a
    fade, so no spectral splatter), still snapping exactly onto the target. */
struct Smoother2
{
    float cur = 0.0f, target = 0.0f, s1 = 0.0f, coef = 1.0f, snap = 1.0e-6f;

    void setTime (float seconds, double sr) noexcept
    {
        coef = seconds <= 0.0f ? 1.0f : (float) (1.0 - std::exp (-2.0 / (seconds * sr)));
    }
    void reset (float v) noexcept { cur = target = s1 = v; }
    float next() noexcept
    {
        s1 += (target - s1) * coef;
        if (std::abs (target - s1) < snap) s1 = target;
        cur += (s1 - cur) * coef;
        if (std::abs (s1 - cur) < snap) cur = s1;
        return cur;
    }
};

//==============================================================================
/** Topology-preserving-transform state variable filter (Zavalishin / Simper).
    Stable under fast cutoff modulation. */
struct Svf
{
    float ic1 = 0.0f, ic2 = 0.0f;
    float a1 = 0.0f, a2 = 0.0f, a3 = 0.0f, k = 1.414f;

    void setup (float cutoffHz, float q, double sr) noexcept
    {
        cutoffHz = clampf (cutoffHz, 10.0f, (float) (sr * 0.45));
        const float g = (float) std::tan (kPiD * cutoffHz / sr);
        k  = 1.0f / q;
        a1 = 1.0f / (1.0f + g * (g + k));
        a2 = g * a1;
        a3 = g * a2;
    }

    void reset() noexcept { ic1 = ic2 = 0.0f; }

    inline void process (float x, float& lp, float& bp, float& hp) noexcept
    {
        const float v3 = x - ic2;
        const float v1 = a1 * ic1 + a2 * v3;
        const float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1;
        ic2 = 2.0f * v2 - ic2;
        lp = v2; bp = v1; hp = x - k * v1 - v2;
    }

    void flush() noexcept { killDenormal (ic1); killDenormal (ic2); }
};

//==============================================================================
/** 4-point, 3rd-order Hermite read from a power-of-two circular buffer.
    delaySamples must be >= 2 and <= size - 4 (the engine guarantees this). */
inline float readHermite (const float* buf, int mask, int writePos, double delaySamples) noexcept
{
    const double dInt = std::floor (delaySamples);
    const float  frac = (float) (delaySamples - dInt);
    const int    i    = writePos - (int) dInt - 1;  // sample just older than the read point
    const float  f    = 1.0f - frac;                // position between i and i+1

    const float xm1 = buf[(i - 1) & mask];
    const float x0  = buf[i & mask];
    const float x1  = buf[(i + 1) & mask];
    const float x2  = buf[(i + 2) & mask];

    const float c1 = 0.5f * (x1 - xm1);
    const float c2 = xm1 - 2.5f * x0 + 2.0f * x1 - 0.5f * x2;
    const float c3 = 0.5f * (x2 - xm1) + 1.5f * (x0 - x1);
    return ((c3 * f + c2) * f + c1) * f + x0;
}
} // namespace cd
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/dsp/CrookedEngine.h" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - artificial double tracking engine (no JUCE dependency)
#pragma once

#include "DspUtils.h"
#include <vector>

namespace cd
{
/** Control values as the user sees them. Set once per block; the engine smooths internally. */
struct EngineParams
{
    float doubleDb   = -9.0f;   // wet level, <= kDoubleOffDb means off
    float distanceMs = 24.0f;   // 8 .. 65
    float drift      = 0.45f;   // 0 .. 1
    float nerves     = 0.40f;   // 0 .. 1
    float crooked    = 0.15f;   // 0 .. 1
    float wear       = 0.25f;   // 0 .. 1
    float width      = 0.50f;   // 0 .. 1
    float outputDb   = 0.0f;    // -24 .. +12
    bool  doubleOnly = false;
    bool  broken     = false;
    bool  hissOn     = false;
    float hissDb     = -62.0f;  // -80 .. -36
};

constexpr float kDoubleOffDb = -60.0f;

struct VoiceView
{
    float delayMs    = 0.0f;  // actual current read delay
    float baseMs     = 0.0f;  // where DISTANCE alone would put this voice
    float pitchCents = 0.0f;  // actual pitch deviation caused by the delay movement
    float pan        = 0.0f;  // -1 .. 1, effective position in the wet mix
    float gain       = 0.0f;  // effective share of the wet mix 0..1
    float crooked    = 0.0f;  // 0..1 envelope of any crooked event in progress
};

struct EngineView
{
    VoiceView voice[2];
    float wetGain    = 0.0f;  // linear
    float peakOut    = 0.0f;  // block peak, absolute
};

/** Diagnostics for the offline tests. Reset with resetStats(). */
struct EngineStats
{
    double minDelaySamples = 1.0e9, maxDelaySamples = 0.0;
    double maxSlew = 0.0;          // max |d delay / d t| in samples per sample
    int    nonFiniteEvents = 0;
    int    eventsStarted = 0;
};

class CrookedEngine
{
public:
    CrookedEngine();

    /** Allocates. Call from prepareToPlay only. */
    void prepare (double sampleRate, int maxBlockSize);
    /** Clears state, no allocation. */
    void reset();
    /** Deterministic randomness (tests). Plugin instances seed from a random device. */
    void setSeed (uint64_t seed);

    void setParams (const EngineParams& p) noexcept { params = p; }

    /** inR may be nullptr (mono in). outR may be nullptr (mono out).
        In-place processing (in == out) is supported. */
    void process (const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept;

    /** Host bypass: keeps everything running, ramps (15 ms) to the exact untouched input,
        and ramps back when process() is called again. No clicks either way. */
    void processBypassed (const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept;

    const EngineView&  view() const noexcept  { return lastView; }
    const EngineStats& stats() const noexcept { return st; }
    void resetStats() noexcept { st = EngineStats{}; }

    static constexpr double kMinDelaySec = 0.0025;
    static constexpr double kMaxDelaySec = 0.160;
    /** Max delay slope in samples/sample: bounds every pitch excursion to about +-50 cents. */
    static constexpr double kMaxSlew = 0.029;

private:
    struct LeanEvent
    {
        bool   active = false;
        float  t = 0.0f, T1 = 0.0f, T2 = 0.0f, alpha = 0.7f;
        float  c1 = 0.0f, c2 = 0.0f;   // delay slopes (s/s) for lean and recovery
        float  peak = 1.0e-6f;          // |max offset| in s, for the envelope
        double offset = 0.0;            // seconds of extra delay
        float  timer = 1.0f;            // seconds until next event may start
    };

    struct Snag
    {
        bool  active = false;
        float t = 0.0f, T = 0.1f, depth = 0.0f; // depth in seconds
        float offset = 0.0f;
        float timer = 2.0f;
    };

    struct Voice
    {
        Rng rng;
        SmoothRandom own[3], tone, toneGain, flutAmp, flutFreq, flutFast;
        double flutPhase = 0.0;
        double delay = 0.0, prevDelay = 0.0;     // samples
        LeanEvent ev;
        Snag snag;
        Svf hp, bell, lp;
        float dcX = 0.0f, dcY = 0.0f;
        float pitchView = 0.0f;
        float lastEnv = 0.0f;
        float out = 0.0f;
        float bellG = 0.0f;
    };

    bool startLean (Voice& v, float crooked, float m, float baseSec, float scale, int forcedSign);
    float tickVoice (Voice& v, int index, float in, float baseSec);
    void updateTone (Voice& v);
    void snapSmoothers();
    void pushInput (float mono) noexcept;

    EngineParams params;
    double sr = 48000.0;
    float  invSr = 1.0f / 48000.0f;
    std::vector<float> buffer;
    int mask = 0, writePos = 0;
    double maxDelaySamples = 0.0, minDelaySamples = 0.0;

    Rng sharedRng, hissRng;
    SmoothRandom shared[2];
    Voice voices[2];

    Smoother2 sWet, sDry, sOut, sHiss, sByp;
    Smoother sWidth, sDist, sDrift, sNerves, sCrooked, sWear, sMode;
    float bypassTarget = 0.0f;
    void run (const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept;
    float multCoef = 0.001f, pitchCoef = 0.01f, dcCoef = 0.999f;
    float warm = 1.0f, warmInc = 0.0f;
    float curNf = 1.0f, curIrr = 0.5f;
    bool  partnerTrigger = false;
    float lastWidth = -1.0f;
    float cache[4] { 1.0f, 1.0f, 0.0f, 0.0f }, cachePan[2] {}, cacheG[2] { 1.0f, 0.0f };
    static constexpr float kHissNorm = 2.16f;
    int   toneCounter = 0;
    bool  needsReset = false;

    // pink noise state (Paul Kellet economy) per channel
    float pk[2][3] {};

    EngineView  lastView;
    EngineStats st;
};
} // namespace cd
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/dsp/CrookedEngine.cpp" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - artificial double tracking engine
#include "CrookedEngine.h"

namespace cd
{
namespace
{
    constexpr float kSqrt2 = 1.41421356237f;

    /** Tukey window on [0, T]: raised-cosine tapers, flat middle. Area = T * (1 - alpha / 2). */
    inline float tukey (float t, float T, float alpha) noexcept
    {
        const float edge = 0.5f * alpha * T;
        if (edge <= 0.0f) return 1.0f;
        if (t < edge)     return 0.5f * (1.0f - std::cos (kPi * t / edge));
        if (t > T - edge) return 0.5f * (1.0f - std::cos (kPi * (T - t) / edge));
        return 1.0f;
    }

    inline void panGains (float p, float& l, float& r) noexcept
    {
        // constant power, scaled so the centre is unity in each channel
        const float a = (p + 1.0f) * 0.25f * kPi;
        l = kSqrt2 * std::cos (a);
        r = kSqrt2 * std::sin (a);
    }

    inline size_t nextPow2 (size_t v) { size_t p = 1; while (p < v) p <<= 1; return p; }
}

CrookedEngine::CrookedEngine()
{
    setSeed (0xC800CEDull);
    prepare (48000.0, 512);
}

void CrookedEngine::setSeed (uint64_t seed)
{
    sharedRng.seed (seed);
    voices[0].rng.seed (seed * 31u + 7u);
    voices[1].rng.seed (seed * 131u + 11u);
    hissRng.seed (seed ^ 0xABCDEF12345ull);

    for (auto& s : shared) s.init (sharedRng);
    for (auto& v : voices)
    {
        for (auto& o : v.own) o.init (v.rng);
        v.tone.init (v.rng); v.toneGain.init (v.rng);
        v.flutAmp.init (v.rng); v.flutFreq.init (v.rng); v.flutFast.init (v.rng);
        v.flutPhase = v.rng.uni();
    }
}

void CrookedEngine::prepare (double sampleRate, int /*maxBlockSize*/)
{
    sr    = sampleRate > 1000.0 ? sampleRate : 48000.0;
    invSr = (float) (1.0 / sr);

    const size_t size = nextPow2 ((size_t) std::ceil (sr * kMaxDelaySec) + 64);
    buffer.assign (size, 0.0f);
    mask = (int) size - 1;
    maxDelaySamples = std::min (kMaxDelaySec * sr, (double) size - 8.0);
    minDelaySamples = kMinDelaySec * sr;

    sWet.setTime (0.040f, sr);
    sDry.setTime (0.025f, sr);
    sOut.setTime (0.030f, sr);
    sWidth.setTime (0.120f, sr);
    sDist.setTime (0.300f, sr);   sDist.snap = 1.0e-8f;
    sDrift.setTime (0.250f, sr);
    sNerves.setTime (0.350f, sr);
    sCrooked.setTime (0.200f, sr);
    sWear.setTime (0.150f, sr);
    sMode.setTime (0.600f, sr);
    sHiss.setTime (0.050f, sr);   sHiss.snap = 1.0e-7f;
    sByp.setTime (0.015f, sr);

    multCoef  = (float) (1.0 - std::exp (-2.0 * kPiD * 2.5 / sr));
    pitchCoef = (float) (1.0 - std::exp (-1.0 / (0.03 * sr)));
    warmInc   = (float) (1.0 / (0.15 * sr));

    reset();
}

void CrookedEngine::snapSmoothers()
{
    const auto& p = params;
    sWet.reset (p.doubleDb <= kDoubleOffDb + 0.01f ? 0.0f : dbToGain (p.doubleDb));
    sDry.reset (p.doubleOnly ? 0.0f : 1.0f);
    sOut.reset (dbToGain (p.outputDb));
    sWidth.reset (clampf (p.width, 0.0f, 1.0f));
    sDist.reset (clampf (p.distanceMs, 8.0f, 65.0f) * 0.001f);
    sDrift.reset (clampf (p.drift, 0.0f, 1.0f));
    sNerves.reset (clampf (p.nerves, 0.0f, 1.0f));
    sCrooked.reset (clampf (p.crooked, 0.0f, 1.0f));
    sWear.reset (clampf (p.wear, 0.0f, 1.0f));
    sMode.reset (p.broken ? 1.0f : 0.0f);
    sHiss.reset (p.hissOn ? dbToGain (clampf (p.hissDb, -80.0f, -36.0f)) : 0.0f);
    sByp.reset (bypassTarget);
}

void CrookedEngine::reset()
{
    std::fill (buffer.begin(), buffer.end(), 0.0f);
    writePos = 0;
    snapSmoothers();

    for (auto& v : voices)
    {
        v.delay = v.prevDelay = -1.0;  // < 0 means "snap to target on next sample"
        v.ev = LeanEvent{};
        v.ev.timer = v.rng.range (0.6f, 3.0f);
        v.snag = Snag{};
        v.snag.timer = v.rng.range (0.5f, 2.5f);
        v.hp.reset(); v.bell.reset(); v.lp.reset();
        v.pitchView = 0.0f; v.lastEnv = 0.0f; v.out = 0.0f;
        updateTone (v);
    }

    for (auto& ch : pk) for (auto& s : ch) s = 0.0f;
    warm = 0.0f;
    toneCounter = 0;
    lastWidth = -1.0f;
    needsReset = false;
}

void CrookedEngine::pushInput (float mono) noexcept
{
    writePos = (writePos + 1) & mask;
    buffer[(size_t) writePos] = std::isfinite (mono) ? mono : 0.0f;
}

//==============================================================================
bool CrookedEngine::startLean (Voice& v, float crooked, float m, float baseSec, float scale, int forcedSign)
{
    auto& e = v.ev;
    int sign = forcedSign != 0 ? forcedSign : (v.rng.uni() < 0.60f + 0.12f * m ? 1 : -1);

    const float cents = v.rng.range (0.45f, 1.0f)
                      * (lerpf (3.0f, 5.0f, m) + crooked * lerpf (20.0f, 35.0f, m)) * scale;

    e.T1    = v.rng.range (0.18f, 0.70f) * (1.0f + 0.3f * m);
    e.T2    = e.T1 * v.rng.range (1.3f, 2.6f);
    e.alpha = v.rng.range (0.5f, 0.9f);

    float slope = 1.0f - std::exp2 (-cents / 1200.0f);     // delay slope for "late and flat"
    const float areaFactor = e.T1 * (1.0f - 0.5f * e.alpha);

    if (sign < 0)
    {
        // rushing ahead: the double can't get closer than the safe minimum
        const float room = 0.45f * std::max (0.0f, baseSec - (float) kMinDelaySec - 0.001f);
        if (room < 0.0003f) sign = 1;
        else slope = std::min (slope, room / areaFactor);
    }
    if (sign > 0)
        slope = std::min (slope, 0.018f / areaFactor);

    e.c1     = slope * (float) sign;
    e.c2     = e.c1 * e.T1 / e.T2;     // recovery returns exactly the same distance
    e.peak   = std::max (1.0e-6f, slope * areaFactor);
    e.t      = 0.0f;
    e.offset = 0.0;
    e.active = true;
    ++st.eventsStarted;
    return true;
}

void CrookedEngine::updateTone (Voice& v)
{
    const float wear = sWear.cur;
    const float gate = smoothstep01 (sCrooked.cur * 12.0f);
    const float tr   = v.tone.value;

    v.hp.setup (85.0f + 120.0f * wear, 0.70f, sr);
    v.bell.setup (1350.0f * (1.0f + 0.10f * tr), 0.80f, sr);
    v.bellG = dbToGain (3.0f * std::min (1.0f, wear * 2.0f)) - 1.0f;

    const float lpHz = 16000.0f * std::exp2 (-1.85f * std::pow (wear, 1.15f))
                     * (1.0f + 0.15f * wear * tr)
                     * (1.0f - 0.30f * v.lastEnv * gate);
    v.lp.setup (lpHz, 0.68f, sr);
}

float CrookedEngine::tickVoice (Voice& v, int index, float /*unused*/, float baseSec)
{
    const float m       = sMode.cur;
    const float drift   = sDrift.cur;
    const float nerves  = sNerves.cur;
    const float crooked = sCrooked.cur;
    const float wear    = sWear.cur;
    const float gate    = smoothstep01 (crooked * 12.0f);
    const float jitter  = index == 0 ? 1.0f : 1.13f;

    // ---- slow, multi timescale drift (bounded random splines) ----
    const float L0 = 0.65f * shared[0].value + 0.76f * v.own[0].tick (0.22f * curNf * jitter, invSr, curIrr, multCoef, v.rng);
    const float L1 = 0.65f * shared[1].value + 0.76f * v.own[1].tick (0.75f * curNf * jitter, invSr, curIrr, multCoef, v.rng);
    const float L2 = v.own[2].tick (2.60f * curNf * jitter, invSr, curIrr, multCoef, v.rng);

    const float depthScale = (0.04f + 0.96f * drift) * (1.0f + 0.6f * m);
    const float maxAbs     = depthScale * ((2.4f + 2.0f) * 1.41f + 1.3f) + 1.0e-6f;
    float driftMs = depthScale * (2.4f * L0 + 2.0f * L1 + 1.3f * L2);
    const float x = driftMs / maxAbs;
    driftMs += 0.30f * m * x * x * maxAbs;   // Broken: lags further than it rushes

    // ---- flutter: quasi periodic capstan wobble + fast random scrape ----
    const float flutHz = (4.6f + 3.2f * nerves) * (1.0f + 0.12f * v.flutFreq.tick (0.4f, invSr, 0.5f, multCoef, v.rng));
    v.flutPhase += flutHz * invSr;
    if (v.flutPhase >= 1.0) v.flutPhase -= 1.0;
    const float amp  = 0.65f + 0.35f * v.flutAmp.tick (0.9f, invSr, 0.6f, multCoef, v.rng);
    const float fast = v.flutFast.tick (14.0f * (0.7f + 0.6f * nerves), invSr, 0.7f, multCoef, v.rng);
    const float flutDepthMs = 0.010f + 0.032f * wear + 0.012f * drift + 0.025f * m;
    const float flutterMs   = flutDepthMs * (amp * std::sin (2.0f * kPi * (float) v.flutPhase) + 0.45f * fast);

    // ---- crooked lean events ----
    auto& e = v.ev;
    if (! e.active)
    {
        e.timer -= invSr;
        if (e.timer <= 0.0f)
        {
            if (crooked > 0.001f && gate > 0.01f)
            {
                startLean (v, crooked, m, baseSec, 1.0f, 0);
                if (index == 0) partnerTrigger = true;
            }
            else
                e.timer = 0.5f;
        }
    }
    else
    {
        e.t += invSr;
        float s = 0.0f;
        if (e.t < e.T1)              s =  e.c1 * tukey (e.t, e.T1, e.alpha);
        else if (e.t < e.T1 + e.T2)  s = -e.c2 * tukey (e.t - e.T1, e.T2, e.alpha);
        else
        {
            e.active = false;
            e.offset = 0.0;  // residual is ~1e-12 s, snapping is inaudible
            const float mean = lerpf (16.0f, 2.0f, std::pow (crooked, 0.6f)) * (1.0f - 0.35f * m);
            e.timer = 0.4f + v.rng.expo (mean);
        }
        e.offset += (double) s * (double) invSr;
    }

    // ---- Broken only: short tape snags ----
    auto& sg = v.snag;
    if (! sg.active)
    {
        sg.timer -= invSr;
        if (sg.timer <= 0.0f)
        {
            if (m > 0.02f && crooked > 0.001f)
            {
                sg.T     = v.rng.range (0.07f, 0.20f);
                sg.depth = std::min (v.rng.range (0.00015f, 0.0005f) * (0.5f + crooked),
                                     0.012f * sg.T / kPi);
                sg.t = 0.0f; sg.active = true;
            }
            sg.timer = 0.2f + v.rng.expo (lerpf (6.0f, 1.2f, crooked) / std::max (m, 0.1f));
        }
    }
    else
    {
        sg.t += invSr;
        if (sg.t >= sg.T) { sg.active = false; sg.offset = 0.0f; }
        else sg.offset = sg.depth * 0.5f * (1.0f - std::cos (2.0f * kPi * sg.t / sg.T));
    }

    // ---- total delay, clamped and slew limited ----
    const double targetSec = (double) baseSec
                           + 0.001 * (double) (driftMs + flutterMs)
                           + (double) gate * e.offset
                           + (double) (m * sg.offset);
    const double target = std::min (maxDelaySamples, std::max (minDelaySamples, targetSec * sr));

    if (v.delay < 0.0)
        v.delay = v.prevDelay = target;
    else
        v.delay += std::min (kMaxSlew, std::max (-kMaxSlew, target - v.delay));

    const double slope = v.delay - v.prevDelay;
    v.prevDelay = v.delay;

    st.minDelaySamples = std::min (st.minDelaySamples, v.delay);
    st.maxDelaySamples = std::max (st.maxDelaySamples, v.delay);
    st.maxSlew         = std::max (st.maxSlew, std::abs (slope));

    const float cents = 1200.0f * std::log2 ((float) std::max (0.5, 1.0 - slope));
    v.pitchView += (cents - v.pitchView) * pitchCoef;

    // ---- read and colour ----
    float y = readHermite (buffer.data(), mask, writePos, v.delay);

    float lp, bp, hp;
    v.bell.process (y, lp, bp, hp);
    y += v.bellG * v.bell.k * bp;                    // gentle nasal / forward bell

    const float satMix = smoothstep01 (wear * 3.0f);
    if (satMix > 0.0f)
    {
        const float drive = 1.0f + 3.2f * std::pow (wear, 1.2f) + 0.6f * m * wear;
        const float bias  = 0.15f * wear;
        const float tb    = std::tanh (bias);
        const float s     = (std::tanh (drive * y + bias) - tb) / (drive * (1.0f - tb * tb));
        y += satMix * (s - y);                       // unity small-signal gain, soft peaks
    }

    v.hp.process (y, lp, bp, hp);  y = hp;           // keeps the double out of the mud, removes bias DC
    v.lp.process (y, lp, bp, hp);  y = lp;           // tape softening

    const float env = e.active ? (float) std::min (1.0, std::abs (e.offset) / (double) e.peak) : 0.0f;
    v.lastEnv = std::max (env, sg.active ? (float) (m * sg.offset / std::max (sg.depth, 1.0e-6f)) * 0.5f : 0.0f);

    const float sag    = 1.0f - crooked * (0.16f + 0.22f * m) * gate * env;   // "struggling to keep up"
    const float uneven = 1.0f + 0.07f * wear * v.toneGain.value;
    v.out = y * sag * uneven;
    return v.out;
}

//==============================================================================
void CrookedEngine::process (const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept
{
    bypassTarget = 0.0f;
    run (inL, inR, outL, outR, numSamples);
}

void CrookedEngine::processBypassed (const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept
{
    bypassTarget = 1.0f;
    run (inL, inR, outL, outR, numSamples);
}

void CrookedEngine::run (const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept
{
    if (needsReset) reset();

    const auto& p = params;
    sWet.target     = p.doubleDb <= kDoubleOffDb + 0.01f ? 0.0f : dbToGain (clampf (p.doubleDb, kDoubleOffDb, 6.0f));
    sDry.target     = p.doubleOnly ? 0.0f : 1.0f;
    sOut.target     = dbToGain (clampf (p.outputDb, -24.0f, 12.0f));
    sWidth.target   = clampf (p.width, 0.0f, 1.0f);
    sDist.target    = clampf (p.distanceMs, 8.0f, 65.0f) * 0.001f;
    sDrift.target   = clampf (p.drift, 0.0f, 1.0f);
    sNerves.target  = clampf (p.nerves, 0.0f, 1.0f);
    sCrooked.target = clampf (p.crooked, 0.0f, 1.0f);
    sWear.target    = clampf (p.wear, 0.0f, 1.0f);
    sMode.target    = p.broken ? 1.0f : 0.0f;
    sHiss.target    = p.hissOn ? dbToGain (clampf (p.hissDb, -80.0f, -36.0f)) : 0.0f;
    sByp.target     = bypassTarget;

    float peak = 0.0f;
    float gA = 1.0f, gB = 0.0f, aL = 1.0f, aR = 1.0f, bL = 1.0f, bR = 1.0f, pA = 0.0f, pB = 0.0f;

    for (int i = 0; i < numSamples; ++i)
    {
        const float l = inL[i];
        const float r = inR != nullptr ? inR[i] : l;
        pushInput (inR != nullptr ? 0.5f * (l + r) : l);

        const float byp   = sByp.next();
        const float wet   = sWet.next() * (1.0f - byp);
        const float dry   = sDry.next();
        const float outG0 = sOut.next();
        const float outG  = outG0 + (1.0f - outG0) * byp;
        const float width = sWidth.next();
        const float dist  = sDist.next();
        sDrift.next(); sNerves.next(); sCrooked.next(); sWear.next();
        const float m = sMode.next();
        const float hissG = sHiss.next() * (1.0f - byp);
        const float dryG  = dry + (1.0f - dry) * byp;

        curNf  = std::exp2 (-1.2f + 2.6f * sNerves.cur) * (1.0f + 0.25f * m);
        curIrr = 0.35f + 0.50f * sNerves.cur + 0.15f * m;
        shared[0].tick (0.22f * curNf, invSr, curIrr, multCoef, sharedRng);
        shared[1].tick (0.75f * curNf, invSr, curIrr, multCoef, sharedRng);

        if (--toneCounter <= 0)
        {
            toneCounter = 32;
            for (auto& v : voices)
            {
                v.tone.tick (0.35f, invSr * 32.0f, 0.6f, 0.2f, v.rng);
                v.toneGain.tick (0.25f, invSr * 32.0f, 0.6f, 0.2f, v.rng);
                updateTone (v);
            }
        }

        const float a = tickVoice (voices[0], 0, 0.0f, dist);
        if (partnerTrigger)
        {
            partnerTrigger = false;
            if (! voices[1].ev.active && voices[1].rng.uni() < 0.25f)
                startLean (voices[1], sCrooked.cur, m, dist * 1.12f + 0.0012f, voices[1].rng.range (0.5f, 0.9f),
                           voices[0].ev.c1 >= 0.0f ? 1 : -1);
        }
        const float b = tickVoice (voices[1], 1, 0.0f, dist * 1.12f + 0.0012f);

        // ---- width: A centred alone at 0, B emerges and the pair spreads ----
        if (width != lastWidth)
        {
            lastWidth = width;
            const float th = width * 0.25f * kPi;
            gA = std::cos (th); gB = std::sin (th);
            const float t2 = (gB * gB) / std::max (gA * gA, 1.0e-6f);
            pB = 0.9f * width;
            pA = -pB * t2;     // energy balanced image at every width
            panGains (pA, aL, aR);
            panGains (pB, bL, bR);
            cache[0] = gA * aL; cache[1] = gA * aR; cache[2] = gB * bL; cache[3] = gB * bR;
            cachePan[0] = pA; cachePan[1] = pB; cacheG[0] = gA; cacheG[1] = gB;
        }

        if (warm < 1.0f) warm = std::min (1.0f, warm + warmInc);
        const float wg = wet * warm * warm;

        float yL, yR;
        if (outR != nullptr)
        {
            yL = l * dryG + wg * (cache[0] * a + cache[2] * b);
            yR = r * dryG + wg * (cache[1] * a + cache[3] * b);
        }
        else
        {
            yL = l * dryG + wg * a;   // mono out: one centred double, no inter-voice combing
            yR = yL;
        }

        if (hissG > 0.0f)
        {
            float n[2];
            for (int c = 0; c < 2; ++c)
            {
                const float white = hissRng.bi();
                auto& s = pk[c];
                s[0] = 0.99765f * s[0] + white * 0.0990460f;
                s[1] = 0.96300f * s[1] + white * 0.2965164f;
                s[2] = 0.57000f * s[2] + white * 1.0526913f;
                const float pink = s[0] + s[1] + s[2] + white * 0.1848f;
                n[c] = (0.55f * white + 0.12f * pink) * kHissNorm;
            }
            const float wr  = width;
            const float nrm = 1.0f / std::sqrt ((1.0f - wr) * (1.0f - wr) + wr * wr);
            yL += hissG * n[0];
            yR += hissG * (outR != nullptr ? ((1.0f - wr) * n[0] + wr * n[1]) * nrm : n[0]);
        }

        yL *= outG;
        yR *= outG;

        if (! (std::isfinite (yL) && std::isfinite (yR)))
        {
            yL = yR = 0.0f;
            ++st.nonFiniteEvents;
            needsReset = true;
        }
        yL = clampf (yL, -32.0f, 32.0f);   // last-resort rail at +30 dBFS, never reached in normal use
        yR = clampf (yR, -32.0f, 32.0f);

        peak = std::max (peak, std::max (std::abs (yL), std::abs (yR)));
        outL[i] = yL;
        if (outR != nullptr) outR[i] = yR;
    }

    for (auto& v : voices) { v.hp.flush(); v.bell.flush(); v.lp.flush(); }
    for (auto& ch : pk) for (auto& s : ch) killDenormal (s);

    for (int k = 0; k < 2; ++k)
    {
        auto& v  = voices[k];
        auto& vv = lastView.voice[k];
        vv.delayMs    = (float) (std::max (0.0, v.delay) / sr * 1000.0);
        vv.pitchCents = v.pitchView;
        vv.baseMs     = (k == 0 ? sDist.cur : sDist.cur * 1.12f + 0.0012f) * 1000.0f;
        vv.pan        = outR != nullptr ? cachePan[k] : 0.0f;
        vv.gain       = outR != nullptr ? cacheG[k] : (k == 0 ? 1.0f : 0.0f);
        vv.crooked    = v.lastEnv;
    }
    lastView.wetGain = sWet.cur * warm * warm;
    lastView.peakOut = peak;
}

} // namespace cd
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/Parameters.h" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - parameter IDs, ranges and factory presets
#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include "dsp/CrookedEngine.h"

namespace ids
{
    // Stable IDs: never rename, automation and saved sets depend on them.
    inline constexpr const char* doubleLevel = "double";
    inline constexpr const char* distance    = "distance";
    inline constexpr const char* drift       = "drift";
    inline constexpr const char* nerves      = "nerves";
    inline constexpr const char* crooked     = "crooked";
    inline constexpr const char* wear        = "wear";
    inline constexpr const char* width       = "width";
    inline constexpr const char* output      = "output";
    inline constexpr const char* doubleOnly  = "doubleOnly";
    inline constexpr const char* mode        = "mode";
    inline constexpr const char* hiss        = "hiss";
    inline constexpr const char* hissLevel   = "hissLevel";
}

namespace params
{
    inline juce::String dbText (float v, int)
    {
        if (v <= cd::kDoubleOffDb + 0.05f) return "Off";
        return (v > 0.0f ? "+" : "") + juce::String (v, 1) + " dB";
    }

    inline juce::AudioProcessorValueTreeState::ParameterLayout createLayout()
    {
        using namespace juce;
        AudioProcessorValueTreeState::ParameterLayout layout;

        auto pct = [] (float v, int) { return String (roundToInt (v)) + "%"; };
        auto pctIn = [] (const String& t) { return t.retainCharacters ("-0123456789.").getFloatValue(); };
        auto dbIn = [] (const String& t) { return t.trim().equalsIgnoreCase ("off") ? cd::kDoubleOffDb : t.retainCharacters ("-+0123456789.").getFloatValue(); };

        NormalisableRange<float> dblRange (cd::kDoubleOffDb, 3.0f, 0.1f);
        dblRange.setSkewForCentre (-12.0f);
        layout.add (std::make_unique<AudioParameterFloat> (ParameterID { ids::doubleLevel, 1 }, "Double", dblRange, -9.0f,
                        AudioParameterFloatAttributes().withLabel ("dB").withStringFromValueFunction (dbText).withValueFromStringFunction (dbIn)));

        NormalisableRange<float> distRange (8.0f, 65.0f, 0.1f);
        distRange.setSkewForCentre (24.0f);
        layout.add (std::make_unique<AudioParameterFloat> (ParameterID { ids::distance, 1 }, "Distance", distRange, 24.0f,
                        AudioParameterFloatAttributes().withLabel ("ms")
                            .withStringFromValueFunction ([] (float v, int) { return String (v, 1) + " ms"; })
                            .withValueFromStringFunction (pctIn)));

        auto addPct = [&] (const char* id, const char* name, float def)
        {
            layout.add (std::make_unique<AudioParameterFloat> (ParameterID { id, 1 }, name, NormalisableRange<float> (0.0f, 100.0f, 0.1f), def,
                            AudioParameterFloatAttributes().withLabel ("%").withStringFromValueFunction (pct).withValueFromStringFunction (pctIn)));
        };
        addPct (ids::drift,   "Drift",   45.0f);
        addPct (ids::nerves,  "Nerves",  40.0f);
        addPct (ids::crooked, "Crooked", 15.0f);
        addPct (ids::wear,    "Wear",    25.0f);
        addPct (ids::width,   "Width",   50.0f);

        layout.add (std::make_unique<AudioParameterFloat> (ParameterID { ids::output, 1 }, "Output", NormalisableRange<float> (-24.0f, 12.0f, 0.1f), 0.0f,
                        AudioParameterFloatAttributes().withLabel ("dB")
                            .withStringFromValueFunction ([] (float v, int) { return (v > 0.0f ? "+" : "") + String (v, 1) + " dB"; })
                            .withValueFromStringFunction (dbIn)));

        layout.add (std::make_unique<AudioParameterBool>   (ParameterID { ids::doubleOnly, 1 }, "Double Only", false));
        layout.add (std::make_unique<AudioParameterChoice> (ParameterID { ids::mode, 1 }, "Mode", StringArray { "Polish", "Broken" }, 0));
        layout.add (std::make_unique<AudioParameterBool>   (ParameterID { ids::hiss, 1 }, "Tape Hiss", false));
        layout.add (std::make_unique<AudioParameterFloat>  (ParameterID { ids::hissLevel, 1 }, "Hiss Level", NormalisableRange<float> (-80.0f, -36.0f, 0.1f), -62.0f,
                        AudioParameterFloatAttributes().withLabel ("dB")
                            .withStringFromValueFunction ([] (float v, int) { return String (v, 1) + " dB"; })
                            .withValueFromStringFunction (dbIn)));
        return layout;
    }
}

//==============================================================================
struct Preset
{
    const char* name;
    float doubleDb, distanceMs, drift, nerves, crooked, wear, width, outputDb;
    bool  broken;
};

/** Index 0 is the init state. Values in the units the user sees (dB, ms, %). */
inline constexpr Preset kPresets[] =
{
    //  name                 double  dist  drift nerves crook wear width  out   broken
    { "Default",              -9.0f, 24.0f, 45.0f, 40.0f, 15.0f, 25.0f,  50.0f,  0.0f, false },
    { "Studio Double",       -10.0f, 18.0f, 30.0f, 35.0f,  6.0f, 15.0f,  40.0f,  0.0f, false },
    { "Crooked John",         -7.0f, 14.0f, 50.0f, 60.0f, 45.0f, 52.0f,  25.0f, -0.5f, true  },
    { "Worn Reel",            -9.0f, 30.0f, 55.0f, 15.0f, 12.0f, 80.0f,  55.0f,  0.0f, false },
    { "Second Take",          -8.0f, 48.0f, 40.0f, 45.0f, 30.0f, 30.0f,  70.0f,  0.0f, false },
    { "Losing the Plot",      -8.0f, 34.0f, 90.0f, 80.0f, 85.0f, 55.0f,  80.0f, -1.0f, true  },
    { "Ghost Beside Me",     -16.0f, 40.0f, 50.0f, 25.0f, 25.0f, 88.0f, 100.0f,  0.0f, false },
};
inline constexpr int kNumPresets = (int) (sizeof (kPresets) / sizeof (kPresets[0]));
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/PluginProcessor.h" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - plugin processor
#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include "Parameters.h"
#include <atomic>

class CrookedDoubleProcessor final : public juce::AudioProcessor
{
public:
    CrookedDoubleProcessor();
    ~CrookedDoubleProcessor() override = default;

    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override {}
    void reset() override;
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;

    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    void processBlockBypassed (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    using AudioProcessor::processBlock;
    using AudioProcessor::processBlockBypassed;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return "CROOKED DOUBLE"; }
    bool acceptsMidi() const override  { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.2; }

    int getNumPrograms() override { return kNumPresets; }
    int getCurrentProgram() override { return currentProgram.load(); }
    void setCurrentProgram (int index) override;
    const juce::String getProgramName (int index) override;
    void changeProgramName (int, const juce::String&) override {}

    void getStateInformation (juce::MemoryBlock& destData) override;
    void setStateInformation (const void* data, int sizeInBytes) override;

    juce::AudioProcessorValueTreeState apvts;

    //==============================================================================
    /** Real DSP state published once per block for the movement display. */
    struct Telemetry
    {
        std::atomic<float> delayMs[2] {}, baseMs[2] {}, pitch[2] {}, pan[2] {}, gain[2] {}, crooked[2] {};
        std::atomic<float> wetGain { 0.0f };
        std::atomic<float> peak { 0.0f };   // max since the editor last read it
    } telemetry;

private:
    cd::EngineParams readParams() const noexcept;
    void publish() noexcept;
    template <typename Fn> void runEngine (juce::AudioBuffer<float>&, Fn&&);

    cd::CrookedEngine engine;
    std::atomic<int> currentProgram { 0 };

    std::atomic<float>* pDouble = nullptr;  std::atomic<float>* pDistance = nullptr;
    std::atomic<float>* pDrift = nullptr;   std::atomic<float>* pNerves = nullptr;
    std::atomic<float>* pCrooked = nullptr; std::atomic<float>* pWear = nullptr;
    std::atomic<float>* pWidth = nullptr;   std::atomic<float>* pOutput = nullptr;
    std::atomic<float>* pDoubleOnly = nullptr; std::atomic<float>* pMode = nullptr;
    std::atomic<float>* pHiss = nullptr;    std::atomic<float>* pHissLevel = nullptr;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (CrookedDoubleProcessor)
};
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/PluginProcessor.cpp" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - plugin processor
#include "PluginProcessor.h"
#include "PluginEditor.h"

CrookedDoubleProcessor::CrookedDoubleProcessor()
    : AudioProcessor (BusesProperties()
                          .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                          .withOutput ("Output", juce::AudioChannelSet::stereo(), true)),
      apvts (*this, nullptr, "CrookedDouble", params::createLayout())
{
    pDouble     = apvts.getRawParameterValue (ids::doubleLevel);
    pDistance   = apvts.getRawParameterValue (ids::distance);
    pDrift      = apvts.getRawParameterValue (ids::drift);
    pNerves     = apvts.getRawParameterValue (ids::nerves);
    pCrooked    = apvts.getRawParameterValue (ids::crooked);
    pWear       = apvts.getRawParameterValue (ids::wear);
    pWidth      = apvts.getRawParameterValue (ids::width);
    pOutput     = apvts.getRawParameterValue (ids::output);
    pDoubleOnly = apvts.getRawParameterValue (ids::doubleOnly);
    pMode       = apvts.getRawParameterValue (ids::mode);
    pHiss       = apvts.getRawParameterValue (ids::hiss);
    pHissLevel  = apvts.getRawParameterValue (ids::hissLevel);

    // each instance wanders differently (two doubles on two tracks should not move in lockstep)
    engine.setSeed ((uint64_t) juce::Random::getSystemRandom().nextInt64() | 1u);
}

cd::EngineParams CrookedDoubleProcessor::readParams() const noexcept
{
    cd::EngineParams p;
    p.doubleDb   = pDouble->load();
    p.distanceMs = pDistance->load();
    p.drift      = pDrift->load() * 0.01f;
    p.nerves     = pNerves->load() * 0.01f;
    p.crooked    = pCrooked->load() * 0.01f;
    p.wear       = pWear->load() * 0.01f;
    p.width      = pWidth->load() * 0.01f;
    p.outputDb   = pOutput->load();
    p.doubleOnly = pDoubleOnly->load() >= 0.5f;
    p.broken     = pMode->load() >= 0.5f;
    p.hissOn     = pHiss->load() >= 0.5f;
    p.hissDb     = pHissLevel->load();
    return p;
}

void CrookedDoubleProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    setLatencySamples (0); // the doubling delay is the effect itself, never compensated
    engine.setParams (readParams());
    engine.prepare (sampleRate, samplesPerBlock);
}

void CrookedDoubleProcessor::reset()
{
    engine.setParams (readParams());
    engine.reset();
}

bool CrookedDoubleProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    const auto in  = layouts.getMainInputChannelSet();
    const auto out = layouts.getMainOutputChannelSet();
    const auto mono = juce::AudioChannelSet::mono(), stereo = juce::AudioChannelSet::stereo();

    if (out != mono && out != stereo) return false;
    if (in != mono && in != stereo)   return false;
    return in.size() <= out.size();   // mono>mono, mono>stereo, stereo>stereo
}

template <typename Fn>
void CrookedDoubleProcessor::runEngine (juce::AudioBuffer<float>& buffer, Fn&& fn)
{
    juce::ScopedNoDenormals noDenormals;

    const int numIn  = getTotalNumInputChannels();
    const int numOut = getTotalNumOutputChannels();
    const int n      = buffer.getNumSamples();

    if (numIn <= 0 || numOut <= 0 || n <= 0)
    {
        buffer.clear();
        return;
    }

    engine.setParams (readParams());

    const float* inL  = buffer.getReadPointer (0);
    const float* inR  = numIn > 1 ? buffer.getReadPointer (1) : nullptr;
    float*       outL = buffer.getWritePointer (0);
    float*       outR = numOut > 1 ? buffer.getWritePointer (1) : nullptr;

    fn (inL, inR, outL, outR, n);

    for (int ch = 2; ch < buffer.getNumChannels(); ++ch)
        buffer.clear (ch, 0, n);

    publish();
}

void CrookedDoubleProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
{
    runEngine (buffer, [this] (const float* a, const float* b, float* c, float* d, int n) { engine.process (a, b, c, d, n); });
}

void CrookedDoubleProcessor::processBlockBypassed (juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
{
    runEngine (buffer, [this] (const float* a, const float* b, float* c, float* d, int n) { engine.processBypassed (a, b, c, d, n); });
}

void CrookedDoubleProcessor::publish() noexcept
{
    const auto& v = engine.view();
    for (int k = 0; k < 2; ++k)
    {
        telemetry.delayMs[k].store (v.voice[k].delayMs, std::memory_order_relaxed);
        telemetry.baseMs[k].store (v.voice[k].baseMs, std::memory_order_relaxed);
        telemetry.pitch[k].store (v.voice[k].pitchCents, std::memory_order_relaxed);
        telemetry.pan[k].store (v.voice[k].pan, std::memory_order_relaxed);
        telemetry.gain[k].store (v.voice[k].gain, std::memory_order_relaxed);
        telemetry.crooked[k].store (v.voice[k].crooked, std::memory_order_relaxed);
    }
    telemetry.wetGain.store (v.wetGain, std::memory_order_relaxed);

    float prev = telemetry.peak.load (std::memory_order_relaxed);
    while (v.peakOut > prev && ! telemetry.peak.compare_exchange_weak (prev, v.peakOut, std::memory_order_relaxed)) {}
}

//==============================================================================
void CrookedDoubleProcessor::setCurrentProgram (int index)
{
    if (index < 0 || index >= kNumPresets) return;
    const auto& pr = kPresets[index];

    auto set = [this] (const char* id, float value)
    {
        if (auto* prm = apvts.getParameter (id))
        {
            prm->beginChangeGesture();
            prm->setValueNotifyingHost (prm->convertTo0to1 (value));
            prm->endChangeGesture();
        }
    };

    set (ids::doubleLevel, pr.doubleDb);
    set (ids::distance,    pr.distanceMs);
    set (ids::drift,       pr.drift);
    set (ids::nerves,      pr.nerves);
    set (ids::crooked,     pr.crooked);
    set (ids::wear,        pr.wear);
    set (ids::width,       pr.width);
    set (ids::output,      pr.outputDb);
    set (ids::mode,        pr.broken ? 1.0f : 0.0f);
    set (ids::doubleOnly,  0.0f);
    // tape hiss is a user preference, presets leave it alone
    currentProgram.store (index);
}

const juce::String CrookedDoubleProcessor::getProgramName (int index)
{
    return juce::isPositiveAndBelow (index, kNumPresets) ? juce::String (kPresets[index].name) : juce::String();
}

void CrookedDoubleProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    auto state = apvts.copyState();
    state.setProperty ("program", currentProgram.load(), nullptr);
    state.setProperty ("stateVersion", 1, nullptr);
    if (auto xml = state.createXml())
        copyXmlToBinary (*xml, destData);
}

void CrookedDoubleProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    auto xml = getXmlFromBinary (data, sizeInBytes);
    if (xml == nullptr || ! xml->hasTagName (apvts.state.getType()))
        return;

    auto tree = juce::ValueTree::fromXml (*xml);
    const int prog = (int) tree.getProperty ("program", 0);
    apvts.replaceState (tree);
    currentProgram.store (juce::jlimit (0, kNumPresets - 1, prog));
}

juce::AudioProcessorEditor* CrookedDoubleProcessor::createEditor()
{
    return new CrookedDoubleEditor (*this);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new CrookedDoubleProcessor();
}
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/PluginEditor.h" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - editor
#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include "PluginProcessor.h"

namespace palette
{
    const juce::Colour paper     { 0xffece4d2 };
    const juce::Colour paperDeep { 0xffddd2b9 };
    const juce::Colour charcoal  { 0xff2a2826 };
    const juce::Colour ink       { 0xff3b3834 };
    const juce::Colour inkSoft   { 0xff7a7268 };
    const juce::Colour red       { 0xffa4463a };
    const juce::Colour mustard   { 0xffbf9a3c };
    const juce::Colour olive     { 0xff7c8048 };
    const juce::Colour cream     { 0xfff6f0e2 };
}

class CrookedLookAndFeel final : public juce::LookAndFeel_V4
{
public:
    CrookedLookAndFeel();
    void drawRotarySlider (juce::Graphics&, int x, int y, int w, int h, float pos, float start, float end, juce::Slider&) override;
    void drawToggleButton (juce::Graphics&, juce::ToggleButton&, bool highlighted, bool down) override;
    void drawButtonBackground (juce::Graphics&, juce::Button&, const juce::Colour&, bool highlighted, bool down) override;
    void drawComboBox (juce::Graphics&, int w, int h, bool down, int bx, int by, int bw, int bh, juce::ComboBox&) override;
    juce::Font getComboBoxFont (juce::ComboBox&) override;
    juce::Font getTextButtonFont (juce::TextButton&, int) override;
    void positionComboBoxText (juce::ComboBox&, juce::Label&) override;
    void drawTooltip (juce::Graphics&, const juce::String&, int w, int h) override;
    juce::Rectangle<int> getTooltipBounds (const juce::String&, juce::Point<int>, juce::Rectangle<int>) override;
};

//==============================================================================
/** A labelled rotary control bound to one parameter. */
class Knob final : public juce::Component
{
public:
    Knob (juce::AudioProcessorValueTreeState&, const char* paramId, const juce::String& title, const juce::String& tip, bool large);
    void resized() override;
    void paint (juce::Graphics&) override;

    juce::Slider slider;
private:
    juce::String title;
    bool large;
    std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> attachment;
};

/** POLISH | BROKEN segmented switch bound to the choice parameter. */
class ModeSwitch final : public juce::ToggleButton
{
public:
    void paintButton (juce::Graphics&, bool highlighted, bool down) override;
};

/** Small window showing where each wet voice actually is right now. */
class MovementScope final : public juce::Component
{
public:
    explicit MovementScope (CrookedDoubleProcessor& p) : proc (p) {}
    void update();
    void paint (juce::Graphics&) override;
private:
    CrookedDoubleProcessor& proc;
    static constexpr int kTrail = 28;
    struct Pt { float timing = 0, pitch = 0; };
    Pt trail[2][kTrail] {};
    int head = 0;
    float delayMs[2] {}, pitch[2] {}, pan[2] {}, gain[2] {}, crooked[2] {}, wet = 0.0f;
};

/** Output peak meter with latching clip lamp (click to clear). */
class OutputMeter final : public juce::Component, public juce::SettableTooltipClient
{
public:
    void setPeak (float linearPeak);
    void paint (juce::Graphics&) override;
    void mouseDown (const juce::MouseEvent&) override { clipHold = 0; repaint(); }
private:
    float level = 0.0f;
    int clipHold = 0;
};

//==============================================================================
class CrookedDoubleEditor final : public juce::AudioProcessorEditor, private juce::Timer
{
public:
    explicit CrookedDoubleEditor (CrookedDoubleProcessor&);
    ~CrookedDoubleEditor() override;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    void timerCallback() override;
    void refreshPresetBox();

    CrookedDoubleProcessor& proc;
    CrookedLookAndFeel laf;
    juce::TooltipWindow tooltips { this, 600 };

    Knob kDouble, kDistance, kDrift, kNerves, kCrooked, kWear, kWidth, kOutput, kHiss;
    juce::ToggleButton doubleOnly { "DOUBLE ONLY" }, hissOn { "TAPE HISS" };
    ModeSwitch modeSwitch;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> aDoubleOnly, aHiss, aMode;

    juce::ComboBox presetBox;
    juce::TextButton prevPreset { "<" }, nextPreset { ">" };
    int shownProgram = -1;

    MovementScope scope;
    OutputMeter meter;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (CrookedDoubleEditor)
};
CROOKED_DOUBLE_EOF
cat > "$DEST/Source/PluginEditor.cpp" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - editor
#include "PluginEditor.h"

using namespace juce;

namespace
{
    Font uiFont (float size, bool bold = false, float kerning = 0.0f)
    {
        return Font (FontOptions (size, bold ? Font::bold : Font::plain)).withExtraKerningFactor (kerning);
    }

    constexpr int kW = 800, kH = 440;
}

//==============================================================================
CrookedLookAndFeel::CrookedLookAndFeel()
{
    setColour (Slider::rotarySliderFillColourId, palette::mustard);
    setColour (ComboBox::textColourId, palette::cream);
    setColour (PopupMenu::backgroundColourId, palette::charcoal);
    setColour (PopupMenu::textColourId, palette::cream);
    setColour (PopupMenu::highlightedBackgroundColourId, palette::mustard);
    setColour (PopupMenu::highlightedTextColourId, palette::charcoal);
    setColour (TextButton::textColourOffId, palette::cream);
    setColour (TextButton::textColourOnId, palette::cream);
    setColour (TooltipWindow::textColourId, palette::charcoal);
}

void CrookedLookAndFeel::drawRotarySlider (Graphics& g, int x, int y, int w, int h, float pos, float start, float end, Slider& s)
{
    const auto bounds = Rectangle<float> ((float) x, (float) y, (float) w, (float) h).reduced (2.0f);
    const float r  = jmin (bounds.getWidth(), bounds.getHeight()) * 0.5f;
    const auto  c  = bounds.getCentre();
    const float angle = start + pos * (end - start);

    // scale ticks
    g.setColour (palette::ink.withAlpha (0.35f));
    for (int i = 0; i <= 10; ++i)
    {
        const float a = start + (float) i / 10.0f * (end - start);
        const auto p1 = c.getPointOnCircumference (r * 0.97f, a);
        const auto p2 = c.getPointOnCircumference (r * (i % 5 == 0 ? 0.84f : 0.89f), a);
        g.drawLine ({ p1, p2 }, i % 5 == 0 ? 1.4f : 1.0f);
    }

    // value arc
    const float arcR = r * 0.78f;
    Path track; track.addCentredArc (c.x, c.y, arcR, arcR, 0.0f, start, end, true);
    g.setColour (palette::paperDeep);
    g.strokePath (track, PathStrokeType (3.5f, PathStrokeType::curved, PathStrokeType::rounded));
    Path val; val.addCentredArc (c.x, c.y, arcR, arcR, 0.0f, start, angle, true);
    g.setColour (s.findColour (Slider::rotarySliderFillColourId).withAlpha (s.isEnabled() ? 1.0f : 0.4f));
    g.strokePath (val, PathStrokeType (3.5f, PathStrokeType::curved, PathStrokeType::rounded));

    // knob body
    const float kr = r * 0.63f;
    ColourGradient body (palette::ink.brighter (0.15f), c.x - kr * 0.6f, c.y - kr * 0.7f,
                         palette::charcoal.darker (0.3f), c.x + kr * 0.5f, c.y + kr * 0.8f, true);
    g.setGradientFill (body);
    g.fillEllipse (c.x - kr, c.y - kr, kr * 2.0f, kr * 2.0f);
    g.setColour (palette::cream.withAlpha (0.12f));
    g.drawEllipse (c.x - kr, c.y - kr, kr * 2.0f, kr * 2.0f, 1.0f);

    // pointer
    const auto p1 = c.getPointOnCircumference (kr * 0.30f, angle);
    const auto p2 = c.getPointOnCircumference (kr * 0.90f, angle);
    g.setColour (palette::cream);
    g.drawLine ({ p1, p2 }, jmax (2.0f, r * 0.05f));
}

void CrookedLookAndFeel::drawToggleButton (Graphics& g, ToggleButton& b, bool highlighted, bool)
{
    auto r = b.getLocalBounds().toFloat().reduced (1.0f);
    const bool on = b.getToggleState();
    g.setColour (on ? palette::charcoal : palette::paperDeep.withAlpha (highlighted ? 1.0f : 0.8f));
    g.fillRoundedRectangle (r, 5.0f);
    g.setColour (palette::ink.withAlpha (on ? 0.0f : 0.35f));
    g.drawRoundedRectangle (r, 5.0f, 1.0f);

    auto lampArea = r.removeFromLeft (r.getHeight() * 0.85f);
    auto lamp = lampArea.withSizeKeepingCentre (8.0f, 8.0f).translated (2.0f, 0.0f);
    const auto lampColour = b.getProperties().getWithDefault ("lamp", "red").toString() == "mustard" ? palette::mustard : palette::red;
    g.setColour (on ? lampColour.brighter (0.25f) : palette::inkSoft.withAlpha (0.45f));
    g.fillEllipse (lamp);

    g.setColour (on ? palette::cream : palette::ink);
    g.setFont (uiFont (11.5f, true, 0.03f));
    g.drawFittedText (b.getButtonText(), r.withTrimmedRight (4.0f).toNearestInt(), Justification::centredLeft, 1, 0.9f);
}

void CrookedLookAndFeel::drawButtonBackground (Graphics& g, Button& b, const Colour&, bool highlighted, bool down)
{
    g.setColour (palette::ink.brighter (down ? 0.3f : highlighted ? 0.15f : 0.0f));
    g.fillRoundedRectangle (b.getLocalBounds().toFloat().reduced (1.0f), 4.0f);
}

Font CrookedLookAndFeel::getTextButtonFont (TextButton&, int) { return uiFont (14.0f, true); }

void CrookedLookAndFeel::drawComboBox (Graphics& g, int w, int h, bool, int, int, int, int, ComboBox& box)
{
    auto r = Rectangle<float> (0.0f, 0.0f, (float) w, (float) h).reduced (1.0f);
    g.setColour (palette::ink.brighter (box.isMouseOver (true) ? 0.12f : 0.0f));
    g.fillRoundedRectangle (r, 4.0f);
    Path arrow;
    const float ax = (float) w - 16.0f, ay = (float) h * 0.5f;
    arrow.addTriangle (ax - 4.5f, ay - 2.5f, ax + 4.5f, ay - 2.5f, ax, ay + 3.0f);
    g.setColour (palette::mustard);
    g.fillPath (arrow);
}

Font CrookedLookAndFeel::getComboBoxFont (ComboBox&) { return uiFont (14.0f, true, 0.03f); }

void CrookedLookAndFeel::positionComboBoxText (ComboBox& box, Label& label)
{
    label.setBounds (8, 1, box.getWidth() - 30, box.getHeight() - 2);
    label.setFont (getComboBoxFont (box));
    label.setJustificationType (Justification::centredLeft);
}

void CrookedLookAndFeel::drawTooltip (Graphics& g, const String& text, int w, int h)
{
    auto r = Rectangle<float> (0.0f, 0.0f, (float) w, (float) h);
    g.setColour (palette::cream);
    g.fillRoundedRectangle (r, 4.0f);
    g.setColour (palette::ink.withAlpha (0.5f));
    g.drawRoundedRectangle (r.reduced (0.5f), 4.0f, 1.0f);
    g.setColour (palette::charcoal);
    g.setFont (uiFont (12.5f));
    g.drawFittedText (text, r.reduced (8.0f, 5.0f).toNearestInt(), Justification::centredLeft, 4);
}

Rectangle<int> CrookedLookAndFeel::getTooltipBounds (const String& text, Point<int> pos, Rectangle<int> area)
{
    const int w = 260;
    const int lines = jlimit (1, 4, (int) (GlyphArrangement::getStringWidth (uiFont (12.5f), text) / (float) (w - 16)) + 1);
    const int h = lines * 16 + 12;
    return Rectangle<int> (pos.x > area.getCentreX() ? pos.x - (w + 12) : pos.x + 12,
                           pos.y > area.getCentreY() ? pos.y - (h + 8) : pos.y + 16, w, h).constrainedWithin (area);
}

//==============================================================================
Knob::Knob (AudioProcessorValueTreeState& state, const char* paramId, const String& t, const String& tip, bool isLarge)
    : title (t), large (isLarge)
{
    slider.setSliderStyle (Slider::RotaryHorizontalVerticalDrag);
    slider.setTextBoxStyle (Slider::NoTextBox, false, 0, 0);
    slider.setRotaryParameters (MathConstants<float>::pi * 1.25f, MathConstants<float>::pi * 2.75f, true);
    slider.setMouseDragSensitivity (large ? 220 : 180);
    slider.setTooltip (tip);
    addAndMakeVisible (slider);
    attachment = std::make_unique<AudioProcessorValueTreeState::SliderAttachment> (state, paramId, slider);
    if (auto* p = state.getParameter (paramId))
        slider.setDoubleClickReturnValue (true, p->convertFrom0to1 (p->getDefaultValue()));
    slider.onValueChange = [this] { repaint(); };
}

void Knob::resized()
{
    auto r = getLocalBounds();
    r.removeFromTop (large ? 20 : 16);
    r.removeFromBottom (large ? 20 : 16);
    const int d = jmin (r.getWidth(), r.getHeight());
    slider.setBounds (r.withSizeKeepingCentre (d, d));
}

void Knob::paint (Graphics& g)
{
    auto r = getLocalBounds();
    g.setColour (palette::ink);
    g.setFont (uiFont (large ? 13.5f : 11.0f, true, 0.12f));
    g.drawText (title, r.removeFromTop (large ? 20 : 16), Justification::centred);
    g.setColour (palette::inkSoft);
    g.setFont (uiFont (large ? 12.5f : 11.0f));
    g.drawText (slider.getTextFromValue (slider.getValue()), r.removeFromBottom (large ? 20 : 16), Justification::centred);
}

//==============================================================================
void ModeSwitch::paintButton (Graphics& g, bool highlighted, bool)
{
    auto r = getLocalBounds().toFloat().reduced (1.0f);
    const bool broken = getToggleState();
    g.setColour (palette::paperDeep.withAlpha (highlighted ? 1.0f : 0.85f));
    g.fillRoundedRectangle (r, 5.0f);
    g.setColour (palette::ink.withAlpha (0.35f));
    g.drawRoundedRectangle (r, 5.0f, 1.0f);

    auto left = r.withWidth (r.getWidth() * 0.5f), right = left.withX (left.getRight());
    auto sel = broken ? right : left;
    g.setColour (broken ? palette::red : palette::charcoal);
    g.fillRoundedRectangle (sel.reduced (2.0f), 4.0f);

    g.setFont (uiFont (12.0f, true, 0.08f));
    g.setColour (broken ? palette::ink : palette::cream);
    g.drawText ("POLISH", left, Justification::centred);
    g.setColour (broken ? palette::cream : palette::ink);
    g.drawText ("BROKEN", right, Justification::centred);
}

//==============================================================================
void MovementScope::update()
{
    auto& t = proc.telemetry;
    head = (head + 1) % kTrail;
    for (int k = 0; k < 2; ++k)
    {
        delayMs[k] = t.delayMs[k].load (std::memory_order_relaxed);
        pitch[k]   = t.pitch[k].load (std::memory_order_relaxed);
        pan[k]     = t.pan[k].load (std::memory_order_relaxed);
        gain[k]    = t.gain[k].load (std::memory_order_relaxed);
        crooked[k] = t.crooked[k].load (std::memory_order_relaxed);
        trail[k][head] = { delayMs[k] - t.baseMs[k].load (std::memory_order_relaxed), pitch[k] };
    }
    wet = t.wetGain.load (std::memory_order_relaxed);
    repaint();
}

void MovementScope::paint (Graphics& g)
{
    auto r = getLocalBounds().toFloat();
    g.setColour (palette::charcoal);
    g.fillRoundedRectangle (r, 6.0f);

    auto info  = r.removeFromBottom (40.0f).reduced (10.0f, 4.0f);
    auto plot  = r.reduced (10.0f, 10.0f);
    const auto c = plot.getCentre();
    const float hw = plot.getWidth() * 0.5f, hh = plot.getHeight() * 0.5f;

    g.setColour (palette::cream.withAlpha (0.06f));
    for (int i = 1; i < 4; ++i)
    {
        g.drawHorizontalLine ((int) (plot.getY() + plot.getHeight() * (float) i / 4.0f), plot.getX(), plot.getRight());
        g.drawVerticalLine ((int) (plot.getX() + plot.getWidth() * (float) i / 4.0f), plot.getY(), plot.getBottom());
    }
    g.setColour (palette::cream.withAlpha (0.18f));
    g.drawHorizontalLine ((int) c.y, plot.getX(), plot.getRight());
    g.drawVerticalLine ((int) c.x, plot.getY(), plot.getBottom());

    g.setFont (uiFont (9.5f, true, 0.15f));
    g.setColour (palette::cream.withAlpha (0.45f));
    g.drawText ("SHARP", plot.withHeight (12.0f), Justification::centredTop);
    g.drawText ("FLAT", plot.withTrimmedTop (plot.getHeight() - 12.0f), Justification::centredBottom);
    g.drawText ("RUSH", plot.withWidth (40.0f).withSizeKeepingCentre (40.0f, 12.0f).translated (0, -10), Justification::centredLeft);
    g.drawText ("DRAG", plot.withTrimmedLeft (plot.getWidth() - 40.0f).withSizeKeepingCentre (40.0f, 12.0f).translated (0, -10), Justification::centredRight);

    // the lead: fixed reference at the centre
    g.setColour (palette::cream);
    g.drawEllipse (c.x - 5.0f, c.y - 5.0f, 10.0f, 10.0f, 1.5f);
    g.setFont (uiFont (9.0f, true, 0.12f));
    g.drawText ("LEAD", Rectangle<float> (c.x - 40.0f, c.y + 4.0f, 34.0f, 11.0f), Justification::centredRight);

    auto toPoint = [&] (float timingMs, float cents)
    {
        return Point<float> (c.x + jlimit (-1.0f, 1.0f, timingMs / 8.0f) * (hw - 6.0f),
                             c.y - jlimit (-1.0f, 1.0f, cents / 25.0f) * (hh - 6.0f));
    };

    const float wetVis = jlimit (0.0f, 1.0f, (Decibels::gainToDecibels (wet, -60.0f) + 42.0f) / 36.0f);
    const Colour col[2] = { palette::mustard, Colour (0xffb5b87a) };

    for (int k = 1; k >= 0; --k)
    {
        if (gain[k] < 0.03f || wetVis <= 0.0f) continue;
        for (int i = 1; i < kTrail; ++i)
        {
            const int idx = (head - i + kTrail) % kTrail;
            const float a = (1.0f - (float) i / kTrail) * 0.35f * wetVis;
            const auto p = toPoint (trail[k][idx].timing, trail[k][idx].pitch);
            g.setColour (col[k].withAlpha (a));
            g.fillEllipse (p.x - 1.6f, p.y - 1.6f, 3.2f, 3.2f);
        }
        const auto p = toPoint (trail[k][head].timing, trail[k][head].pitch);
        const float rad = 3.5f + 3.5f * gain[k];
        if (crooked[k] > 0.02f)
        {
            g.setColour (palette::red.brighter (0.3f).withAlpha (jlimit (0.0f, 1.0f, crooked[k])));
            g.drawEllipse (p.x - rad - 4.0f, p.y - rad - 4.0f, (rad + 4.0f) * 2.0f, (rad + 4.0f) * 2.0f, 2.0f);
        }
        g.setColour (col[k].withAlpha (0.35f + 0.65f * wetVis));
        g.fillEllipse (p.x - rad, p.y - rad, rad * 2.0f, rad * 2.0f);
    }

    // stereo placement strip and readout
    auto strip = info.removeFromTop (12.0f);
    g.setColour (palette::cream.withAlpha (0.2f));
    g.drawHorizontalLine ((int) strip.getCentreY(), strip.getX() + 12.0f, strip.getRight() - 12.0f);
    g.setFont (uiFont (9.0f, true));
    g.setColour (palette::cream.withAlpha (0.45f));
    g.drawText ("L", strip, Justification::centredLeft);
    g.drawText ("R", strip, Justification::centredRight);
    const float sx0 = strip.getX() + 12.0f, sw = strip.getWidth() - 24.0f;
    g.setColour (palette::cream);
    g.fillEllipse (sx0 + sw * 0.5f - 2.0f, strip.getCentreY() - 2.0f, 4.0f, 4.0f);
    for (int k = 1; k >= 0; --k)
    {
        if (gain[k] < 0.03f) continue;
        const float px = sx0 + sw * (0.5f + 0.5f * pan[k]);
        g.setColour (col[k]);
        g.fillRoundedRectangle (px - 3.0f, strip.getCentreY() - 4.0f, 6.0f, 8.0f, 1.5f);
    }

    g.setFont (uiFont (10.5f));
    g.setColour (palette::cream.withAlpha (0.75f));
    auto txt = [&] (int k) { return String (delayMs[k], 1) + " ms  " + (pitch[k] >= 0 ? "+" : "") + String (pitch[k], 1) + " c"; };
    String s = "A " + txt (0);
    if (gain[1] >= 0.03f) s += "     B " + txt (1);
    g.drawText (s, info, Justification::centred);
}

//==============================================================================
void OutputMeter::setPeak (float p)
{
    level = jmax (p, level * 0.82f);
    if (p > 1.0f) clipHold = 60;  // ~2 s at 30 Hz
    else if (clipHold > 0) --clipHold;
    repaint();
}

void OutputMeter::paint (Graphics& g)
{
    auto r = getLocalBounds().toFloat();
    auto lamp = r.removeFromRight (40.0f);
    r.removeFromRight (6.0f);

    g.setColour (palette::charcoal);
    g.fillRoundedRectangle (r, 3.0f);
    const float db = Decibels::gainToDecibels (level, -60.0f);
    const float norm = jlimit (0.0f, 1.0f, (db + 48.0f) / 54.0f);   // -48 .. +6 dBFS
    const float zero = 48.0f / 54.0f;
    auto bar = r.reduced (2.0f);
    g.setColour (palette::olive.brighter (0.2f));
    g.fillRect (bar.withWidth (bar.getWidth() * jmin (norm, zero)));
    if (norm > zero)
    {
        g.setColour (palette::red);
        g.fillRect (bar.withX (bar.getX() + bar.getWidth() * zero).withWidth (bar.getWidth() * (norm - zero)));
    }
    g.setColour (palette::cream.withAlpha (0.6f));
    g.drawVerticalLine ((int) (bar.getX() + bar.getWidth() * zero), bar.getY(), bar.getBottom());

    const bool clip = clipHold > 0;
    g.setColour (clip ? palette::red : palette::paperDeep);
    g.fillRoundedRectangle (lamp, 3.0f);
    g.setColour (clip ? palette::cream : palette::inkSoft);
    g.setFont (uiFont (10.5f, true, 0.1f));
    g.drawText ("CLIP", lamp, Justification::centred);
}

//==============================================================================
CrookedDoubleEditor::CrookedDoubleEditor (CrookedDoubleProcessor& p)
    : AudioProcessorEditor (&p), proc (p),
      kDouble   (p.apvts, ids::doubleLevel, "DOUBLE",   "Level of the artificial double under your untouched lead. Around -9 dB thickens; higher sounds like a second singer.", true),
      kDistance (p.apvts, ids::distance,    "DISTANCE", "How late the double follows you. Short is close and thick; long is a distinct second voice.", true),
      kDrift    (p.apvts, ids::drift,       "DRIFT",    "How far the tape wanders in pitch and timing. Low barely moves; high wanders noticeably.", true),
      kNerves   (p.apvts, ids::nerves,      "NERVES",   "How quickly and restlessly the wandering changes. Low is lazy; high is jittery.", true),
      kCrooked  (p.apvts, ids::crooked,     "CROOKED",  "Occasional stumbles: the double lags, leans flat or sharp, then finds its place. Zero switches them off.", true),
      kWear     (p.apvts, ids::wear,        "WEAR",     "Tape character on the double only: soft saturation, a forward mid colour and a duller top. Adds no noise.", true),
      kWidth    (p.apvts, ids::width,       "WIDTH",    "0 keeps one double in the centre. Turning up splits it into two related voices spread left and right.", true),
      kOutput   (p.apvts, ids::output,      "OUTPUT",   "Final trim after the lead and double are summed. CLIP lights above 0 dBFS (click it to clear).", false),
      kHiss     (p.apvts, ids::hissLevel,   "LEVEL",    "Level of the optional tape hiss.", false),
      scope (p)
{
    setLookAndFeel (&laf);

    for (auto* k : { &kDouble, &kDistance, &kDrift, &kNerves, &kCrooked, &kWear, &kWidth, &kOutput, &kHiss })
        addAndMakeVisible (k);
    kCrooked.slider.setColour (Slider::rotarySliderFillColourId, palette::red);
    kWear.slider.setColour (Slider::rotarySliderFillColourId, palette::olive);

    doubleOnly.setTooltip ("Mutes the dry lead so you can hear or print the double on its own.");
    hissOn.setTooltip ("Optional tape hiss. When off it is true digital silence.");
    hissOn.getProperties().set ("lamp", "mustard");
    modeSwitch.setTooltip ("POLISH keeps the movement restrained and smooth. BROKEN allows lopsided drift, tape snags and bigger stumbles.");
    addAndMakeVisible (doubleOnly);
    addAndMakeVisible (hissOn);
    addAndMakeVisible (modeSwitch);
    aDoubleOnly = std::make_unique<AudioProcessorValueTreeState::ButtonAttachment> (p.apvts, ids::doubleOnly, doubleOnly);
    aHiss       = std::make_unique<AudioProcessorValueTreeState::ButtonAttachment> (p.apvts, ids::hiss, hissOn);
    aMode       = std::make_unique<AudioProcessorValueTreeState::ButtonAttachment> (p.apvts, ids::mode, modeSwitch);

    for (int i = 0; i < kNumPresets; ++i)
        presetBox.addItem (kPresets[i].name, i + 1);
    presetBox.setTooltip ("Factory presets. Tape hiss is left as you set it.");
    presetBox.onChange = [this]
    {
        const int idx = presetBox.getSelectedId() - 1;
        if (idx >= 0 && idx != proc.getCurrentProgram()) proc.setCurrentProgram (idx);
        shownProgram = idx;
    };
    prevPreset.onClick = [this] { proc.setCurrentProgram ((proc.getCurrentProgram() + kNumPresets - 1) % kNumPresets); refreshPresetBox(); };
    nextPreset.onClick = [this] { proc.setCurrentProgram ((proc.getCurrentProgram() + 1) % kNumPresets); refreshPresetBox(); };
    addAndMakeVisible (presetBox);
    addAndMakeVisible (prevPreset);
    addAndMakeVisible (nextPreset);
    refreshPresetBox();

    addAndMakeVisible (scope);
    addAndMakeVisible (meter);
    meter.setTooltip ("Output peak. CLIP lights above 0 dBFS; click to clear.");

    setSize (kW, kH);
    startTimerHz (30);
}

CrookedDoubleEditor::~CrookedDoubleEditor()
{
    stopTimer();
    setLookAndFeel (nullptr);
}

void CrookedDoubleEditor::refreshPresetBox()
{
    shownProgram = proc.getCurrentProgram();
    presetBox.setSelectedId (shownProgram + 1, dontSendNotification);
}

void CrookedDoubleEditor::timerCallback()
{
    if (proc.getCurrentProgram() != shownProgram) refreshPresetBox();
    scope.update();
    meter.setPeak (proc.telemetry.peak.exchange (0.0f));
}

void CrookedDoubleEditor::paint (Graphics& g)
{
    g.fillAll (palette::paper);

    // header band
    auto header = getLocalBounds().removeFromTop (56);
    g.setColour (palette::charcoal);
    g.fillRect (header);
    g.setColour (palette::red);
    g.fillRect (header.getX(), header.getBottom(), header.getWidth(), 3);

    g.setColour (palette::cream);
    g.setFont (uiFont (25.0f, true, 0.14f));
    g.drawText ("CROOKED DOUBLE", 22, 7, 400, 30, Justification::centredLeft);
    g.setColour (palette::mustard);
    g.setFont (uiFont (10.5f, true, 0.28f));
    g.drawText ("ARTIFICIAL DOUBLE TRACKER", 23, 35, 400, 14, Justification::centredLeft);

    // section labels
    auto label = [&] (const String& t, int x, int y, int w)
    {
        g.setColour (palette::inkSoft);
        g.setFont (uiFont (10.0f, true, 0.22f));
        g.drawText (t, x, y, w, 12, Justification::centredLeft);
        g.setColour (palette::ink.withAlpha (0.12f));
        g.fillRect (x + (int) GlyphArrangement::getStringWidth (g.getCurrentFont(), t) + 8, y + 6, w - (int) GlyphArrangement::getStringWidth (g.getCurrentFont(), t) - 8, 1);
    };
    label ("THE DOUBLE", 16, 68, 512);
    label ("CHARACTER", 16, 242, 512);
    label ("MOVEMENT", 552, 68, 232);
    label ("MASTER", 552, 280, 232);

    g.setColour (palette::ink.withAlpha (0.12f));
    g.fillRect (540, 72, 1, 330);

    g.setColour (palette::inkSoft);
    g.setFont (uiFont (10.5f, true, 0.22f));
    g.drawText ("MODE", 400, 318, 120, 12, Justification::centredLeft);

    g.setFont (uiFont (11.0f));
    g.setColour (palette::inkSoft);
    g.drawText (String (CharPointer_UTF8 ("Lead stays dry, centred and untouched  \xc2\xb7  zero latency  \xc2\xb7  an expressive artificial double, not a second performance")),
                getLocalBounds().removeFromBottom (30), Justification::centred);
}

void CrookedDoubleEditor::resized()
{
    const int cellW = 128, x0 = 16;
    kDouble.setBounds   (x0 + 0 * cellW, 84, cellW, 150);
    kDistance.setBounds (x0 + 1 * cellW, 84, cellW, 150);
    kDrift.setBounds    (x0 + 2 * cellW, 84, cellW, 150);
    kNerves.setBounds   (x0 + 3 * cellW, 84, cellW, 150);
    kCrooked.setBounds  (x0 + 0 * cellW, 256, cellW, 150);
    kWear.setBounds     (x0 + 1 * cellW, 256, cellW, 150);
    kWidth.setBounds    (x0 + 2 * cellW, 256, cellW, 150);

    doubleOnly.setBounds (400, 270, 122, 32);
    modeSwitch.setBounds (400, 334, 122, 32);

    scope.setBounds (552, 84, 232, 188);

    kOutput.setBounds (548, 292, 84, 108);
    meter.setBounds (640, 312, 144, 20);
    hissOn.setBounds (640, 352, 98, 30);
    kHiss.setBounds (740, 336, 50, 70);

    prevPreset.setBounds (516, 15, 28, 26);
    presetBox.setBounds (548, 15, 200, 26);
    nextPreset.setBounds (752, 15, 28, 26);
}
CROOKED_DOUBLE_EOF
cat > "$DEST/tests/EngineTests.cpp" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - offline DSP verification (no JUCE, no host)
// Build: see CMakeLists.txt option CROOKED_BUILD_TESTS, or
//   g++ -std=c++17 -O2 -I../Source tests/EngineTests.cpp ../Source/dsp/CrookedEngine.cpp
#include "dsp/CrookedEngine.h"

#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>
#if defined(__SSE__) || defined(__x86_64__)
 #include <xmmintrin.h>
 #include <pmmintrin.h>
#endif

using namespace cd;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf ("  FAIL: "); std::printf (__VA_ARGS__); std::printf ("\n"); } } while (0)

static void enableFtz()
{
#if defined(__SSE__) || defined(__x86_64__)
    _MM_SET_FLUSH_ZERO_MODE (_MM_FLUSH_ZERO_ON);
    _MM_SET_DENORMALS_ZERO_MODE (_MM_DENORMALS_ZERO_ON);
#endif
}

static double db (double g) { return 20.0 * std::log10 (std::max (g, 1.0e-12)); }

//==============================================================================
// Synthetic sung-vocal-like test signal: band-limited glottal saw with vibrato,
// moving formants, note envelopes and consonant noise bursts. Peak -6 dBFS.
static std::vector<float> makeVocal (double sr, double seconds, uint32_t seed = 1)
{
    const int n = (int) (sr * seconds);
    std::vector<float> out ((size_t) n, 0.0f);
    Rng r; r.seed (seed);

    const float notes[] = { 196.0f, 220.0f, 246.9f, 220.0f, 261.6f, 246.9f, 196.0f, 174.6f };
    const float formants[][3] = { { 730, 1090, 2440 }, { 270, 2290, 3010 }, { 570, 840, 2410 }, { 530, 1840, 2480 }, { 300, 870, 2240 } };

    Svf f[3]; float fq[3] = { 8, 10, 12 };
    double phase = 0.0;
    int pos = 0, noteIdx = 0;
    while (pos < n)
    {
        const int len = (int) (sr * r.range (0.22f, 0.55f));
        const int gap = (int) (sr * r.range (0.03f, 0.09f));
        const float f0 = notes[noteIdx++ % 8];
        const auto& fm = formants[r.uni() < 0.999f ? (int) (r.uni() * 5) % 5 : 0];
        for (int k = 0; k < 3; ++k) f[k].setup (fm[k], fq[k], sr);
        const int cons = (int) (sr * 0.025);

        for (int i = 0; i < len && pos < n; ++i, ++pos)
        {
            const double t = i / sr;
            const double vib = 1.0 + 0.012 * std::sin (2.0 * kPiD * 5.5 * t) * std::min (1.0, t / 0.2);
            phase += f0 * vib / sr;
            if (phase >= 1.0) phase -= 1.0;
            float src = 0.0f;
            const int nh = (int) std::min (40.0, 7000.0 / (f0 * vib));
            for (int h = 1; h <= nh; ++h) src += (float) (std::sin (2.0 * kPiD * h * phase) / h);
            float env = (float) std::min (1.0, t / 0.03) * (float) std::min (1.0, (len - i) / (0.05 * sr));
            float y = 0.0f, lp, bp, hp;
            for (int k = 0; k < 3; ++k) { f[k].process (src, lp, bp, hp); y += bp * (k == 0 ? 1.0f : k == 1 ? 0.6f : 0.3f); }
            float noise = i < cons ? r.bi() * 0.25f * (1.0f - (float) i / cons) : 0.0f;
            out[(size_t) pos] = env * y + noise;
        }
        pos += gap;
    }
    float pk = 0.0f;
    for (auto v : out) pk = std::max (pk, std::abs (v));
    for (auto& v : out) v *= 0.5f / pk;
    return out;
}

static std::vector<float> makeSine (double sr, double seconds, float hz, float amp)
{
    std::vector<float> s ((size_t) (sr * seconds));
    for (size_t i = 0; i < s.size(); ++i) s[i] = amp * (float) std::sin (2.0 * kPiD * hz * (double) i / sr);
    return s;
}

struct Render { std::vector<float> L, R; };

/** Block-wise render with optional per-block parameter callback and random block sizes. */
static Render render (CrookedEngine& e, const std::vector<float>& inL, const std::vector<float>* inR, bool stereoOut,
                      const std::function<void (int sampleIndex, EngineParams&)>& automate,
                      EngineParams p, uint32_t blockSeed = 0, int fixedBlock = 256,
                      const std::function<void (int, const CrookedEngine&)>& observe = {})
{
    Render out; out.L.resize (inL.size()); out.R.resize (inL.size());
    Rng br; br.seed (blockSeed + 99);
    size_t pos = 0;
    while (pos < inL.size())
    {
        int bs = blockSeed ? 1 + (int) (br.uni() * br.uni() * 2048) : fixedBlock;
        bs = (int) std::min ((size_t) bs, inL.size() - pos);
        if (automate) automate ((int) pos, p);
        e.setParams (p);
        e.process (inL.data() + pos, inR ? inR->data() + pos : nullptr,
                   out.L.data() + pos, stereoOut ? out.R.data() + pos : nullptr, bs);
        if (! stereoOut) std::memcpy (out.R.data() + pos, out.L.data() + pos, sizeof (float) * (size_t) bs);
        if (observe) observe ((int) pos, e);
        pos += (size_t) bs;
    }
    return out;
}

static float peakAbs (const std::vector<float>& v, size_t from = 0, size_t to = SIZE_MAX)
{
    float p = 0.0f; to = std::min (to, v.size());
    for (size_t i = from; i < to; ++i) p = std::max (p, std::abs (v[i]));
    return p;
}
static double rms (const std::vector<float>& v, size_t from = 0, size_t to = SIZE_MAX)
{
    double s = 0; to = std::min (to, v.size());
    for (size_t i = from; i < to; ++i) s += (double) v[i] * v[i];
    return std::sqrt (s / std::max<size_t> (1, to - from));
}
static bool allFinite (const Render& r)
{
    for (size_t i = 0; i < r.L.size(); ++i) if (! std::isfinite (r.L[i]) || ! std::isfinite (r.R[i])) return false;
    return true;
}

/** Peak of 8 kHz-high-passed signal in 2 ms windows: a click detector. */
static float hfPeak (const std::vector<float>& x, double sr, size_t skip)
{
    Svf a, b; a.setup (8000.0f, 0.54f, sr); b.setup (8000.0f, 1.31f, sr);
    float pk = 0.0f, lp, bp, hp, hp2;
    for (size_t i = 0; i < x.size(); ++i)
    {
        a.process (x[i], lp, bp, hp);
        b.process (hp, lp, bp, hp2);
        if (i >= skip) pk = std::max (pk, std::abs (hp2));
    }
    return pk;
}

static EngineParams defaults() { return EngineParams{}; }

static const double kRates[] = { 44100.0, 48000.0, 88200.0, 96000.0, 192000.0 };

//==============================================================================
static void testSilence()
{
    std::printf ("[1] Silence in, hiss off -> silence out\n");
    for (double sr : kRates)
    {
        for (int broken = 0; broken < 2; ++broken)
        {
            CrookedEngine e; e.setSeed (5); auto p = defaults(); p.broken = broken; p.drift = 1; p.nerves = 1; p.crooked = 1; p.wear = 1; p.width = 1; p.doubleDb = 0;
            e.setParams (p); e.prepare (sr, 512);
            std::vector<float> z ((size_t) (sr * 3.0), 0.0f);
            auto o = render (e, z, &z, true, {}, p, 3);
            CHECK (peakAbs (o.L) == 0.0f && peakAbs (o.R) == 0.0f, "sr %.0f broken %d: silence produced %g", sr, broken, peakAbs (o.L));
        }
        // vocal then silence: tail must decay to digital zero
        CrookedEngine e; auto p = defaults(); p.wear = 1; p.doubleDb = 0; e.setParams (p); e.prepare (sr, 512);
        auto v = makeVocal (sr, 2.0);
        v.resize ((size_t) (sr * 4.0), 0.0f);
        auto o = render (e, v, nullptr, true, {}, p, 0, 512);
        const float tail = peakAbs (o.L, (size_t) (sr * 3.0));
        CHECK (tail == 0.0f, "sr %.0f: tail 1 s after vocal is %g (want exact 0)", sr, tail);
    }
    std::printf ("    done\n");
}

static void testDryExact()
{
    std::printf ("[2] DOUBLE off + OUTPUT 0 dB -> output bit identical to input\n");
    for (double sr : { 44100.0, 96000.0 })
    {
        auto vl = makeVocal (sr, 3.0, 2), vr = makeVocal (sr, 3.0, 3);
        auto p = defaults(); p.doubleDb = kDoubleOffDb; p.drift = 1; p.nerves = 1; p.crooked = 1; p.wear = 1; p.broken = true; p.width = 1;

        { CrookedEngine e; e.setParams (p); e.prepare (sr, 512);
          auto o = render (e, vl, &vr, true, {}, p, 7);
          CHECK (o.L == vl && o.R == vr, "stereo->stereo not bit exact at %.0f", sr); }
        { CrookedEngine e; e.setParams (p); e.prepare (sr, 512);
          auto o = render (e, vl, nullptr, true, {}, p, 7);
          CHECK (o.L == vl && o.R == vl, "mono->stereo not bit exact at %.0f", sr); }
        { CrookedEngine e; e.setParams (p); e.prepare (sr, 512);
          auto o = render (e, vl, nullptr, false, {}, p, 7);
          CHECK (o.L == vl, "mono->mono not bit exact at %.0f", sr); }
        { // automate from -9 dB down to off: after the fade the dry must again be exact
          CrookedEngine e; auto q = defaults(); e.setParams (q); e.prepare (sr, 512);
          auto o = render (e, vl, &vr, true, [&] (int pos, EngineParams& pp) { if (pos > sr * 1.0) pp.doubleDb = kDoubleOffDb; }, q, 9);
          bool exact = true;
          for (size_t i = (size_t) (sr * 1.6); i < vl.size(); ++i) if (o.L[i] != vl[i] || o.R[i] != vr[i]) { exact = false; break; }
          CHECK (exact, "after automating DOUBLE to off the dry was not exact at %.0f", sr); }
    }
    std::printf ("    done\n");
}

static void testZeroLatency()
{
    std::printf ("[3] Zero latency: dry impulse is not moved\n");
    CrookedEngine e; auto p = defaults(); e.setParams (p); e.prepare (48000.0, 512);
    std::vector<float> x (48000, 0.0f); x[1000] = 0.5f;
    auto o = render (e, x, nullptr, true, {}, p);
    CHECK (o.L[1000] == 0.5f, "dry impulse altered at its own sample: %g", o.L[1000]);
    // the double arrives later (intentional doubling delay, not latency)
    size_t at = 0; float best = 0;
    for (size_t i = 1001; i < x.size(); ++i) if (std::abs (o.L[i]) > best) { best = std::abs (o.L[i]); at = i; }
    std::printf ("    wet impulse peak at +%.1f ms (%.1f dB re dry)\n", (double) (at - 1000) / 48.0, db (best / 0.5));
}

static void testExtremes()
{
    std::printf ("[4] Extreme corners, random block sizes, all rates: finite, bounded, delay in range, pitch bounded\n");
    int combos = 0;
    double worstSlew = 0, worstMin = 1e9, worstMax = 0;
    float worstPeak = 0;
    for (double sr : kRates)
    {
        auto v = makeVocal (sr, 2.5, 4);
        for (int mask = 0; mask < 512; mask += (sr == 48000.0 ? 1 : 7))
        {
            EngineParams p;
            p.doubleDb   = (mask & 1)   ? 6.0f  : -59.0f;
            p.distanceMs = (mask & 2)   ? 65.0f : 8.0f;
            p.drift      = (mask & 4)   ? 1.0f  : 0.0f;
            p.nerves     = (mask & 8)   ? 1.0f  : 0.0f;
            p.crooked    = (mask & 16)  ? 1.0f  : 0.0f;
            p.wear       = (mask & 32)  ? 1.0f  : 0.0f;
            p.width      = (mask & 64)  ? 1.0f  : 0.0f;
            p.broken     = (mask & 128) != 0;
            p.outputDb   = (mask & 256) ? 12.0f : -24.0f;
            CrookedEngine e; e.setSeed ((uint64_t) mask + 1); e.setParams (p); e.prepare (sr, 2048);
            auto o = render (e, v, &v, true, {}, p, (uint32_t) mask + 1);
            ++combos;
            const auto& s = e.stats();
            CHECK (allFinite (o), "non finite output mask %d sr %.0f", mask, sr);
            CHECK (s.maxSlew <= CrookedEngine::kMaxSlew + 1e-9, "slew %g", s.maxSlew);
            CHECK (s.minDelaySamples >= CrookedEngine::kMinDelaySec * sr - 1e-6, "min delay %g", s.minDelaySamples);
            CHECK (s.maxDelaySamples <= CrookedEngine::kMaxDelaySec * sr + 1e-6, "max delay %g", s.maxDelaySamples);
            const float bound = 0.5f * (1.0f + 2.0f * 2.0f * 1.42f) * dbToGain (p.outputDb) * 1.1f;
            const float pk = std::max (peakAbs (o.L), peakAbs (o.R));
            CHECK (pk <= bound, "peak %g above bound %g (mask %d)", pk, bound, mask);
            worstSlew = std::max (worstSlew, s.maxSlew);
            worstMin = std::min (worstMin, s.minDelaySamples / sr * 1000.0);
            worstMax = std::max (worstMax, s.maxDelaySamples / sr * 1000.0);
            worstPeak = std::max (worstPeak, pk / dbToGain (p.outputDb));
        }
    }
    std::printf ("    %d renders. delay range used %.2f .. %.2f ms, worst pitch excursion %.1f cents, worst peak %.1f dBFS (pre output trim)\n",
                 combos, worstMin, worstMax, 1200.0 * std::log2 (1.0 + worstSlew), db (worstPeak));

    // hostile inputs
    for (double sr : { 44100.0, 192000.0 })
    {
        const int n = (int) (sr * 2);
        std::vector<float> noise ((size_t) n), dc ((size_t) n, 1.0f), imp ((size_t) n, 0.0f), nanIn ((size_t) n, 0.0f);
        Rng r; r.seed (3);
        for (auto& x : noise) x = r.bi();
        for (int i = 0; i < n; i += 997) imp[(size_t) i] = 1.0f;
        auto vv = makeVocal (sr, 2.0, 8); nanIn = vv; nanIn[(size_t) n / 3] = NAN; nanIn[(size_t) n / 2] = INFINITY;
        EngineParams p; p.doubleDb = 6; p.drift = 1; p.nerves = 1; p.crooked = 1; p.wear = 1; p.broken = true; p.width = 1; p.outputDb = 12;
        for (auto* in : { &noise, &dc, &imp, &nanIn })
        {
            CrookedEngine e; e.setParams (p); e.prepare (sr, 512);
            auto o = render (e, *in, in, true, {}, p, 11);
            CHECK (allFinite (o), "hostile input produced non finite output");
            CHECK (peakAbs (o.L) <= 32.0f, "rail exceeded");
            if (in == &nanIn)
            {
                CHECK (e.stats().nonFiniteEvents > 0, "NaN input not caught");
                CHECK (peakAbs (o.L, (size_t) (n * 0.6)) > 0.01f, "engine did not recover after NaN");
            }
        }
    }

    // random automation fuzz: every block gets random values
    for (double sr : { 44100.0, 96000.0 })
    {
        auto v = makeVocal (sr, 8.0, 6);
        CrookedEngine e; EngineParams p; e.setParams (p); e.prepare (sr, 2048);
        Rng r; r.seed (77);
        auto o = render (e, v, &v, true, [&] (int, EngineParams& q) {
            q.doubleDb = r.range (-60, 6); q.distanceMs = r.range (8, 65); q.drift = r.uni(); q.nerves = r.uni();
            q.crooked = r.uni(); q.wear = r.uni(); q.width = r.uni(); q.outputDb = r.range (-24, 12);
            q.broken = r.uni() < 0.5f; q.doubleOnly = r.uni() < 0.2f; q.hissOn = r.uni() < 0.5f; q.hissDb = r.range (-80, -36);
        }, p, 21);
        CHECK (allFinite (o), "fuzz non finite");
        CHECK (e.stats().maxSlew <= CrookedEngine::kMaxSlew + 1e-9, "fuzz slew");
        CHECK (std::max (peakAbs (o.L), peakAbs (o.R)) < 16.0f, "fuzz peak %g", peakAbs (o.L));
    }
    std::printf ("    done\n");
}

static void testClicks()
{
    std::printf ("[5] Automation / mode jumps: no clicks (8 kHz+ residual vs steady state, sine 220 Hz)\n");
    const double sr = 48000.0;
    auto s = makeSine (sr, 6.0, 220.0f, 0.25f);
    const size_t skip = (size_t) (sr * 0.5);

    struct Case { const char* name; std::function<void (EngineParams&, bool)> set; };
    std::vector<Case> cases = {
        { "POLISH/BROKEN",  [] (EngineParams& p, bool b) { p.broken = b; p.crooked = 0.6f; p.drift = 0.7f; } },
        { "DISTANCE 8/65",  [] (EngineParams& p, bool b) { p.distanceMs = b ? 65.0f : 8.0f; } },
        { "WIDTH 0/1",      [] (EngineParams& p, bool b) { p.width = b ? 1.0f : 0.0f; } },
        { "DOUBLE off/+6",  [] (EngineParams& p, bool b) { p.doubleDb = b ? 6.0f : kDoubleOffDb; } },
        { "DOUBLE ONLY",    [] (EngineParams& p, bool b) { p.doubleOnly = b; } },
        { "OUTPUT -24/+12", [] (EngineParams& p, bool b) { p.outputDb = b ? 12.0f : -24.0f; } },
        { "WEAR 0/1",       [] (EngineParams& p, bool b) { p.wear = b ? 1.0f : 0.0f; } },
        { "CROOKED 0/1",    [] (EngineParams& p, bool b) { p.crooked = b ? 1.0f : 0.0f; } },
        { "DRIFT 0/1",      [] (EngineParams& p, bool b) { p.drift = b ? 1.0f : 0.0f; } },
        { "NERVES 0/1",     [] (EngineParams& p, bool b) { p.nerves = b ? 1.0f : 0.0f; } },
    };

    for (auto& c : cases)
    {
        float base = 0.0f;
        for (int b = 0; b < 2; ++b)
        {
            CrookedEngine e; e.setSeed (42); auto p = defaults(); c.set (p, b); e.setParams (p); e.prepare (sr, 256);
            auto o = render (e, s, nullptr, true, {}, p);
            base = std::max (base, std::max (hfPeak (o.L, sr, skip), hfPeak (o.R, sr, skip)));
        }
        CrookedEngine e; e.setSeed (42); auto p = defaults(); c.set (p, false); e.setParams (p); e.prepare (sr, 256);
        auto o = render (e, s, nullptr, true, [&] (int pos, EngineParams& q) { c.set (q, ((pos / (int) (sr * 0.7)) & 1) != 0); }, p);
        const float sw = std::max (hfPeak (o.L, sr, skip), hfPeak (o.R, sr, skip));
        const float limit = 2.0f * base + 1.0e-5f;
        std::printf ("    %-15s steady %7.1f dB  switching %7.1f dB  %s\n", c.name, db (base), db (sw), sw <= limit ? "ok" : "CLICK");
        CHECK (sw <= limit, "%s produced HF transient", c.name);
    }

    // bypass and resume, then reset (transport restart / reload)
    {
        CrookedEngine e; auto p = defaults(); p.doubleDb = 0; e.setParams (p); e.prepare (sr, 256);
        std::vector<float> o (s.size()), oR (s.size());
        size_t pos = 0; int blk = 0;
        while (pos < s.size())
        {
            const int n = (int) std::min<size_t> (256, s.size() - pos);
            if (blk % 40 >= 20 && blk % 40 < 26) e.processBypassed (s.data() + pos, nullptr, o.data() + pos, oR.data() + pos, n);
            else e.process (s.data() + pos, nullptr, o.data() + pos, oR.data() + pos, n);
            pos += (size_t) n; ++blk;
        }
        CrookedEngine e2; e2.setParams (p); e2.prepare (sr, 256);
        auto steady = render (e2, s, nullptr, true, {}, p);
        const float b = hfPeak (steady.L, sr, skip), sw = hfPeak (o, sr, skip);
        std::printf ("    %-15s steady %7.1f dB  switching %7.1f dB  %s\n", "BYPASS/RESUME", db (b), db (sw), sw <= 2 * b + 1e-5f ? "ok" : "CLICK");
        CHECK (sw <= 2 * b + 1e-5f, "bypass resume click");
    }
}

static void testMonoAndWidth()
{
    std::printf ("[6] Width, stereo image and mono summing (DOUBLE ONLY, vocal)\n");
    const double sr = 48000.0;
    auto v = makeVocal (sr, 12.0, 12);
    double centreMono = 0;
    for (float w : { 0.0f, 0.25f, 0.5f, 0.75f, 1.0f })
    {
        CrookedEngine e; e.setSeed (9); auto p = defaults(); p.width = w; p.doubleOnly = true; p.doubleDb = 0; e.setParams (p); e.prepare (sr, 512);
        auto o = render (e, v, nullptr, true, {}, p);
        const size_t a = (size_t) sr;
        double sL = 0, sR = 0, sLR = 0;
        std::vector<float> mono (o.L.size());
        for (size_t i = a; i < o.L.size(); ++i) { sL += o.L[i] * o.L[i]; sR += o.R[i] * o.R[i]; sLR += o.L[i] * o.R[i]; mono[i] = 0.5f * (o.L[i] + o.R[i]); }
        const double corr = sLR / std::sqrt (sL * sR + 1e-30);
        const double stereoPow = db (std::sqrt ((sL + sR) / 2.0 / (double) (o.L.size() - a)));
        const double monoLvl = db (rms (mono, a));
        if (w == 0.0f) centreMono = monoLvl;
        std::printf ("    width %.2f: L/R corr %+.2f  balance L-R %+.2f dB  stereo level %.1f dB  mono-sum level %.1f dB (%+.1f re centre)\n",
                     w, corr, db (std::sqrt (sL / sR)), stereoPow, monoLvl, monoLvl - centreMono);
        if (w == 1.0f)
        {
            CHECK (corr < 0.9 && corr > -0.2, "full width correlation %g out of range", corr);
            CHECK (monoLvl - centreMono > -4.5, "mono fold-down loses %.1f dB", monoLvl - centreMono);
        }
        CHECK (std::abs (db (std::sqrt (sL / sR))) < 1.5, "image unbalanced at width %.2f", w);
    }
    // stereo input: dry image untouched, wet from mono sum
    {
        auto vl = makeVocal (sr, 3.0, 2), vr = makeVocal (sr, 3.0, 3);
        CrookedEngine e; auto p = defaults(); e.setParams (p); e.prepare (sr, 512);
        auto o = render (e, vl, &vr, true, {}, p);
        double dl = 0, dr = 0;
        for (size_t i = 0; i < vl.size(); ++i) { dl += std::abs (o.L[i] - vl[i]); dr += std::abs (o.R[i] - vr[i]); }
        std::printf ("    stereo in: wet adds %.1f dB (L) / %.1f dB (R) relative to dry\n", db (dl / vl.size() / (rms (vl) + 1e-9)), db (dr / vr.size() / (rms (vr) + 1e-9)));
    }
}

static void testRatesAndMovement()
{
    std::printf ("[7] Sample rates: same musical result at every rate\n");
    for (double sr : kRates)
    {
        CrookedEngine e; e.setSeed (1234); auto p = defaults(); e.setParams (p); e.prepare (sr, 512);
        auto v = makeVocal (sr, 20.0, 5);
        double sumD = 0, sumP2 = 0, maxP = 0; int nb = 0;
        auto o = render (e, v, nullptr, true, {}, p, 0, (int) (sr / 375.0), [&] (int pos, const CrookedEngine& en) {
            if (pos < sr) return;
            const auto& vw = en.view().voice[0];
            sumD += vw.delayMs; sumP2 += vw.pitchCents * vw.pitchCents; maxP = std::max (maxP, (double) std::abs (vw.pitchCents)); ++nb; });
        std::printf ("    %6.0f Hz: mean delay %.2f ms, pitch dev RMS %.2f c / peak %.1f c, out RMS %.2f dBFS, max slew %.1f c\n",
                     sr, sumD / nb, std::sqrt (sumP2 / nb), maxP, db (rms (o.L)), 1200.0 * std::log2 (1.0 + e.stats().maxSlew));
    }

    std::printf ("[8] Movement character (120 s per setting, view sampled every 2.67 ms)\n");
    struct S { const char* name; EngineParams p; };
    std::vector<S> sets;
    { S s { "default", defaults() }; sets.push_back (s); }
    { S s { "drift 1 nerves 0", defaults() }; s.p.drift = 1; s.p.nerves = 0; s.p.crooked = 0; sets.push_back (s); }
    { S s { "drift 0 nerves 1", defaults() }; s.p.drift = 0; s.p.nerves = 1; s.p.crooked = 0; sets.push_back (s); }
    { S s { "drift 1 nerves 1", defaults() }; s.p.drift = 1; s.p.nerves = 1; s.p.crooked = 0; sets.push_back (s); }
    { S s { "crooked 1 polish", defaults() }; s.p.crooked = 1; sets.push_back (s); }
    { S s { "all max broken", defaults() }; s.p.drift = 1; s.p.nerves = 1; s.p.crooked = 1; s.p.broken = true; sets.push_back (s); }
    { S s { "crooked 0", defaults() }; s.p.crooked = 0; sets.push_back (s); }

    const double sr = 48000.0;
    for (auto& s : sets)
    {
        CrookedEngine e; e.setSeed (777); e.setParams (s.p); e.prepare (sr, 128);
        std::vector<float> z ((size_t) (sr * 120.0), 0.0f);
        std::vector<double> da, db_, pa;
        render (e, z, nullptr, true, {}, s.p, 0, 128, [&] (int, const CrookedEngine& en) {
            da.push_back (en.view().voice[0].delayMs); db_.push_back (en.view().voice[1].delayMs); pa.push_back (en.view().voice[0].pitchCents); });
        auto meanOf = [] (const std::vector<double>& x) { double m = 0; for (auto v : x) m += v; return m / x.size(); };
        const double ma = meanOf (da), mb = meanOf (db_);
        double va = 0, vb = 0, cab = 0, p2 = 0, pmax = 0, dmin = 1e9, dmax = 0;
        for (size_t i = 0; i < da.size(); ++i)
        {
            va += (da[i] - ma) * (da[i] - ma); vb += (db_[i] - mb) * (db_[i] - mb); cab += (da[i] - ma) * (db_[i] - mb);
            p2 += pa[i] * pa[i]; pmax = std::max (pmax, std::abs (pa[i])); dmin = std::min (dmin, da[i]); dmax = std::max (dmax, da[i]);
        }
        // strongest repeat: highest autocorrelation peak after the first zero crossing (lags up to 40 s)
        double best = 0, bestLag = 0;
        const int n = (int) da.size(), step = 4;
        bool crossed = false;
        for (int lag = step; lag < (int) (40 * 375); lag += step)
        {
            double c = 0; for (int i = 0; i + lag < n; i += 2) c += (da[(size_t) i] - ma) * (da[(size_t) (i + lag)] - ma);
            c /= (va / n) * ((n - lag) / 2.0) + 1e-30;
            if (! crossed) { crossed = c < 0.0; continue; }
            if (c > best) { best = c; bestLag = lag / 375.0; }
        }
        std::printf ("    %-17s delay A %.1f..%.1f ms  pitch RMS %5.2f c peak %5.1f c  A/B corr %+.2f  repeat peak %.2f @ %.1fs  events %d\n",
                     s.name, dmin, dmax, std::sqrt (p2 / pa.size()), pmax, cab / std::sqrt (va * vb + 1e-30), best, bestLag, e.stats().eventsStarted);
        if (std::string (s.name) == "crooked 0") CHECK (e.stats().eventsStarted == 0, "CROOKED 0 still produced events");
        CHECK (best < 0.6, "%s: movement looks periodic (%.2f)", s.name, best);
    }
}

static void testHiss()
{
    std::printf ("[9] Tape hiss level calibration\n");
    const double sr = 48000.0;
    for (float hdb : { -80.0f, -62.0f, -36.0f })
    {
        CrookedEngine e; auto p = defaults(); p.hissOn = true; p.hissDb = hdb; e.setParams (p); e.prepare (sr, 512);
        std::vector<float> z ((size_t) sr * 4, 0.0f);
        auto o = render (e, z, nullptr, true, {}, p);
        std::printf ("    HISS %.0f dB -> measured %.1f dBFS RMS\n", hdb, db (rms (o.L, (size_t) sr)));
    }
    CrookedEngine e; auto p = defaults(); p.hissOn = true; e.setParams (p); e.prepare (sr, 512);
    std::vector<float> z ((size_t) sr * 3, 0.0f);
    auto o = render (e, z, nullptr, true, [&] (int pos, EngineParams& q) { q.hissOn = pos < sr; }, p);
    CHECK (peakAbs (o.L, (size_t) (sr * 1.5)) == 0.0f, "hiss not exactly silent after switching off");
    std::printf ("    switched off -> exact digital silence: %s\n", peakAbs (o.L, (size_t) (sr * 1.5)) == 0.0f ? "yes" : "NO");
}

int main (int argc, char** argv)
{
    enableFtz();
    if (argc > 1 && std::string (argv[1]) == "move") { testRatesAndMovement(); return failures; }
    if (argc > 1 && std::string (argv[1]) == "click") { testClicks(); return failures; }
    testSilence();
    testDryExact();
    testZeroLatency();
    testExtremes();
    testClicks();
    testMonoAndWidth();
    testRatesAndMovement();
    testHiss();
    std::printf ("\n%s (%d failures)\n", failures == 0 ? "ALL ENGINE TESTS PASSED" : "ENGINE TESTS FAILED", failures);
    return failures == 0 ? 0 : 1;
}
CROOKED_DOUBLE_EOF
cat > "$DEST/tests/StateTests.cpp" <<'CROOKED_DOUBLE_EOF'
// CROOKED DOUBLE - plugin-level tests: presets, state save/restore, bus layouts, editor snapshot
#include <juce_audio_utils/juce_audio_utils.h>
#include "PluginProcessor.h"
#include "PluginEditor.h"
#include <cstdio>

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf ("  FAIL: "); std::printf (__VA_ARGS__); std::printf ("\n"); } } while (0)

using namespace juce;

static std::vector<float> snapshot (CrookedDoubleProcessor& p)
{
    std::vector<float> v;
    for (auto* prm : p.getParameters()) v.push_back (prm->getValue());
    return v;
}

static float valueOf (CrookedDoubleProcessor& p, const char* id)
{
    auto* prm = p.apvts.getParameter (id);
    return prm->convertFrom0to1 (prm->getValue());
}

int main (int argc, char** argv)
{
    ScopedJuceInitialiser_GUI gui;

    std::printf ("[A] Presets apply exactly and survive save/restore\n");
    {
        CrookedDoubleProcessor p;
        for (int i = 0; i < p.getNumPrograms(); ++i)
        {
            p.setCurrentProgram (i);
            const auto& pr = kPresets[i];
            const bool ok = std::abs (valueOf (p, ids::doubleLevel) - pr.doubleDb) < 0.06f
                         && std::abs (valueOf (p, ids::distance) - pr.distanceMs) < 0.06f
                         && std::abs (valueOf (p, ids::drift) - pr.drift) < 0.06f
                         && std::abs (valueOf (p, ids::nerves) - pr.nerves) < 0.06f
                         && std::abs (valueOf (p, ids::crooked) - pr.crooked) < 0.06f
                         && std::abs (valueOf (p, ids::wear) - pr.wear) < 0.06f
                         && std::abs (valueOf (p, ids::width) - pr.width) < 0.06f
                         && std::abs (valueOf (p, ids::output) - pr.outputDb) < 0.06f
                         && (valueOf (p, ids::mode) >= 0.5f) == pr.broken;
            CHECK (ok, "preset %d (%s) did not apply exactly", i, pr.name);

            MemoryBlock mb; p.getStateInformation (mb);
            CrookedDoubleProcessor q;
            q.setStateInformation (mb.getData(), (int) mb.getSize());
            CHECK (snapshot (q) == snapshot (p), "preset %d state did not restore", i);
            CHECK (q.getCurrentProgram() == i, "program index %d not restored (%d)", i, q.getCurrentProgram());
            std::printf ("    %-16s ok\n", pr.name);
        }
    }

    std::printf ("[B] Random settings incl. switches restore bit-exactly; garbage state is ignored\n");
    {
        Random r (1234);
        for (int trial = 0; trial < 50; ++trial)
        {
            CrookedDoubleProcessor p;
            for (auto* prm : p.getParameters())
            {
                const float v = r.nextFloat();
                prm->setValueNotifyingHost (prm->isDiscrete() ? (v < 0.5f ? 0.0f : 1.0f) : v);
            }
            MemoryBlock mb; p.getStateInformation (mb);
            CrookedDoubleProcessor q;
            q.setStateInformation (mb.getData(), (int) mb.getSize());
            CHECK (snapshot (q) == snapshot (p), "random state %d did not restore", trial);
        }
        CrookedDoubleProcessor p;
        auto before = snapshot (p);
        const char junk[] = "not a state at all";
        p.setStateInformation (junk, (int) sizeof (junk));
        p.setStateInformation (nullptr, 0);
        CHECK (snapshot (p) == before, "garbage state changed parameters");
    }

    std::printf ("[C] Bus layouts\n");
    {
        CrookedDoubleProcessor p;
        auto L = [] (AudioChannelSet in, AudioChannelSet out) { AudioProcessor::BusesLayout l; l.inputBuses.add (in); l.outputBuses.add (out); return l; };
        CHECK (p.checkBusesLayoutSupported (L (AudioChannelSet::mono(), AudioChannelSet::mono())), "mono>mono rejected");
        CHECK (p.checkBusesLayoutSupported (L (AudioChannelSet::mono(), AudioChannelSet::stereo())), "mono>stereo rejected");
        CHECK (p.checkBusesLayoutSupported (L (AudioChannelSet::stereo(), AudioChannelSet::stereo())), "stereo>stereo rejected");
        CHECK (! p.checkBusesLayoutSupported (L (AudioChannelSet::stereo(), AudioChannelSet::mono())), "stereo>mono accepted");
        CHECK (! p.checkBusesLayoutSupported (L (AudioChannelSet::create5point1(), AudioChannelSet::create5point1())), "5.1 accepted");
    }

    std::printf ("[D] Processor renders: every layout, rate and block size; dry exact with DOUBLE off; zero latency\n");
    {
        for (double sr : { 44100.0, 48000.0, 88200.0, 96000.0 })
        {
            for (int layout = 0; layout < 3; ++layout)
            {
                CrookedDoubleProcessor p;
                const int ins = layout == 2 ? 2 : 1, outs = layout == 0 ? 1 : 2;
                AudioProcessor::BusesLayout l;
                l.inputBuses.add (AudioChannelSet::canonicalChannelSet (ins));
                l.outputBuses.add (AudioChannelSet::canonicalChannelSet (outs));
                CHECK (p.setBusesLayout (l), "could not set layout");
                p.setCurrentProgram (5); // Losing the Plot
                p.prepareToPlay (sr, 1024);
                CHECK (p.getLatencySamples() == 0, "latency reported");

                Random r (7);
                const int total = (int) sr * 2;
                AudioBuffer<float> buf (2, 1024);
                MidiBuffer midi;
                bool finite = true;
                for (int pos = 0; pos < total;)
                {
                    const int n = 1 + r.nextInt (1024);
                    buf.setSize (2, n, false, false, true);
                    for (int c = 0; c < ins; ++c)
                        for (int i = 0; i < n; ++i) buf.setSample (c, i, 0.3f * std::sin (0.03f * (float) (pos + i) * (1 + c)));
                    p.processBlock (buf, midi);
                    for (int c = 0; c < outs; ++c)
                        for (int i = 0; i < n; ++i) finite &= std::isfinite (buf.getSample (c, i));
                    pos += n;
                }
                CHECK (finite, "non finite output sr %.0f layout %d", sr, layout);

                // DOUBLE off, OUTPUT 0 dB, DOUBLE ONLY off: bit exact dry
                p.apvts.getParameter (ids::doubleLevel)->setValueNotifyingHost (0.0f);
                p.apvts.getParameter (ids::output)->setValueNotifyingHost (p.apvts.getParameter (ids::output)->convertTo0to1 (0.0f));
                p.reset();
                bool exact = true;
                for (int blk = 0; blk < 40; ++blk)
                {
                    buf.setSize (2, 512, false, false, true);
                    AudioBuffer<float> ref (2, 512);
                    for (int c = 0; c < ins; ++c)
                        for (int i = 0; i < 512; ++i) { const float v = 0.4f * std::sin (0.01f * (float) (blk * 512 + i) * (1 + c)); buf.setSample (c, i, v); ref.setSample (c, i, v); }
                    if (ins == 1) ref.copyFrom (1, 0, ref, 0, 0, 512);
                    p.processBlock (buf, midi);
                    for (int c = 0; c < outs; ++c)
                        for (int i = 0; i < 512; ++i) exact &= buf.getSample (c, i) == ref.getSample (c, i);
                }
                CHECK (exact, "dry not bit exact sr %.0f layout %d", sr, layout);
            }
        }
        std::printf ("    done\n");
    }

    std::printf ("[E] Editor builds, animates and snapshots\n");
    {
        CrookedDoubleProcessor p;
        p.prepareToPlay (48000.0, 512);
        std::unique_ptr<AudioProcessorEditor> ed (p.createEditor());
        CHECK (ed != nullptr && ed->getWidth() == 800 && ed->getHeight() == 440, "editor size");

        // feed audio so the movement display shows real state
        AudioBuffer<float> buf (2, 512); MidiBuffer midi;
        for (int blk = 0; blk < 600; ++blk)
        {
            for (int c = 0; c < 2; ++c)
                for (int i = 0; i < 512; ++i) buf.setSample (c, i, 0.3f * std::sin (0.04f * (float) (blk * 512 + i)));
            p.processBlock (buf, midi);
            if (blk % 16 == 0) MessageManager::getInstance()->runDispatchLoopUntil (5);
        }
        if (argc > 1)
        {
            auto img = ed->createComponentSnapshot (ed->getLocalBounds(), true, 2.0f);
            File out { String (argv[1]) };
            out.deleteFile();
            FileOutputStream fos (out);
            PNGImageFormat().writeImageToStream (img, fos);
            std::printf ("    snapshot written to %s\n", argv[1]);
        }
        ed.reset();
    }

    std::printf ("\n%s (%d failures)\n", failures == 0 ? "ALL STATE TESTS PASSED" : "STATE TESTS FAILED", failures);
    return failures == 0 ? 0 : 1;
}
CROOKED_DOUBLE_EOF
}

say "Writing source project to $DEST"
write_sources
[ "$MODE" = "--extract-only" ] && { echo "Done. Source is in $DEST"; exit 0; }

[ "$(uname -s)" = "Darwin" ] || { echo "Building needs macOS. Source has been written to $DEST."; exit 1; }

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang++ >/dev/null 2>&1; then
    say "Xcode Command Line Tools are needed. A macOS installer window will open."
    xcode-select --install || true
    echo "When that installer has finished, run this script again."
    exit 1
fi

if command -v cmake >/dev/null 2>&1; then
    CMAKE_BIN="$(command -v cmake)"
elif [ -x /Applications/CMake.app/Contents/bin/cmake ]; then
    CMAKE_BIN=/Applications/CMake.app/Contents/bin/cmake
else
    CMAKE_BIN="$DEST/.tools/cmake-3.30.5-macos-universal/CMake.app/Contents/bin/cmake"
    if [ ! -x "$CMAKE_BIN" ]; then
        say "Downloading CMake 3.30.5 into the project folder (no system install)"
        mkdir -p "$DEST/.tools"
        curl -fL --progress-bar -o "$DEST/.tools/cmake.tgz" \
            https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-macos-universal.tar.gz
        tar -xzf "$DEST/.tools/cmake.tgz" -C "$DEST/.tools"
        rm -f "$DEST/.tools/cmake.tgz"
    fi
fi
echo "Using $("$CMAKE_BIN" --version | head -1)"

TESTS=OFF; [ "$MODE" = "--test" ] && TESTS=ON
JOBS="$(sysctl -n hw.ncpu)"

say "Configuring (the first run downloads JUCE, a minute or two)"
"$CMAKE_BIN" -S "$DEST" -B "$DEST/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCROOKED_BUILD_TESTS=$TESTS

say "Building VST3 and AU"
"$CMAKE_BIN" --build "$DEST/build" --config Release -j "$JOBS" --target CrookedDouble_VST3 CrookedDouble_AU

ART="$DEST/build/CrookedDouble_artefacts/Release"
VST3_DIR="$HOME/Library/Audio/Plug-Ins/VST3"
AU_DIR="$HOME/Library/Audio/Plug-Ins/Components"
VST3="$VST3_DIR/CROOKED DOUBLE.vst3"
AU="$AU_DIR/CROOKED DOUBLE.component"

say "Installing"
mkdir -p "$VST3_DIR" "$AU_DIR"
rm -rf "$VST3" "$AU"
cp -R "$ART/VST3/CROOKED DOUBLE.vst3" "$VST3"
cp -R "$ART/AU/CROOKED DOUBLE.component" "$AU"
codesign --force --deep --sign - "$VST3"
codesign --force --deep --sign - "$AU"
xattr -dr com.apple.quarantine "$VST3" "$AU" 2>/dev/null || true
lipo -archs "$VST3/Contents/MacOS/CROOKED DOUBLE" 2>/dev/null | sed 's/^/VST3 architectures: /' || true

say "Checking the AU with auval"
killall -9 AudioComponentRegistrar 2>/dev/null || true
if auval -v aufx Crkd Ldsa > "$DEST/auval.log" 2>&1; then
    echo "auval: PASS"
else
    echo "auval: FAILED (details in $DEST/auval.log). The VST3 is unaffected."
fi

if [ "$TESTS" = ON ]; then
    say "Building and running tests"
    "$CMAKE_BIN" --build "$DEST/build" --config Release -j "$JOBS" --target CrookedEngineTests CrookedStateTests
    "$DEST/build/CrookedEngineTests"
    "$DEST/build/CrookedStateTests_artefacts/Release/CrookedStateTests" "$DEST/ui-snapshot.png"
fi

say "Installed"
echo "  $VST3"
echo "  $AU"
echo
echo "In Live 12: Settings > Plug-Ins > turn on 'Use VST3 Plug-In System Folders' and 'Use Audio Units v2',"
echo "click Rescan, then find it under Plug-Ins > LDS Audio > CROOKED DOUBLE."
