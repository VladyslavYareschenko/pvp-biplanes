#include <core/include/plane.hpp>
#include <core/include/constants.hpp>
#include <core/include/math.hpp>

#include <cmath>
#include <algorithm>

// ---------------------------------------------------------------------------
// Plane
// ---------------------------------------------------------------------------

Plane::Plane(PlaneType type)
    : mType{type}
{
    pilot.setPlane(this);
}

Plane::Plane(const Plane& o)
{
    *this = o;
}

Plane::Plane(Plane&& o) noexcept
{
    *this = std::move(o);
}

Plane& Plane::operator=(const Plane& o)
{
    if (this == &o) return *this;
    // Copy all data via memberwise copy of the base struct fields
    mType        = o.mType;
    mHp          = o.mHp;
    mScore       = o.mScore;
    mX           = o.mX;
    mY           = o.mY;
    mDir         = o.mDir;
    mSpeed       = o.mSpeed;
    mMaxSpeedVar = o.mMaxSpeedVar;
    mSpeedVec    = o.mSpeedVec;
    mIsDead      = o.mIsDead;
    mHasJumped   = o.mHasJumped;
    mIsOnGround  = o.mIsOnGround;
    mIsTakingOff = o.mIsTakingOff;
    mSmokeFrame  = o.mSmokeFrame;
    mFireFrame   = o.mFireFrame;
    mShootCooldown  = o.mShootCooldown;
    mPitchCooldown  = o.mPitchCooldown;
    mDeadCooldown   = o.mDeadCooldown;
    mProtection     = o.mProtection;
    mSmokeAnim      = o.mSmokeAnim;
    mSmokeCooldown  = o.mSmokeCooldown;
    mFireAnim       = o.mFireAnim;
    pilot        = o.pilot;
    pilot.setPlane(this);  // fix the pointer
    return *this;
}

Plane& Plane::operator=(Plane&& o) noexcept
{
    if (this == &o) return *this;
    mType        = o.mType;
    mHp          = o.mHp;
    mScore       = o.mScore;
    mX           = o.mX;
    mY           = o.mY;
    mDir         = o.mDir;
    mSpeed       = o.mSpeed;
    mMaxSpeedVar = o.mMaxSpeedVar;
    mSpeedVec    = o.mSpeedVec;
    mIsDead      = o.mIsDead;
    mHasJumped   = o.mHasJumped;
    mIsOnGround  = o.mIsOnGround;
    mIsTakingOff = o.mIsTakingOff;
    mSmokeFrame  = o.mSmokeFrame;
    mFireFrame   = o.mFireFrame;
    mShootCooldown  = std::move(o.mShootCooldown);
    mPitchCooldown  = std::move(o.mPitchCooldown);
    mDeadCooldown   = std::move(o.mDeadCooldown);
    mProtection     = std::move(o.mProtection);
    mSmokeAnim      = std::move(o.mSmokeAnim);
    mSmokeCooldown  = std::move(o.mSmokeCooldown);
    mFireAnim       = std::move(o.mFireAnim);
    pilot        = std::move(o.pilot);
    pilot.setPlane(this);  // fix the pointer
    return *this;
}


// ---- Public input actions --------------------------------------------------

void Plane::Accelerate(float dt)
{
    namespace p = constants::plane;

    if (mIsDead || mHasJumped) return;

    if (mIsOnGround) {
        if (!mIsTakingOff) TakeOffStart();
        mSpeed += p::takeoffAcceleration * dt;
        return;
    }

    if (mDir != 0.0f) {
        if (mDir == 22.5f || mDir == 337.5f)
            mSpeed += 0.25f * p::acceleration * dt;
        else if (mDir == 45.0f || mDir == 315.0f)
            mSpeed += 0.5f  * p::acceleration * dt;
        else
            mSpeed += 0.75f * p::acceleration * dt;

        mSpeed = std::min(mSpeed, mMaxSpeedVar);
    }
}

void Plane::Decelerate(float dt)
{
    namespace p = constants::plane;

    if (mIsDead || mHasJumped) return;

    if (mIsTakingOff) {
        mSpeed -= p::takeoffDeceleration * dt;
        return;
    }

    mSpeed -= p::deceleration * dt;
    mSpeed  = std::max(mSpeed, 0.0f);
    mMaxSpeedVar = std::max(mSpeed, p::maxSpeedBase);
}

void Plane::Turn(PlanePitch dir, float dt)
{
    (void)dt;
    if (mIsDead || mIsOnGround) return;
    if (!mPitchCooldown.isReady()) return;

    mPitchCooldown.Start();

    const float d = (dir == PlanePitch::Left) ? -1.0f : 1.0f;
    mDir += d * constants::plane::pitchStep;
    mDir  = clamp_angle(mDir, 360.f);
}

bool Plane::Shoot(float dt)
{
    (void)dt;
    if (mHasJumped || mIsDead || mIsOnGround) return false;
    if (!mProtection.isReady())               return false;
    if (!mShootCooldown.isReady())            return false;

    mShootCooldown.Start();
    return true;
}

bool Plane::Jump()
{
    if (mIsDead || mIsOnGround || !mProtection.isReady()) return false;

    mHasJumped = true;
    pilot.Bail(mX, mY, jumpDir());
    return true;
}

// ---- Per-tick update -------------------------------------------------------

void Plane::Update(float dt, const Plane& /*opponent*/)
{
    SpeedUpdate(dt);
    CoordinatesUpdate(dt);
    CollisionsUpdate();
    AbandonedUpdate(dt);

    if (mHasJumped)
        pilot.Update(dt);

    mPitchCooldown.Update(dt);
    mShootCooldown.Update(dt);
    mDeadCooldown.Update(dt);
    mProtection.Update(dt);

    AnimationsUpdate(dt);
}

// ---- Private physics -------------------------------------------------------

void Plane::SpeedUpdate(float dt)
{
    namespace p = constants::plane;

    if (mIsOnGround) { TakeOffUpdate(dt); return; }

    // Climb penalty
    if (mDir <= 70 || mDir >= 290) {
        if (mDir == 0)
            mSpeed -= 0.225f * p::acceleration * dt;
        else if (mDir <= 25 || mDir >= 330)
            mSpeed -= 0.100f * p::acceleration * dt;
        else if (mDir <= 50 || mDir >= 310)
            mSpeed -= 0.065f * p::acceleration * dt;
        else
            mSpeed -= 0.020f * p::acceleration * dt;

        mMaxSpeedVar = std::max(mMaxSpeedVar, p::maxSpeedBase);
        mSpeed       = std::max(mSpeed, 0.0f);
        mMaxSpeedVar = std::max(mSpeed, p::maxSpeedBase);
        return;
    }

    // Dive boost
    if (mDir > 113 && mDir < 246) {
        if (mSpeed < p::maxSpeedBoosted) {
            mSpeed += p::diveAcceleration * dt;
            if (mSpeed > mMaxSpeedVar) {
                mMaxSpeedVar = std::min(mSpeed, p::maxSpeedBoosted);
                mSpeed = mMaxSpeedVar;
            }
            return;
        }
        mSpeed       = p::maxSpeedBoosted;
        mMaxSpeedVar = mSpeed;
    }
}

void Plane::CoordinatesUpdate(float dt)
{
    if (mIsDead)                              return;
    if (mIsOnGround && !mIsTakingOff) return;

    const Vec2 prev{mX, mY};

    mX += mSpeed * std::sin(mDir * M_PI / 180.0f) * dt;

    if (!mIsOnGround) {
        mY -= mSpeed * std::cos(mDir * M_PI / 180.0f) * dt;

        // Gravity
        if (mSpeed < mMaxSpeedVar)
            mY += (mMaxSpeedVar - mSpeed) * dt;
    }

    mSpeedVec = {mX - prev.x, mY - prev.y};
    CoordinatesWrap();
}

void Plane::CoordinatesWrap()
{
    mX = std::fmod(std::fmod(mX, 1.0f) + 1.0f, 1.0f);
    mY = std::max(mY, 0.0f);
}

void Plane::CollisionsUpdate()
{
    namespace barn = constants::barn;
    namespace p    = constants::plane;

    if (mIsDead || (mIsOnGround && !mIsTakingOff)) return;

    const bool collidesWithBarn
    {
        mY > barn::planeCollisionY &&
        mX > barn::planeCollisionX &&
        mX < barn::planeCollisionX + barn::sizeX
    };

    const bool collidesWithGround
    {
        !mIsOnGround && mY > p::groundCollision
    };

    if (collidesWithBarn || collidesWithGround)
        Crash();
}

void Plane::TakeOffUpdate(float dt)
{
    namespace p = constants::plane;
    if (!mIsTakingOff) return;

    mSpeed += 0.75f * p::acceleration * dt;
    if (mSpeed >= p::maxSpeedBase)
        TakeOffFinish();
}

void Plane::AbandonedUpdate(float dt)
{
    namespace p = constants::plane;
    if (mIsDead || !mHasJumped || mDir == 180.0f) return;

    if (mSpeed > p::maxSpeedAbandoned)
        mSpeed -= p::abandonedDeceleration * dt;

    if (!mPitchCooldown.isReady()) return;

    mPitchCooldown.Start();
    mDir += p::pitchStep * (mDir < 180.f ? 1.f : -1.f);
}

void Plane::AnimationsUpdate(float dt)
{
    if (mHasJumped)
        pilot.AnimationsUpdate(dt);

    if (mIsDead) return;

    SmokeUpdate(dt);
    FireUpdate(dt);
}

void Plane::AnimationsReset()
{
    namespace p     = constants::plane;
    namespace smoke = constants::smoke;
    namespace fire  = constants::fire;

    mSmokeFrame = 0;
    mSmokeAnim.Stop();
    mSmokeCooldown.Stop();
    mFireAnim.Stop();
    mFireFrame = 0;

    mShootCooldown.SetNewTimeout(static_cast<float>(p::shootCooldown));
    mPitchCooldown.SetNewTimeout(static_cast<float>(p::pitchCooldown));
    mDeadCooldown.SetNewTimeout(static_cast<float>(p::deadCooldown));
    mProtection.SetNewTimeout(static_cast<float>(p::spawnProtectionCooldown));
    mSmokeAnim.SetNewTimeout(static_cast<float>(smoke::frameTime));
    mSmokeCooldown.SetNewTimeout(static_cast<float>(smoke::cooldown));
    mFireAnim.SetNewTimeout(static_cast<float>(fire::frameTime));

    pilot.AnimationsReset();
}

void Plane::SmokeUpdate(float dt)
{
    namespace smoke = constants::smoke;
    if (mHp > 1) return;

    mSmokeAnim.Update(dt);
    mSmokeCooldown.Update(dt);

    if (mSmokeCooldown.isReady()) {
        mSmokeCooldown.Start();
        mSmokeAnim.Stop();
        mSmokeFrame = 0;
    }

    if (!mSmokeAnim.isReady()) return;

    if (mSmokeFrame < smoke::frameCount) {
        mSmokeAnim.Start();
        ++mSmokeFrame;
    }
}

void Plane::FireUpdate(float dt)
{
    if (mHp > 0) return;
    mFireAnim.Update(dt);
    if (mFireAnim.isReady()) {
        mFireAnim.Start();
        ++mFireFrame;
        if (mFireFrame > 2) mFireFrame = 0;
    }
}

void Plane::TakeOffStart()
{
    if (mIsTakingOff) return;
    mIsTakingOff = true;
    mDir = (mType == PlaneType::Blue)
        ? constants::plane::takeoffDirectionBlue
        : constants::plane::takeoffDirectionRed;
}

void Plane::TakeOffFinish()
{
    mIsTakingOff = false;
    mIsOnGround  = false;
}

void Plane::Explode()
{
    mSpeed = 0.0f;
    mDir   = 0.0f;
    mHp    = 0;

    mIsDead      = true;
    mIsOnGround  = false;
    mIsTakingOff = false;

    mProtection.Stop();
    mPitchCooldown.Stop();
    mShootCooldown.Stop();
    mDeadCooldown.Start();

    mX = 0.0f;
    mY = 0.0f;
    mSpeedVec = {};
}

// ---- Damage ----------------------------------------------------------------

void Plane::Hit(Plane& attacker)
{
    if (mIsDead) return;
    if (!mProtection.isReady()) return;

    if (mHp > 0) {
        --mHp;
        if (mHp == 1) {
            mSmokeAnim.Start();
            mSmokeCooldown.Start();
        } else if (mHp == 0) {
            mFireAnim.Start();
        }
        return;
    }

    Explode();

    if (!mHasJumped) {
        ScoreChange(-1);          // victim loses a point (no, actually attacker gains)
        attacker.ScoreChange(1, this);
    }
}

void Plane::Crash()
{
    if (mIsDead) return;
    Explode();
    if (!mHasJumped)
        ScoreChange(-1);
}

void Plane::ScoreChange(int8_t delta, Plane* /*opponent*/)
{
    if (mScore == 0 && delta < 0) return;
    if (delta < 0)
        mScore -= static_cast<uint8_t>(-delta);
    else
        mScore += static_cast<uint8_t>(delta);
}

void Plane::ResetScore()
{
    mScore = 0;
}

// ---- Respawn ---------------------------------------------------------------

void Plane::Respawn(const Plane& opponent)
{
    namespace p = constants::plane;

    mIsDead      = false;
    mHp          = p::maxHp;
    mIsOnGround  = true;
    mIsTakingOff = false;
    mSpeed       = 0.0f;
    mMaxSpeedVar = p::maxSpeedBase;
    mSpeedVec    = {};
    mHasJumped   = false;

    mDeadCooldown.Stop();
    mPitchCooldown.Stop();
    mShootCooldown.Stop();
    mProtection.Stop();

    mY = p::spawnY;
    mX = (mType == PlaneType::Blue) ? p::spawnBlueX : p::spawnRedX;
    mDir = (mType == PlaneType::Blue) ? p::spawnRotationBlue : p::spawnRotationRed;

    pilot.Respawn();
    AnimationsReset();

    // Spawn protection
    if (!opponent.mIsOnGround && !opponent.mIsDead)
        mProtection.Start();
    else
        mProtection.Stop();
}

// ---- Queries ---------------------------------------------------------------

bool Plane::isDead() const
{
    return pilot.isDead() || (!mHasJumped && mIsDead);
}

float Plane::protectionRemainder() const
{
    if (mIsDead || mHasJumped) return 0.0f;
    return mProtection.remainderTime();
}

bool Plane::canShoot() const
{
    return !isDead()
        && !mHasJumped
        && !mIsOnGround
        && mProtection.isReady()
        && mShootCooldown.isReady();
}

bool Plane::canJump() const
{
    return !isDead()
        && !mIsOnGround
        && mProtection.isReady()
        && !pilot.mIsRunning
        && !pilot.mIsChuteOpen
        && (!mHasJumped || pilot.mChuteState == ChuteState::Idle);
}

Vec2 Plane::bulletSpawnOffset() const
{
    const float dir = mDir * static_cast<float>(M_PI) / 180.0f;
    const float off = constants::plane::bulletSpawnOffset;
    return { off * std::sin(dir), -off * std::cos(dir) };
}

float Plane::jumpDir() const
{
    namespace p = constants::plane;
    return (mType == PlaneType::Red)
        ? clamp_angle(mDir + p::jumpDirOffsetRed,  360.f)
        : clamp_angle(mDir + p::jumpDirOffsetBlue, 360.f);
}

GameRect Plane::Hitbox() const
{
    namespace p = constants::plane;
    return {
        mX - 0.5f * p::hitboxSizeX,
        mY - 0.5f * p::hitboxSizeY,
        p::hitboxSizeX,
        p::hitboxSizeY,
    };
}

bool Plane::isHit(float bx, float by) const
{
    if (mIsDead || !mProtection.isReady()) return false;
    return pointInRect(bx, by, Hitbox());
}


// ===========================================================================
// Plane::Pilot
// ===========================================================================

void Plane::Pilot::Update(float dt)
{
    FallUpdate(dt);
    RunUpdate(dt);
    DeathUpdate(dt);
}

void Plane::Pilot::Move(PlanePitch dir, float dt)
{
    namespace p     = constants::pilot;
    namespace chute = p::chute;
    (void)dt;

    const float moveDir = (dir == PlanePitch::Left) ? -1.0f : 1.0f;

    if (mIsChuteOpen) {
        mChuteState = static_cast<ChuteState>(static_cast<uint8_t>(dir));
        mMoveSpeed  = moveDir * chute::baseSpeedX;
        return;
    }

    if (!mIsRunning) return;

    mDir       = (dir == PlanePitch::Left) ? 90 : 270;
    mMoveSpeed = moveDir * p::runSpeed;

    if (!mRunAnim.isReady()) return;

    mRunAnim.Start();
    ++mRunFrame;
    if (mRunFrame > 2) mRunFrame = 0;
}

void Plane::Pilot::MoveIdle()
{
    mMoveSpeed = 0.0f;
    if (mIsRunning) {
        mRunAnim.Stop();
        mRunFrame = 0;
        return;
    }
    if (mChuteState < ChuteState::Destroyed)
        mChuteState = ChuteState::Idle;
}

void Plane::Pilot::OpenChute()
{
    if (mIsDead || mIsChuteOpen || mIsRunning) return;
    if (mChuteState != ChuteState::Idle)       return;

    mIsChuteOpen = true;
    mGravity     = constants::pilot::gravity;

    if (mSpeed.y < 0.0f)
        mSpeed.y = constants::pilot::chute::baseSpeedY;
}

void Plane::Pilot::ChuteUnlock()
{
    if (plane->mHasJumped && !mIsDead && mChuteState == ChuteState::None)
        mChuteState = ChuteState::Idle;
}

void Plane::Pilot::FallUpdate(float dt)
{
    namespace p     = constants::pilot;
    namespace chute = p::chute;

    if (mIsDead || mIsRunning) return;

    const Vec2 prev{mX, mY};

    mX += (mSpeed.x + mMoveSpeed) * dt;

    if (mIsChuteOpen) {
        if (mSpeed.y > chute::baseSpeedY) {
            mSpeed.y -= chute::speedYSlowdownFactor * dt;
            mSpeed.y  = std::max(mSpeed.y, chute::baseSpeedY);
        } else if (mSpeed.y < chute::baseSpeedY) {
            mSpeed.y += chute::speedYSlowdownFactor * dt;
        }
    } else {
        if (mSpeed.y <= 0.f) {
            mGravity  += 2.f * mGravity * dt;
            mSpeed.y  += mGravity * dt;
            if (mSpeed.y >= 0.f) mGravity = 0.24f;
        } else {
            mGravity += mGravity * dt;
            mSpeed.y += mGravity * dt;
        }
    }

    mY += mSpeed.y * dt;

    if (std::abs(mSpeed.x) > p::maxSpeedXThreshold) {
        const float slowdown = mIsChuteOpen
            ? chute::speedXSlowdownFactor
            : p::speedXSlowdownFactor;
        mSpeed.x += -slowdown * mSpeed.x * dt;
    } else {
        mSpeed.x = 0.0f;
    }

    mSpeedVec = {mX - prev.x, mY - prev.y};

    // Wrap X
    mX = std::fmod(std::fmod(mX, 1.0f) + 1.0f, 1.0f);

    HitGroundCheck();
}

void Plane::Pilot::RunUpdate(float dt)
{
    namespace barn = constants::barn;
    if (!mIsRunning || mIsDead) return;

    const Vec2 prev{mX, mY};
    mX += mMoveSpeed * dt;
    mSpeedVec = {mX - prev.x, mY - prev.y};

    // Wrap X
    mX = std::fmod(std::fmod(mX, 1.0f) + 1.0f, 1.0f);

    // Check rescue zone
    if (mX > barn::pilotCollisionLeftX && mX < barn::pilotCollisionRightX)
        mNeedsRescue = true;
}

void Plane::Pilot::DeathUpdate(float dt)
{
    namespace angel = constants::pilot::angel;
    if (!mIsDead) return;

    mY -= angel::ascentRate * dt;

    if (!mAngelAnim.isReady()) return;

    mAngelAnim.Start();

    if (mAngelFrame == angel::framePastLoopId) {
        mNeedsRespawn = true;
        return;
    }

    ++mAngelFrame;
    if (mAngelFrame != angel::framePastLoopId) return;

    if (mAngelLoop < angel::loopCount) {
        ++mAngelLoop;
        mAngelFrame = 0;
    }
}

void Plane::Pilot::AnimationsUpdate(float dt)
{
    if (mIsDead)       { mAngelAnim.Update(dt); return; }
    if (mIsRunning)    { mRunAnim.Update(dt);   return; }
    if (mIsChuteOpen)  ChuteAnimUpdate(dt);
    else               FallAnimUpdate(dt);
}

void Plane::Pilot::AnimationsReset()
{
    namespace p     = constants::pilot;
    namespace chute = p::chute;
    namespace angel = p::angel;

    mFallAnim.Stop();   mFallFrame  = 0;
    mChuteAnim.Stop();  mChuteState = ChuteState::None;
    mRunAnim.Stop();    mRunFrame   = 0;
    mAngelAnim.Stop();  mAngelFrame = 0; mAngelLoop = 0;

    mFallAnim.SetNewTimeout(static_cast<float>(p::fallFrameTime));
    mChuteAnim.SetNewTimeout(static_cast<float>(chute::frameTime));
    mRunAnim.SetNewTimeout(static_cast<float>(p::runFrameTime));
    mAngelAnim.SetNewTimeout(static_cast<float>(angel::frameTime));
}

void Plane::Pilot::FallAnimUpdate(float dt)
{
    mFallAnim.Update(dt);
    if (mFallAnim.isReady()) {
        mFallAnim.Start();
        mFallFrame = !mFallFrame;
    }
}

void Plane::Pilot::ChuteAnimUpdate(float dt)
{
    if (mChuteState >= ChuteState::Destroyed) return;
    mChuteAnim.Update(dt);
    if (mChuteAnim.isReady()) {
        mChuteAnim.Start();
        mFallFrame = !mFallFrame;
    }
}

GameRect Plane::Pilot::Hitbox() const
{
    namespace p = constants::pilot;
    return {
        mX - 0.5f * p::sizeX,
        mY - 0.5f * p::sizeY,
        p::sizeX,
        p::sizeY,
    };
}

GameRect Plane::Pilot::ChuteHitbox() const
{
    namespace chute = constants::pilot::chute;
    return {
        mX - 0.5f * chute::sizeX,
        mY - chute::offsetY,
        chute::sizeX,
        chute::sizeY,
    };
}

void Plane::Pilot::Bail(float planeX, float planeY, float bailDir)
{
    namespace p = constants::pilot;

    mX = planeX;
    mY = planeY;
    mDir = static_cast<int16_t>(clamp_angle(bailDir, 360.f));

    mGravity   = p::gravity;
    mSpeed.x   =  p::ejectSpeed * std::sin(mDir * static_cast<float>(M_PI) / 180.0f);
    mSpeed.y   = -p::ejectSpeed * std::cos(mDir * static_cast<float>(M_PI) / 180.0f);
    mMoveSpeed = 0.0f;
}

void Plane::Pilot::ChuteHit(Plane& attacker)
{
    (void)attacker;
    mChuteState  = ChuteState::Destroyed;
    mIsChuteOpen = false;
    mFallAnim.Stop();
}

void Plane::Pilot::Kill(Plane& attacker)
{
    // Death
    mIsRunning   = false;
    mIsChuteOpen = false;
    mIsDead      = true;
    mDir         = 0;
    mSpeed       = {};
    mGravity     = 0.0f;
    mSpeedVec    = {};
    mChuteState  = ChuteState::None;

    // Attacker gets 2 points for pilot kill
    attacker.ScoreChange(2);
}

void Plane::Pilot::HitGroundCheck()
{
    namespace p     = constants::pilot;
    namespace chute = p::chute;

    if (mY <= p::groundCollision) return;

    if (mSpeed.y <= p::safeLandingSpeed) {
        FallSurvive();
        return;
    }

    // Fatal landing — pilot dies, plane loses 1 point
    mIsRunning   = false;
    mIsChuteOpen = false;
    mIsDead      = true;
    mDir         = 0;
    mSpeed       = {};
    mGravity     = 0.0f;
    mSpeedVec    = {};
    mChuteState  = ChuteState::None;
    plane->ScoreChange(-1);
}

void Plane::Pilot::FallSurvive()
{
    namespace p = constants::pilot;

    mY           = p::groundCollision;
    mIsRunning   = true;
    mIsChuteOpen = false;
    mSpeed       = {};
    mGravity     = 0.0f;
    mSpeedVec    = {};
    mChuteState  = ChuteState::Idle;
}

void Plane::Pilot::Rescue()
{
    // Signal world to respawn the plane
    mNeedsRescue = true;
}

void Plane::Pilot::Respawn()
{
    mIsRunning   = false;
    mIsChuteOpen = false;
    mIsDead      = false;
    mDir         = 0;
    mGravity     = 0.0f;
    mSpeed       = {};
    mSpeedVec    = {};
    mNeedsRespawn = false;
    mNeedsRescue  = false;

    AnimationsReset();
}

bool Plane::Pilot::isHit(float bx, float by) const
{
    if (mIsDead || !plane->mHasJumped) return false;
    return pointInRect(bx, by, Hitbox());
}

bool Plane::Pilot::ChuteIsHit(float bx, float by) const
{
    if (!mIsChuteOpen) return false;
    return pointInRect(bx, by, ChuteHitbox());
}

float Plane::Pilot::x() const
{
    return plane->mHasJumped ? mX : plane->x();
}

float Plane::Pilot::y() const
{
    return plane->mHasJumped ? mY : plane->y();
}
