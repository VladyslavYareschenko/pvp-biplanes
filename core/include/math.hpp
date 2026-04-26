#pragma once
#include <cstddef>

float clamp_angle(float angle, float constraint);
float get_angle_relative(float angleSource, float angleTarget);
float get_distance(float x1, float y1, float x2, float y2);
size_t angleToPitchIndex(float degrees);
