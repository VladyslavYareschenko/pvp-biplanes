add_executable(biplanes_server src/main.cpp)

target_link_libraries(biplanes_server PRIVATE
    biplanes_common
)

target_compile_options(biplanes_server PRIVATE
    -Wall -Wextra -Wno-unused-parameter
)
