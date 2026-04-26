#include <core/include/world.hpp>
#include <core/include/constants.hpp>

#include <cmath>

GameWorld::GameWorld()
{
    planes[0] = Plane{PlaneType::Blue};
    planes[1] = Plane{PlaneType::Red};
}

void GameWorld::startRound()
{
    reset();
    roundRunning = true;
}

void GameWorld::reset()
{
    tick          = 0;
    roundRunning  = false;
    roundFinished = false;
    winnerId      = -1;

    planes[0] = Plane{PlaneType::Blue};
    planes[1] = Plane{PlaneType::Red};

    planes[0].Respawn(planes[1]);
    planes[1].Respawn(planes[0]);

    bullets.Clear();
}

void GameWorld::update(const PlayerInput inputs[2])
{
    if (!roundRunning) return;

    ++tick;

    // Apply inputs
    for (int i = 0; i < 2; ++i)
        applyInput(i, inputs[i]);

    // Update physics for each plane (pass opponent for context)
    for (int i = 0; i < 2; ++i)
        planes[i].Update(TICK_DT, planes[1 - i]);

    // Bullet physics + collision
    bullets.Update(TICK_DT, planes);

    // Handle respawns triggered by this tick
    handleRespawns();

    // Check win
    if (!roundFinished)
        checkWinCondition();
}

void GameWorld::applyInput(int idx, const PlayerInput& input)
{
    Plane& plane = planes[idx];

    if (plane.isDead()) return;

    const JoystickState& js = input.joystick;

    if (js.active) {
        // ---- Analog joystick mode -------------------------------------------
        if (plane.hasJumped()) {
            // Pilot on parachute: use X-component of joystick for left/right movement.
            const float sx = std::sin(js.angle * (3.14159265f / 180.0f));
            if (sx < -0.2f)
                plane.pilot.Move(PlanePitch::Left,  TICK_DT);
            else if (sx > 0.2f)
                plane.pilot.Move(PlanePitch::Right, TICK_DT);
            else
                plane.pilot.MoveIdle();
        } else if (plane.isOnGround()) {
            // On ground: accelerate for takeoff when stick is pushed.
            if (js.magnitude > 0.4f)
                plane.Accelerate(TICK_DT);
        } else {
            // Airborne: full analog flight control.
            plane.ApplyAnalogJoystick(js.angle, js.magnitude, TICK_DT);
        }
    } else {
        // ---- Discrete (legacy) button mode ----------------------------------

        // Throttle
        if (input.throttle == PlaneThrottle::Increase)
            plane.Accelerate(TICK_DT);
        else if (input.throttle == PlaneThrottle::Decrease)
            plane.Decelerate(TICK_DT);

        // Pitch — plane or pilot movement
        if (plane.hasJumped()) {
            if (input.pitch == PlanePitch::Left)
                plane.pilot.Move(PlanePitch::Left, TICK_DT);
            else if (input.pitch == PlanePitch::Right)
                plane.pilot.Move(PlanePitch::Right, TICK_DT);
            else
                plane.pilot.MoveIdle();
        } else {
            if (input.pitch == PlanePitch::Left)
                plane.Turn(PlanePitch::Left, TICK_DT);
            else if (input.pitch == PlanePitch::Right)
                plane.Turn(PlanePitch::Right, TICK_DT);
        }
    }

    // Shoot — always available regardless of input mode
    if (input.shoot && plane.canShoot()) {
        if (plane.Shoot(TICK_DT)) {
            const Vec2 off = plane.bulletSpawnOffset();
            bullets.SpawnBullet(
                plane.x() + off.x,
                plane.y() + off.y,
                plane.dir(),
                plane.type());
        }
    }

    // Jump / chute — always available regardless of input mode
    if (input.jump) {
        if (!plane.hasJumped()) {
            if (plane.Jump()) {
                // Unlock chute immediately so player can open it
                plane.pilot.ChuteUnlock();
            }
        } else {
            // Try to open chute; if still locked, try unlock first
            if (plane.pilot.chuteState() == ChuteState::None)
                plane.pilot.ChuteUnlock();
            plane.pilot.OpenChute();
        }
    }
}

void GameWorld::handleRespawns()
{
    for (int i = 0; i < 2; ++i) {
        Plane& plane    = planes[i];
        Plane& opponent = planes[1 - i];

        // Plane body dead without bail — respawn after cooldown
        if (plane.isPlaneBodyDead() && !plane.hasJumped() && plane.deadCooldownReady()) {
            plane.Respawn(opponent);
            continue;
        }

        // Pilot angel animation finished → respawn
        if (plane.hasJumped() && plane.pilot.isDead() && plane.pilot.needsRespawn()) {
            plane.pilot.clearRespawn();
            plane.Respawn(opponent);
            continue;
        }

        // Pilot ran to rescue zone → respawn
        if (plane.hasJumped() && plane.pilot.isRunning() && plane.pilot.needsRescue()) {
            plane.pilot.clearRescue();
            plane.Respawn(opponent);
            continue;
        }
    }
}

void GameWorld::checkWinCondition()
{
    for (int i = 0; i < 2; ++i) {
        if (planes[i].score() >= winScore) {
            roundFinished = true;
            winnerId      = i;
            return;
        }
    }
}
