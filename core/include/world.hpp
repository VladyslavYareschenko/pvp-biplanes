#pragma once
#include <core/include/plane.hpp>
#include <core/include/bullet.hpp>
#include <core/include/types.hpp>

#include <cstdint>

struct PlayerInput {
    PlaneThrottle throttle{PlaneThrottle::Idle};
    PlanePitch    pitch   {PlanePitch::Idle};
    bool          shoot   {};
    bool          jump    {};
};

struct GameWorld
{
    static constexpr float TICK_DT = 1.0f / 120.0f;

    Plane         planes[2] { Plane{PlaneType::Blue}, Plane{PlaneType::Red} };
    BulletSpawner bullets   {};

    bool    roundRunning  {false};
    bool    roundFinished {false};
    int     winnerId      {-1};   // -1=none, 0=Blue, 1=Red
    uint8_t winScore      {10};
    uint64_t tick         {0};

    GameWorld();

    void startRound();
    void update(const PlayerInput inputs[2]);
    void reset();

private:
    void applyInput(int playerIdx, const PlayerInput& input);
    void checkWinCondition();
    void handleRespawns();
};
