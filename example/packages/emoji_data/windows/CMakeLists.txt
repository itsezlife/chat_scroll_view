cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "emoji_data")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "emoji_data_plugin")

list(APPEND PLUGIN_SOURCES
  "emoji_data_plugin.cpp"
  "emoji_data_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/emoji_data/emoji_data_plugin_c_api.h"
  "emoji_data_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(emoji_data_bundled_libraries
  ""
  PARENT_SCOPE
)
