#include <core/include/bot.hpp>
#include <core/include/plane.hpp>
#include <core/include/math.hpp>
#include <core/include/constants.hpp>

#include <cmath>
#include <algorithm>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
namespace {

// Shortest angular distance from 'from' to 'to' in range [-180, 180]
static float angleDiff(float from, float to)
{
    float d = std::fmod(to - from + 540.f, 360.f) - 180.f;
    return d;
}

// Angle (degrees, 0=up, clockwise) from point (sx,sy) to (tx,ty)
static float angleToPoint(float sx, float sy, float tx, float ty)
{
    const float dx = tx - sx;
    const float dy = ty - sy;
    float a = std::atan2(dx, -dy) * 180.f / static_cast<float>(M_PI);
    if (a < 0.f) a += 360.f;
    return a;
}

static float distSq(float ax, float ay, float bx, float by)
{
    return (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
}

// Check if flying toward ground/barn within the next ~0.4 seconds
static bool isAboutToCrash(const Plane& p)
{
    namespace plane = constants::plane;
    namespace barn  = constants::barn;

    const float rad = p.dir() * static_cast<float>(M_PI) / 180.f;
    const float lookahead = 0.4f;
    const float fx = p.x() + p.speed() * std::sin(rad) * lookahead;
    const float fy = p.y() - p.speed() * std::cos(rad) * lookahead;

    if (fy >= plane::groundCollision) return true;

    const bool barnX = fx > barn::planeCollisionX &&
                       fx < barn::planeCollisionX + barn::sizeX;
    const bool barnY = fy > barn::planeCollisionY;
    if (barnX && barnY) return true;

    return false;
}

// True if any incoming bullet is on a collision course within proximity
static bool bulletThreat(const Plane& self, const std::vector<Bullet>& bullets)
{
    namespace p = constants::plane;
    constexpr float dangerDist = 0.06f;

    for (const auto& b : bullets) {
        if (b.firedBy() == self.type()) continue;
        if (distSq(b.x(), b.y(), self.x(), self.y()) < dangerDist * dangerDist)
            return true;
    }
    return false;
}

} // anonymous namespace

// ---------------------------------------------------------------------------
// BotAI
// ---------------------------------------------------------------------------
BotAI::BotAI(BotDifficulty difficulty)
    : mDifficulty{difficulty}
{
    switch (difficulty) {
        case BotDifficulty::Easy:   mReactionDelay = 0.35f; break;
        case BotDifficulty::Medium: mReactionDelay = 0.20f; break;
        case BotDifficulty::Hard:   mReactionDelay = 0.08f; break;
    }
    mReactionTimer = mReactionDelay;
}

PlayerInput BotAI::think(const Plane& self, const Plane& opponent,
                          const std::vector<Bullet>& bullets, float dt)
{
    mReactionTimer -= dt;
    if (mReactionTimer <= 0.f) {
        mReactionTimer = mReactionDelay;
        if (self.hasJumped())
            mCachedInput = computePilotInput(self, opponent);
        else
            mCachedInput = computePlaneInput(self, opponent, bullets);
    }
    return mCachedInput;
}

// ---------------------------------------------------------------------------
// Plane AI
// ---------------------------------------------------------------------------
PlayerInput BotAI::computePlaneInput(const Plane& self, const Plane& opponent,
                                      const std::vector<Bullet>& bullets)
{
    namespace plane = constants::plane;

    PlayerInput in{};

    if (self.isPlaneBodyDead() || self.isOnGround()) {
        // Take off: just throttle up
        in.throttle = PlaneThrottle::Increase;
        return in;
    }

    // --- Crash avoidance (highest priority) ---
    const bool crashing = isAboutToCrash(self);
    if (crashing) {
        // Turn toward sky (straight up = dir 0)
        const float diffUp = angleDiff(self.dir(), 0.f);
        in.pitch    = (diffUp < 0.f) ? PlanePitch::Left : PlanePitch::Right;
        in.throttle = PlaneThrottle::Increase;
        return in;
    }

    // --- Bullet evasion ---
    const bool threatened = bulletThreat(self, bullets);
    if (threatened && mDifficulty != BotDifficulty::Easy) {
        // Jink: turn perpendicular to current heading
        in.pitch    = PlanePitch::Right;
        in.throttle = PlaneThrottle::Increase;
        return in;
    }

    // --- Find shortest path to opponent (handle X wrapping) ---
    const float opX  = opponent.pilot.x();
    const float opY  = opponent.pilot.y();
    const float opXL = opX - 1.f;
    const float opXR = opX + 1.f;

    // Pick wrapped position that is closest
    float targetX = opX;
    if (distSq(self.x(), self.y(), opXL, opY) < distSq(self.x(), self.y(), opX, opY))
        targetX = opXL;
    else if (distSq(self.x(), self.y(), opXR, opY) < distSq(self.x(), self.y(), opX, opY))
        targetX = opXR;
    const float targetY = opY;

    const float dirToOpponent   = angleToPoint(self.x(), self.y(), targetX, targetY);
    const float relAngle        = angleDiff(self.dir(), dirToOpponent);
    const float absRelAngle     = std::abs(relAngle);

    // --- Shoot ---
    const float aimCone = (mDifficulty == BotDifficulty::Easy)   ? 15.f
                        : (mDifficulty == BotDifficulty::Medium)  ? 10.f
                        :                                            6.f;
    if (absRelAngle <= aimCone && !opponent.isDead())
        in.shoot = true;

    // --- Bail when critically low HP ---
    if (self.hp() <= 1 && self.canJump() && !self.hasJumped()) {
        in.jump = true;
        return in;
    }

    // --- Turn toward opponent ---
    const float turnThresh = constants::plane::pitchStep;
    if (absRelAngle > turnThresh)
        in.pitch = (relAngle > 0.f) ? PlanePitch::Right : PlanePitch::Left;

    // --- Speed management ---
    const float targetSpeed = plane::maxSpeedBase * 0.85f;
    if (self.speed() < targetSpeed)
        in.throttle = PlaneThrottle::Increase;
    else if (self.speed() > plane::maxSpeedBase)
        in.throttle = PlaneThrottle::Decrease;

    return in;
}

// ---------------------------------------------------------------------------
// Pilot AI (after bailing out)
// ---------------------------------------------------------------------------
PlayerInput BotAI::computePilotInput(const Plane& self, const Plane& /*opponent*/)
{
    namespace barn = constants::barn;

    PlayerInput in{};

    // Always open chute if we can
    if (!self.pilot.isChuteOpen() && !self.pilot.isDead())
        in.jump = true;

    if (self.pilot.isRunning()) {
        // Walk toward barn center
        const float barnCenterX = 0.5f;
        const float dx = barnCenterX - self.pilot.x();
        if (std::abs(dx) > 0.01f)
            in.pitch = (dx > 0.f) ? PlanePitch::Right : PlanePitch::Left;
    }

    return in;
}
