#include <core/include/bullet.hpp>
#include <core/include/plane.hpp>
#include <core/include/constants.hpp>

#include <cmath>
#include <algorithm>

Bullet::Bullet(float x, float y, float dir, PlaneType firedBy)
    : mX{x}, mY{y}, mDir{dir}, mFiredBy{firedBy}
{}

Bullet::HitResult Bullet::Update(float dt, Plane planes[2])
{
    namespace barn   = constants::barn;
    namespace bullet = constants::bullet;

    HitResult result{};

    if (mIsDead) return result;

    mX += bullet::speed * std::sin(mDir * static_cast<float>(M_PI) / 180.0f) * dt;
    mY -= bullet::speed * std::cos(mDir * static_cast<float>(M_PI) / 180.0f) * dt;

    // Screen borders
    if (mX > 1.0f || mX < 0.0f || mY < 0.0f) {
        mX = std::max(std::min(mX, 1.0f), 0.0f);
        mY = std::max(mY, 0.0f);
        Destroy();
        return result;
    }

    // Ground / barn surface
    const bool hitsGround{mY > bullet::groundCollision};
    const bool hitsBarn{
        mX > barn::bulletCollisionX &&
        mX < barn::bulletCollisionX + barn::bulletCollisionSizeX &&
        mY > barn::bulletCollisionY
    };
    if (hitsGround || hitsBarn) {
        Destroy();
        return result;
    }

    // Determine target plane (opposite of shooter)
    const int targetIdx   = (mFiredBy == PlaneType::Blue) ? 1 : 0;
    const int attackerIdx = 1 - targetIdx;
    Plane& target   = planes[targetIdx];
    (void)planes[attackerIdx];

    if (target.isHit(mX, mY)) {
        Destroy();
        result.hitPlane = true;
        result.hitOwner = target.type();
        return result;
    }

    if (target.pilot.ChuteIsHit(mX, mY)) {
        Destroy();
        result.hitChute = true;
        result.hitOwner = target.type();
        return result;
    }

    if (target.pilot.isHit(mX, mY)) {
        Destroy();
        result.hitPilot = true;
        result.hitOwner = target.type();
        return result;
    }

    return result;
}

void Bullet::Destroy()
{
    mIsDead = true;
}


// ---------------------------------------------------------------------------
// BulletSpawner
// ---------------------------------------------------------------------------

void BulletSpawner::SpawnBullet(float x, float y, float dir, PlaneType firedBy)
{
    mInstances.push_back({x, y, dir, firedBy});
}

void BulletSpawner::Update(float dt, Plane planes[2])
{
    size_t i = 0;
    while (i < mInstances.size()) {
        auto& b   = mInstances[i];
        auto  hit = b.Update(dt, planes);

        if (hit.hitPlane || hit.hitChute || hit.hitPilot) {
            // Determine attacker/target indices
            const int targetIdx   = (b.firedBy() == PlaneType::Blue) ? 1 : 0;
            const int attackerIdx = 1 - targetIdx;

            if (hit.hitPlane)
                planes[targetIdx].Hit(planes[attackerIdx]);
            else if (hit.hitChute)
                planes[targetIdx].pilot.ChuteHit(planes[attackerIdx]);
            else if (hit.hitPilot)
                planes[targetIdx].pilot.Kill(planes[attackerIdx]);
        }

        if (mInstances[i].isDead()) {
            mInstances.erase(mInstances.begin() + i);
            continue;
        }
        ++i;
    }
}

void BulletSpawner::Clear()
{
    mInstances.clear();
}

std::vector<Bullet> BulletSpawner::GetClosestBullets(float x, float y, PlaneType target) const
{
    std::vector<Bullet> result;
    for (const auto& b : mInstances) {
        if (b.firedBy() != target)
            result.push_back(b);
    }
    std::sort(result.begin(), result.end(),
        [x, y](const Bullet& a, const Bullet& b) {
            const float da = (a.x()-x)*(a.x()-x) + (a.y()-y)*(a.y()-y);
            const float db = (b.x()-x)*(b.x()-x) + (b.y()-y)*(b.y()-y);
            return da < db;
        });
    return result;
}
