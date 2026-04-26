add_executable(biplanes_client src/main.cpp)

target_include_directories(biplanes_client PRIVATE ${SDL2_INCLUDE_DIRS})

target_link_libraries(biplanes_client PRIVATE
    biplanes_core
    biplanes_common
    ${SDL2_LIBRARIES}
)

target_compile_options(biplanes_client PRIVATE
    -Wall -Wextra -Wno-unused-parameter
)
