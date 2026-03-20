cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "ironpress")
project(${PROJECT_NAME} LANGUAGES C)

# Precompiled shared library location
set(NATIVE_LIB "${CMAKE_CURRENT_SOURCE_DIR}/libs/libironpress.so")

# Bundle the .so with the Flutter app
set(ironpress_bundled_libraries
  ${NATIVE_LIB}
  PARENT_SCOPE
)
