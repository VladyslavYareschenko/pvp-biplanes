#pragma once

#include <common/include/protocol.hpp>

#include <array>
#include <cmath>
#include <cstdint>

// ---------------------------------------------------------------------------
// SnapshotInterpolator
//
// Keeps a small ring-buffer of timestamped GameSnapshots received from the
// server and produces a smoothly-interpolated snapshot at any requested
// render time.
//
// Usage:
//   On each received snapshot:   interp.push(snap, nowMs())
//   On each render frame:        auto s = interp.interpolated(nowMs() - renderDelayMs())
//
// renderDelayMs() should be at least 2× the snapshot interval so there are
// always two samples to interpolate between (e.g. 33 ms at 60 Hz snapshots).
//
// Virtual-time design:
//   Each snapshot carries a server tick. We convert that to a nominal virtual
//   time (tick × 1000/SERVER_TICK_RATE_HZ) that is perfectly uniformly
//   spaced, eliminating jitter from irregular packet arrival intervals.
//   A wall-clock → virtual-clock offset is tracked via an EMA so that
//   render queries expressed in wall-clock time are converted correctly.
// ---------------------------------------------------------------------------
class SnapshotInterpolator
{
public:
    static constexpr int    BUFFER_SIZE        = 8;
    // Server simulation rate (ticks/sec). Snapshots are sent every 2 ticks.
    static constexpr double SERVER_TICK_RATE_HZ = 120.0;

    // Push a newly received snapshot with its wall-clock arrival time (ms).
    void push(const GameSnapshot& snap, double recvTimeMs)
    {
        // Derive perfectly uniform virtual time from server tick.
        const double virtualMs = snap.tick * (1000.0 / SERVER_TICK_RATE_HZ);

        // Track clock offset: wall-clock − virtual (≈ network one-way delay).
        // Use a fast EMA so the first sample initialises instantly.
        const double sample = recvTimeMs - virtualMs;
        if (!_clockInitialised)
        {
            _clockOffset      = sample;
            _clockInitialised = true;
        }
        else
        {
            _clockOffset = 0.95 * _clockOffset + 0.05 * sample;
        }

        Entry& e    = _buf[_head];
        e.snap      = snap;
        e.timeMs    = virtualMs;          // store virtual (uniform) time
        _head       = (_head + 1) % BUFFER_SIZE;
        if (_count < BUFFER_SIZE) ++_count;
    }

    // Return an interpolated snapshot for a render time expressed in
    // wall-clock milliseconds (e.g. nowMs() - renderDelayMs).
    // Falls back gracefully when the buffer has < 2 entries.
    GameSnapshot interpolated(double renderWallMs) const
    {
        if (_count == 0) return GameSnapshot{};
        if (_count == 1) return entry(0).snap;

        // Convert wall-clock render time → virtual time.
        const double renderTimeMs = renderWallMs - _clockOffset;

        // Find the two entries that bracket renderTimeMs (latest first).
        const Entry* newer = nullptr;
        const Entry* older = nullptr;

        // Walk from newest → oldest; find first entry whose virtual time
        // <= renderTimeMs (that's our "older" sample).
        for (int i = 0; i < _count; ++i)
        {
            const Entry& e = entry(i);  // entry(0) = newest
            if (e.timeMs <= renderTimeMs)
            {
                older = &e;
                if (i > 0) newer = &entry(i - 1);
                break;
            }
        }

        // Render time is older than all buffered samples — clamp to newest.
        if (!older) return entry(0).snap;

        // Render time is newer than all samples — clamp to newest.
        if (!newer) return entry(0).snap;

        const double span = newer->timeMs - older->timeMs;
        const float  t    = (span > 0.001)
            ? static_cast<float>((renderTimeMs - older->timeMs) / span)
            : 1.0f;
        const float tc = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);

        return lerpSnapshots(older->snap, newer->snap, tc);
    }

    // Whether any snapshots have been received yet.
    bool empty() const { return _count == 0; }

    // Most recent raw snapshot (no interpolation).
    const GameSnapshot* latest() const
    {
        if (_count == 0) return nullptr;
        return &entry(0).snap;
    }

private:
    struct Entry {
        GameSnapshot snap{};
        double       timeMs{0.0};    // nominal virtual time (from server tick)
    };

    std::array<Entry, BUFFER_SIZE> _buf{};
    int    _head             {0};
    int    _count            {0};
    double _clockOffset      {0.0};  // wall-clock − virtual-time (≈ one-way delay)
    bool   _clockInitialised {false};

    // entry(0) = newest, entry(1) = one before that, ...
    const Entry& entry(int age) const
    {
        int idx = (_head - 1 - age + BUFFER_SIZE * 2) % BUFFER_SIZE;
        return _buf[idx];
    }

    // ---------------------------------------------------------------------------
    static float lerpAngle(float a, float b, float t)
    {
        // Shortest-path angle lerp (degrees).
        float diff = b - a;
        while (diff >  180.f) diff -= 360.f;
        while (diff < -180.f) diff += 360.f;
        return a + diff * t;
    }

    static float lerp(float a, float b, float t) { return a + (b - a) * t; }

    static PilotSnapshot lerpPilot(const PilotSnapshot& a,
                                   const PilotSnapshot& b,
                                   float t)
    {
        PilotSnapshot r = a;  // copy discrete state from the older sample
        r.x      = lerp(a.x,      b.x,      t);
        r.y      = lerp(a.y,      b.y,      t);
        r.speedX = lerp(a.speedX, b.speedX, t);
        r.speedY = lerp(a.speedY, b.speedY, t);
        return r;
    }

    static PlaneSnapshot lerpPlane(const PlaneSnapshot& a,
                                   const PlaneSnapshot& b,
                                   float t)
    {
        PlaneSnapshot r = a;  // copy discrete state from older sample
        // Don't lerp position across the alive↔dead boundary: the server
        // resets a dead plane to (0,0), so lerping would drag the visible
        // position toward the origin and corrupt the explosion spawn point.
        if (a.isDead == b.isDead)
        {
            r.x = lerp(a.x, b.x, t);
            r.y = lerp(a.y, b.y, t);
        }
        else
        {
            // Hold the alive snapshot's position until the transition is complete.
            const PlaneSnapshot& alive = a.isDead ? b : a;
            r.x = alive.x;
            r.y = alive.y;
        }
        r.dir   = lerpAngle(a.dir, b.dir, t);
        r.speed = lerp(a.speed, b.speed, t);
        r.deadCooldownRemaining = lerp(a.deadCooldownRemaining,
                                       b.deadCooldownRemaining, t);
        r.protectionRemaining   = lerp(a.protectionRemaining,
                                       b.protectionRemaining,   t);
        r.pilot = lerpPilot(a.pilot, b.pilot, t);
        return r;
    }

    static GameSnapshot lerpSnapshots(const GameSnapshot& a,
                                      const GameSnapshot& b,
                                      float t)
    {
        GameSnapshot r  = a;  // copy round/meta state from older sample
        r.planes[0]     = lerpPlane(a.planes[0], b.planes[0], t);
        r.planes[1]     = lerpPlane(a.planes[1], b.planes[1], t);
        // Bullets: use the newer snapshot directly (they move fast and
        // spawning/despawning makes lerp unreliable).
        r.bullets       = b.bullets;
        return r;
    }
};
