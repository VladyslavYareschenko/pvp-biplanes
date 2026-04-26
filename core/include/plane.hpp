#pragma once
#include <core/include/types.hpp>
#include <core/include/timer.hpp>

class Plane
{
    PlaneType mType {};
    uint8_t   mScore{};

    float mX{}, mY{}, mDir{};
    float mSpeed{}, mMaxSpeedVar{};
    Vec2  mSpeedVec{};
    float mAngularVelocity{};  // deg/s — used by analog joystick control

    Timer mPitchCooldown  {0.0f};
    Timer mShootCooldown  {0.0f};

    uint8_t mHp    {};
    bool    mIsDead{};
    Timer   mDeadCooldown{0.0f};
    Timer   mProtection  {0.0f};

    bool mIsOnGround{};
    bool mIsTakingOff{};
    bool mHasJumped {};

    // Animation state (sent to client for rendering)
    uint8_t mSmokeFrame{};
    Timer   mSmokeAnim    {0.0f};
    Timer   mSmokeCooldown{0.0f};
    int8_t  mFireFrame{};
    Timer   mFireAnim{0.0f};


public:
    explicit Plane(PlaneType type);

    // Ensure pilot.plane pointer stays valid across copies/moves
    Plane(const Plane& o);
    Plane(Plane&& o) noexcept;
    Plane& operator=(const Plane& o);
    Plane& operator=(Plane&& o) noexcept;
    ~Plane() = default;

    // Input-driven actions — called by GameWorld per tick
    void Accelerate(float dt);
    void Decelerate(float dt);
    void Turn(PlanePitch dir, float dt);

    // Analog joystick flight control (replaces Accelerate/Decelerate/Turn when joystick is active).
    //   targetDir  – desired heading in game degrees (0=up, CW-positive)
    //   magnitude  – joystick deflection [0, 1]
    //   dt         – tick delta time (seconds)
    void ApplyAnalogJoystick(float targetDir, float magnitude, float dt);

    // Returns true if a bullet should be spawned by the caller
    bool Shoot(float dt);

    // Returns true if pilot bailed (caller should call pilot.ChuteUnlock())
    bool Jump();

    // Per-tick physics update; opponent needed for spawn-protection check
    void Update(float dt, const Plane& opponent);

    // Called by world when respawn conditions are met
    void Respawn(const Plane& opponent);

    // Damage
    void Hit(Plane& attacker);   // attacker gets score on kill
    void Crash();                // self-inflicted; attacker loses score

    // Misc
    void ResetScore();

    // ---- Queries ----
    PlaneType type()  const { return mType;  }
    uint8_t   score() const { return mScore; }
    uint8_t   hp()    const { return mHp;    }

    float x()   const { return mX;   }
    float y()   const { return mY;   }
    float dir()  const { return mDir;  }
    float speed() const { return mSpeed; }
    Vec2  speedVec() const { return mSpeedVec; }

    bool isPlaneBodyDead()  const { return mIsDead; }  // plane body dead (not pilot)
    bool hasJumped()        const { return mHasJumped; }
    bool isOnGround()       const { return mIsOnGround; }
    bool isTakingOff()      const { return mIsTakingOff; }

    // Combined "fully dead" (no pilot alive either)
    bool isDead() const;

    bool deadCooldownReady() const { return mDeadCooldown.isReady(); }
    float protectionRemainder() const;
    float deadCooldownRemainder() const { return mDeadCooldown.remainderTime(); }

    bool canShoot() const;
    bool canJump()  const;

    Vec2 bulletSpawnOffset() const;
    float jumpDir() const;

    // Hitbox helpers
    GameRect  Hitbox() const;
    bool  isHit(float bx, float by) const;

    // Smoke/fire frame accessors for rendering
    uint8_t smokeFrame() const { return mSmokeFrame; }
    int8_t  fireFrame()  const { return mFireFrame;  }


    // ---- Pilot inner class ----
    class Pilot
    {
        friend class Plane;

        Plane* plane{};

        bool  mIsRunning  {};
        bool  mIsChuteOpen{};
        bool  mIsDead     {};

        float mX{}, mY{};
        int16_t mDir{};

        Vec2  mSpeed{};
        float mMoveSpeed{};
        float mGravity  {};
        Vec2  mSpeedVec {};

        int8_t mFallFrame{};
        Timer  mFallAnim {0.0f};

        ChuteState mChuteState{ChuteState::None};
        Timer      mChuteAnim {0.0f};

        uint8_t mRunFrame{};
        Timer   mRunAnim {0.0f};

        int8_t  mAngelFrame{};
        int8_t  mAngelLoop {};
        Timer   mAngelAnim {0.0f};

        // Set by DeathUpdate when angel animation completes
        bool mNeedsRespawn{};
        // Set by RunUpdate when pilot reaches rescue zone
        bool mNeedsRescue {};

    public:
        Pilot() = default;

        void setPlane(Plane* p) { plane = p; }

        void Move(PlanePitch dir, float dt);
        void MoveIdle();
        void OpenChute();
        void ChuteUnlock();

        void Update(float dt);

        void FallUpdate  (float dt);
        void RunUpdate   (float dt);
        void DeathUpdate (float dt);
        void AnimationsUpdate(float dt);
        void AnimationsReset();
        void FallAnimUpdate(float dt);
        void ChuteAnimUpdate(float dt);

        GameRect Hitbox()      const;
        GameRect ChuteHitbox() const;

        void Bail(float planeX, float planeY, float bailDir);
        void ChuteHit(Plane& attacker);
        void Kill(Plane& attacker);
        void HitGroundCheck();
        void FallSurvive();
        void Rescue();
        void Respawn();

        bool isHit(float bx, float by)      const;
        bool ChuteIsHit(float bx, float by) const;

        bool isDead()        const { return mIsDead;      }
        bool isChuteOpen()   const { return mIsChuteOpen; }
        bool isChuteBroken() const { return mChuteState == ChuteState::Destroyed; }
        bool isRunning()     const { return mIsRunning;   }
        ChuteState chuteState() const { return mChuteState; }

        bool needsRespawn() const { return mNeedsRespawn; }
        bool needsRescue()  const { return mNeedsRescue;  }
        void clearRespawn()       { mNeedsRespawn = false; }
        void clearRescue()        { mNeedsRescue  = false; }

        float x() const;
        float y() const;
        Vec2  speedVec() const { return mSpeedVec; }

        int8_t   fallFrame()  const { return mFallFrame;  }
        uint8_t  runFrame()   const { return mRunFrame;   }
        int8_t   angelFrame() const { return mAngelFrame; }
        int16_t  dir()        const { return mDir;        }
    };

    Pilot pilot{};

private:
    void SpeedUpdate(float dt);
    void CoordinatesUpdate(float dt);
    void CoordinatesWrap();
    void CollisionsUpdate();
    void TakeOffUpdate(float dt);
    void AbandonedUpdate(float dt);
    void AnimationsUpdate(float dt);
    void AnimationsReset();
    void SmokeUpdate(float dt);
    void FireUpdate(float dt);

    void TakeOffStart();
    void TakeOffFinish();

    void Explode();

    void ScoreChange(int8_t delta, Plane* opponent = nullptr);
};
