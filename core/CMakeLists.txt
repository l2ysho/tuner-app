cmake_minimum_required(VERSION 3.25)
project(tuner_core VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(TUNER_BUILD_TESTS "Build unit tests" ${PROJECT_IS_TOP_LEVEL})
option(TUNER_BUILD_TOOLS "Build the bench CLI" ${PROJECT_IS_TOP_LEVEL})
option(TUNER_SANITIZE "Build with AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(TUNER_SANITIZE)
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()

add_library(tuner_core
    src/correlator.cpp
    src/detector.cpp
    src/note.cpp
    src/tuner.cpp
)
add_library(tuner::core ALIAS tuner_core)
target_include_directories(tuner_core PUBLIC include)
target_compile_features(tuner_core PUBLIC cxx_std_20)

target_compile_options(tuner_core PRIVATE -Wall -Wextra -Wpedantic -Werror)

# The C ABI that Swift and JNI link against. SPM compiles the same file.
add_library(tuner_dsp_c capi/tuner_dsp_c.cpp)
add_library(tuner::dsp_c ALIAS tuner_dsp_c)
target_include_directories(tuner_dsp_c PUBLIC capi)
target_link_libraries(tuner_dsp_c PUBLIC tuner_core)
target_compile_options(tuner_dsp_c PRIVATE -Wall -Wextra -Wpedantic -Werror)

if(TUNER_BUILD_TESTS)
    include(CTest)
    add_subdirectory(tests)
endif()

if(TUNER_BUILD_TOOLS)
    add_subdirectory(tools/bench)
endif()
