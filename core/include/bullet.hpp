#pragma once
#include <core/include/types.hpp>
#include <core/include/timer.hpp>

#include <vector>

class Plane;

class Bullet
{
    float     mX{}, mY{}, mDir{};
    bool      mIsDead{false};
    PlaneType mFiredBy{};

public:
    Bullet(float x, float y, float dir, PlaneType firedBy);

    struct HitResult {
        bool      hitPlane {};
        bool      hitChute {};
        bool      hitPilot {};
        PlaneType hitOwner {};  // owner of the hit entity (who was hit)
    };

    HitResult Update(float dt, Plane planes[2]);
    void Destroy();

    bool      isDead()   const { return mIsDead;  }
    PlaneType firedBy()  const { return mFiredBy; }
    float     x()        const { return mX;       }
    float     y()        const { return mY;       }
    float     dir()      const { return mDir;     }
};


class BulletSpawner
{
    std::vector<Bullet> mInstances{};

public:
    BulletSpawner() = default;

    void SpawnBullet(float x, float y, float dir, PlaneType firedBy);

    // Updates all bullets; applies hit results to planes
    void Update(float dt, Plane planes[2]);

    void Clear();

    const std::vector<Bullet>& instances() const { return mInstances; }

    std::vector<Bullet> GetClosestBullets(float x, float y, PlaneType target) const;
};
