#pragma once
#include <core/include/types.hpp>
#include <core/include/world.hpp>
#include <core/include/bullet.hpp>

enum class BotDifficulty { Easy, Medium, Hard };

class BotAI
{
public:
    explicit BotAI(BotDifficulty difficulty = BotDifficulty::Medium);

    // Call once per server tick; returns input for the bot's plane
    PlayerInput think(const Plane& self, const Plane& opponent,
                      const std::vector<Bullet>& bullets, float dt);

private:
    BotDifficulty mDifficulty;

    // Reaction-time simulation: bot only refreshes its decision
    // every mReactionDelay seconds instead of every tick
    float mReactionDelay {};
    float mReactionTimer {};
    PlayerInput mCachedInput {};

    PlayerInput computePlaneInput (const Plane& self, const Plane& opponent,
                                   const std::vector<Bullet>& bullets);
    PlayerInput computePilotInput (const Plane& self, const Plane& opponent);
};
