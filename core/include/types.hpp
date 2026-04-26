#pragma once
#include <cstdint>
#include <cmath>

struct Vec2 {
    float x{};
    float y{};

    Vec2 operator+(const Vec2& o) const { return {x + o.x, y + o.y}; }
    Vec2 operator-(const Vec2& o) const { return {x - o.x, y - o.y}; }
    Vec2 operator*(float s)       const { return {x * s,   y * s};   }
    float length()                const { return std::sqrt(x*x + y*y); }
    bool operator==(const Vec2& o) const { return x == o.x && y == o.y; }
};

struct GameRect {
    float x{};
    float y{};
    float w{};
    float h{};
};

inline bool pointInRect(float px, float py, const GameRect& r) {
    return px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h;
}

enum class PlaneType     : uint8_t { Blue = 0, Red = 1 };
enum class PlanePitch    : uint8_t { Idle, Left, Right };
enum class PlaneThrottle : uint8_t { Idle, Increase, Decrease };
enum class ChuteState    : uint8_t { Idle, Left, Right, Destroyed, None };
