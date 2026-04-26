add_library(biplanes_core STATIC
    src/timer.cpp
    src/math.cpp
    src/plane.cpp
    src/bullet.cpp
    src/world.cpp
    src/bot.cpp
)

target_include_directories(biplanes_core PUBLIC ${CMAKE_SOURCE_DIR})

target_compile_options(biplanes_core PRIVATE
    -Wall -Wextra -Wno-unused-parameter
)
