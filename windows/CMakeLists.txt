cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "ironpress")
project(${PROJECT_NAME} LANGUAGES C)

# Precompiled DLL location
set(NATIVE_LIB "${CMAKE_CURRENT_SOURCE_DIR}/libs/ironpress.dll")

# Bundle the .dll with the Flutter app
set(ironpress_bundled_libraries
  ${NATIVE_LIB}
  PARENT_SCOPE
)
