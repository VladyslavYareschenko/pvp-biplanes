#pragma once

#include <common/include/protocol.hpp>
#include <core/include/world.hpp>

#include <cmath>
#include <cstdint>
#include <deque>
#include <utility>

// ---------------------------------------------------------------------------
// ClientPredictor
//
// Runs a shadow GameWorld that advances on every local input tick so the
// local player's plane moves without waiting for a server round-trip.
// When a server snapshot arrives, the prediction is reconciled: the world
// is reset to the authoritative state and all inputs sent after the last
// acknowledged tick are re-simulated.
//
// Usage (online loop):
//   // Each display/game tick — apply current input and advance shadow world:
//   pred.applyInput(localTick, humanInput);
//
//   // Each received server snapshot:
//   pred.reconcile(serverSnapshot);
//
//   // When building the render frame:
//   PlaneSnapshot mine = pred.localPlane();   // smooth, predicted
//   // Remote plane comes from SnapshotInterpolator (server-authoritative).
// ---------------------------------------------------------------------------
class ClientPredictor
{
public:
    static constexpr int MAX_HISTORY = 256;  // ~2 seconds at 120 Hz

    explicit ClientPredictor(int playerId = 0)
        : _playerId(playerId)
    {
        _world.startRound();
    }

    void setPlayerId(int id) { _playerId = id; }

    // Number of inputs in the unacknowledged history (i.e. what will be replayed).
    std::size_t historySize() const { return _history.size(); }

    // Reduce the visual correction offset — call once per rendered frame.
    // dtMs is the actual elapsed milliseconds since the previous frame.
    // The correction blends out with a ~60 ms half-life so the player never
    // sees a sudden snap; the physics world is always at the reconciled state.
    void blendStep(double dtMs)
    {
        constexpr double HALF_LIFE_MS = 60.0;
        const float factor     = static_cast<float>(std::pow(0.5, dtMs / HALF_LIFE_MS));
        const float factorDir  = static_cast<float>(std::pow(0.5, dtMs / DIR_BLEND_HALF_LIFE_MS));
        _visualOffsetX      *= factor;
        _visualOffsetY      *= factor;
        _visualOffsetDir    *= factorDir;
        _visualOffsetPilotX *= factor;
        _visualOffsetPilotY *= factor;
        if (std::fabs(_visualOffsetX)      < 1e-4f) _visualOffsetX      = 0.f;
        if (std::fabs(_visualOffsetY)      < 1e-4f) _visualOffsetY      = 0.f;
        if (std::fabs(_visualOffsetDir)    < 1e-3f) _visualOffsetDir    = 0.f;
        if (std::fabs(_visualOffsetPilotX) < 1e-4f) _visualOffsetPilotX = 0.f;
        if (std::fabs(_visualOffsetPilotY) < 1e-4f) _visualOffsetPilotY = 0.f;
    }

    // Advance the shadow world by one tick with the local player's input.
    // Call this once per local game tick.
    void applyInput(uint64_t localTick, const PlayerInput& input)
    {
        // Build a two-player input array; use zero input for the remote player
        // since we have no prediction for them.
        PlayerInput inputs[2]{};
        inputs[_playerId]     = input;
        inputs[1 - _playerId] = PlayerInput{};  // neutral

        _world.update(inputs);

        _history.push_back({localTick, input});
        while (static_cast<int>(_history.size()) > MAX_HISTORY)
            _history.pop_front();
    }

    // Reconcile with an authoritative server snapshot.
    // Resets the shadow world to the snapshot state, then re-simulates all
    // local inputs that the server has not yet processed.
    // Any sudden position jump is absorbed into _visualOffset so the rendered
    // position blends smoothly to the corrected physics (see blendStep).
    void reconcile(const GameSnapshot& snap)
    {
        const uint64_t ackedTick = snap.lastAckedInputTick[_playerId];

        // Drop history entries the server has already consumed.
        while (!_history.empty() && _history.front().first <= ackedTick)
            _history.pop_front();

        // Save physics position before resetting (for correction blending).
        const PlaneSnapshot prePhy = GameSnapshot::fromPlane(_world.planes[_playerId]);

        // Restore authoritative state.
        restoreFromSnapshot(snap);

        // Re-simulate remaining unacknowledged inputs.
        for (const auto& [tick, input] : _history)
        {
            (void)tick;
            PlayerInput inputs[2]{};
            inputs[_playerId]     = input;
            inputs[1 - _playerId] = PlayerInput{};
            _world.update(inputs);
        }

        // Accumulate visual offset so the rendered plane doesn't jump.
        // Large corrections (e.g. respawn teleport) skip blending and snap.
        const PlaneSnapshot postPhy = GameSnapshot::fromPlane(_world.planes[_playerId]);
        const float dx = prePhy.x - postPhy.x;
        const float dy = prePhy.y - postPhy.y;
        const float dist = std::sqrt(dx * dx + dy * dy);
        if (dist > 1e-4f && dist < MAX_BLEND_OFFSET)
        {
            _visualOffsetX += dx;
            _visualOffsetY += dy;
            // Clamp the total accumulated offset.
            const float total = std::sqrt(_visualOffsetX * _visualOffsetX +
                                          _visualOffsetY * _visualOffsetY);
            if (total > MAX_BLEND_OFFSET)
            {
                const float s = MAX_BLEND_OFFSET / total;
                _visualOffsetX *= s;
                _visualOffsetY *= s;
            }
        }
        else if (dist >= MAX_BLEND_OFFSET)
        {
            // Large jump — snap immediately, clear any residual offset.
            _visualOffsetX = 0.f;
            _visualOffsetY = 0.f;
        }

        // Direction blending: accumulate shortest-path angle correction.
        const float dDir = shortestAngleDiff(postPhy.dir, prePhy.dir);
        if (std::fabs(dDir) > 1e-3f && std::fabs(dDir) < MAX_BLEND_DIR)
        {
            _visualOffsetDir += dDir;
            // Clamp accumulated direction offset.
            if (std::fabs(_visualOffsetDir) > MAX_BLEND_DIR)
                _visualOffsetDir = std::copysign(MAX_BLEND_DIR, _visualOffsetDir);
        }
        else if (std::fabs(dDir) >= MAX_BLEND_DIR)
        {
            // Large direction snap (e.g. respawn) — clear direction offset.
            _visualOffsetDir = 0.f;
        }

        // Pilot position blending: same approach, but only while pilot is
        // active both before and after reconcile (skip on eject/death transitions).
        if (prePhy.hasJumped && postPhy.hasJumped)
        {
            const float dpx  = prePhy.pilot.x - postPhy.pilot.x;
            const float dpy  = prePhy.pilot.y - postPhy.pilot.y;
            const float pdist = std::sqrt(dpx * dpx + dpy * dpy);
            if (pdist > 1e-4f && pdist < MAX_BLEND_OFFSET)
            {
                _visualOffsetPilotX += dpx;
                _visualOffsetPilotY += dpy;
                const float ptotal = std::sqrt(_visualOffsetPilotX * _visualOffsetPilotX +
                                               _visualOffsetPilotY * _visualOffsetPilotY);
                if (ptotal > MAX_BLEND_OFFSET)
                {
                    const float s = MAX_BLEND_OFFSET / ptotal;
                    _visualOffsetPilotX *= s;
                    _visualOffsetPilotY *= s;
                }
            }
            else if (pdist >= MAX_BLEND_OFFSET)
            {
                _visualOffsetPilotX = 0.f;
                _visualOffsetPilotY = 0.f;
            }
        }
        else
        {
            // Pilot state changed (just ejected or died) — clear pilot offset.
            _visualOffsetPilotX = 0.f;
            _visualOffsetPilotY = 0.f;
        }
    }

    // The smoothly-predicted plane for the local player.
    // Returns the physics position blended with any pending visual correction.
    PlaneSnapshot localPlane() const
    {
        PlaneSnapshot ps = GameSnapshot::fromPlane(_world.planes[_playerId]);
        ps.x         += _visualOffsetX;
        ps.y         += _visualOffsetY;
        ps.dir       += _visualOffsetDir;
        ps.pilot.x   += _visualOffsetPilotX;
        ps.pilot.y   += _visualOffsetPilotY;
        return ps;
    }

    // Pure physics position — no visual correction applied.
    // Use this for logging reconcile corrections (pre/post physics delta).
    PlaneSnapshot physicsLocalPlane() const
    {
        return GameSnapshot::fromPlane(_world.planes[_playerId]);
    }

    // Reset to a fresh round (e.g. on new game).
    void reset(int playerId)
    {
        _playerId = playerId;
        _world    = GameWorld{};
        _world.startRound();
        _history.clear();
        _visualOffsetX      = 0.f;
        _visualOffsetY      = 0.f;
        _visualOffsetDir    = 0.f;
        _visualOffsetPilotX = 0.f;
        _visualOffsetPilotY = 0.f;
    }

private:
    // Position corrections larger than this snap immediately; smaller ones blend smoothly.
    static constexpr float MAX_BLEND_OFFSET = 0.25f;
    // Direction corrections (degrees) larger than this snap immediately.
    static constexpr float MAX_BLEND_DIR    = 45.f;
    // Direction blend half-life (ms) — longer than position so angle pops are invisible.
    static constexpr double DIR_BLEND_HALF_LIFE_MS = 120.0;

    int       _playerId{0};
    GameWorld _world{};

    using HistoryEntry = std::pair<uint64_t, PlayerInput>;
    std::deque<HistoryEntry> _history{};

    // Visual blending: offset added to localPlane() output while it decays.
    // Keeps the rendered plane/pilot from jumping when reconcile makes a correction.
    float _visualOffsetX      {0.f};
    float _visualOffsetY      {0.f};
    float _visualOffsetDir    {0.f};  // degrees, shortest-path direction correction
    float _visualOffsetPilotX {0.f};
    float _visualOffsetPilotY {0.f};

    // Returns the signed shortest-path delta from angle a to angle b (degrees).
    static float shortestAngleDiff(float a, float b)
    {
        float d = b - a;
        while (d >  180.f) d -= 360.f;
        while (d < -180.f) d += 360.f;
        return d;
    }

    // Restore world state from an authoritative snapshot.
    void restoreFromSnapshot(const GameSnapshot& snap)
    {
        _world.tick          = snap.tick;
        _world.roundRunning  = snap.roundRunning;
        _world.roundFinished = snap.roundFinished;
        _world.winnerId      = snap.winnerId;

        for (int i = 0; i < 2; ++i)
            applyPlaneSnapshot(_world.planes[i], snap.planes[i]);

        // We do not restore bullets — they are always taken from the
        // interpolated snapshot during rendering.
    }

    static void applyPlaneSnapshot(Plane& plane, const PlaneSnapshot& ps)
    {
        // Approximate the speed vector from speed + direction.
        const float rad = ps.dir * (3.14159265f / 180.f);
        plane.setPredictionState(
            ps.x, ps.y, ps.dir, ps.speed,
            ps.speed * std::sin(rad), -ps.speed * std::cos(rad),
            ps.isDead, ps.isOnGround, ps.isTakingOff, ps.hasJumped,
            ps.hp, ps.deadCooldownRemaining, ps.protectionRemaining);
        if (ps.hasJumped)
            plane.setPilotPredictionState(ps.pilot.x, ps.pilot.y);
    }
};
