add_library(biplanes_common INTERFACE)

target_include_directories(biplanes_common INTERFACE ${CMAKE_SOURCE_DIR})

target_link_libraries(biplanes_common INTERFACE
    biplanes_core
    nlohmann_json::nlohmann_json
)
