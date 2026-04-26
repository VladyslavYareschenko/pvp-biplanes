#pragma once
#include <cstdint>

namespace constants
{
    static constexpr uint32_t tickRate        {120};
    static constexpr uint32_t snapshotRate    {30};
    static constexpr uint8_t  defaultWinScore {10};

    static constexpr float baseWidth  {256.f};
    static constexpr float baseHeight {208.f};

    namespace plane
    {
        static constexpr uint8_t maxHp {2};

        static constexpr float sizeX {24.f / baseWidth};
        static constexpr float sizeY {24.f / baseHeight};

        static constexpr float hitboxSizeX   {sizeX / 3.f * 2.f};
        static constexpr float hitboxSizeY   {sizeY / 3.f * 2.f};
        static constexpr float hitboxDiameter{hitboxSizeX};
        static constexpr float hitboxRadius  {0.5f * hitboxDiameter};
        static constexpr float hitboxOffset  {0.1f * sizeX};

        static constexpr float bulletSpawnOffset {hitboxOffset + hitboxRadius};

        static constexpr float groundCollision {182.f / baseHeight};

        static constexpr uint8_t directionCount {16};
        static constexpr float   pitchStep      {360.f / directionCount};

        static constexpr float acceleration         {0.5f};
        static constexpr float deceleration         {0.5f * acceleration};
        static constexpr float takeoffAcceleration  {0.85f * acceleration};
        static constexpr float takeoffDeceleration  {0.75f * acceleration};
        static constexpr float diveAcceleration     {0.2f  * acceleration};
        static constexpr float abandonedDeceleration{0.2f  * acceleration};

        static constexpr float maxSpeedBase     {0.303f};
        static constexpr float maxSpeedBoosted  {0.43478f};
        static constexpr float maxSpeedAbandoned{0.5f * maxSpeedBase};

        static constexpr double deadCooldown           {3.0};
        static constexpr double spawnProtectionCooldown{2.0};
        static constexpr double pitchCooldown          {0.1};
        static constexpr double shootCooldown          {0.65};

        static constexpr float spawnBlueX {16.f / baseWidth};
        static constexpr float spawnRedX  {(baseWidth - 16.f) / baseWidth};
        static constexpr float spawnY     {180.44f / baseHeight};

        static constexpr float spawnRotationBlue {67.5f};
        static constexpr float spawnRotationRed  {292.5f};

        static constexpr float takeoffDirectionBlue {90.f};
        static constexpr float takeoffDirectionRed  {270.f};

        static constexpr float jumpDirOffsetBlue {-90.f};
        static constexpr float jumpDirOffsetRed  { 90.f};
    }

    namespace joystick
    {
        // Maximum rotation rate (degrees per second) at low speed.
        static constexpr float maxTurnRate      = 250.0f;
        // Angular-velocity smoothing factor (higher = snappier response, less inertia).
        static constexpr float angularSmoothing = 10.0f;
        // Angular-velocity decay factor when in dead zone (higher = faster stop).
        static constexpr float angularDecay     = 12.0f;
        // Minimum airspeed maintained while joystick is active (prevents full stall).
        static constexpr float minSpeed         = 0.10f;
        // How much high speed reduces turn rate:
        //   effectiveRate = maxTurnRate * (1 - speedTurnFactor * speed/maxSpeedBoosted)
        static constexpr float speedTurnFactor  = 0.4f;
        // Magnitude dead-zone threshold (below this, steer is suppressed).
        static constexpr float deadZone         = 0.10f;
        // Magnitude above which full acceleration is applied.
        static constexpr float accelThreshold   = 0.60f;
        // Magnitude below which deceleration (toward minSpeed) is applied.
        static constexpr float decelThreshold   = 0.35f;
    }

    namespace smoke
    {
        static constexpr double  frameTime  {0.1};
        static constexpr uint8_t frameCount {5};
        static constexpr double  cooldown   {1.0};
    }

    namespace fire
    {
        static constexpr double  frameTime  {0.075};
        static constexpr uint8_t frameCount {3};
    }

    namespace bullet
    {
        static constexpr float speed          {0.77f};
        static constexpr float groundCollision{186.16f / baseHeight};
    }

    namespace barn
    {
        static constexpr float sizeX {35.f / baseWidth};
        static constexpr float sizeY {22.f / baseHeight};

        static constexpr float planeCollisionX {0.5f - sizeX * 0.5f};
        static constexpr float planeCollisionY {163.904f / baseHeight};

        static constexpr float pilotCollisionLeftX  {0.5f - sizeX * 0.475f};
        static constexpr float pilotCollisionRightX {0.5f + sizeX * 0.475f};

        static constexpr float bulletCollisionX    {0.5f - sizeX * 0.475f};
        static constexpr float bulletCollisionY    {168.48f / baseHeight};
        static constexpr float bulletCollisionSizeX{sizeX * 0.95f};
    }

    namespace pilot
    {
        static constexpr float sizeX           {7.f / baseWidth};
        static constexpr float sizeY           {7.f / baseHeight};
        static constexpr float groundCollision {185.64f / baseHeight};

        static constexpr float gravity            {0.2f};
        static constexpr float ejectSpeed         {0.45f};
        static constexpr float runSpeed           {25.6f / baseWidth};
        static constexpr float safeLandingSpeed   {gravity};

        static constexpr float maxSpeedXThreshold    {2.048f / baseWidth};
        static constexpr float speedXSlowdownFactor  {1.f};

        static constexpr double runFrameTime  {0.075};
        static constexpr double fallFrameTime {0.1};

        namespace chute
        {
            static constexpr float sizeX   {20.f / baseWidth};
            static constexpr float sizeY   {12.f / baseHeight};
            static constexpr float offsetY {1.375f * chute::sizeY};

            static constexpr double frameTime {0.25};

            static constexpr float baseSpeedX {10.24f / baseWidth};
            static constexpr float baseSpeedY {16.64f / baseHeight};

            static constexpr float speedXSlowdownFactor {2.f};
            static constexpr float speedYSlowdownFactor {0.5f};
        }

        namespace angel
        {
            static constexpr float  ascentRate    {7.28f / baseHeight};
            static constexpr double frameTime     {0.138};
            static constexpr uint8_t frameCount   {4};
            static constexpr uint8_t framePastLoopId{3};
            static constexpr uint8_t loopCount    {6};
        }
    }
}
