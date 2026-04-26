#include <core/include/math.hpp>
#include <core/include/constants.hpp>

#include <cmath>

float clamp_angle(float angle, float constraint)
{
    return std::fmod(angle + constraint, constraint);
}

float get_angle_relative(float angleSource, float angleTarget)
{
    float rel = angleTarget - angleSource;
    if (rel >  180.f) rel -= 360.f;
    if (rel < -180.f) rel += 360.f;
    return rel;
}

float get_distance(float x1, float y1, float x2, float y2)
{
    return std::sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
}

size_t angleToPitchIndex(float degrees)
{
    return static_cast<size_t>(std::round(degrees / constants::plane::pitchStep));
}
