include(FetchContent)
FetchContent_Declare(
    Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG v3.8.1
    GIT_SHALLOW TRUE
    SYSTEM
    FIND_PACKAGE_ARGS 3
)
FetchContent_MakeAvailable(Catch2)

add_executable(tuner_tests
    detector_test.cpp
    note_test.cpp
    tuner_test.cpp
    capi_test.cpp
)
target_link_libraries(tuner_tests PRIVATE tuner::dsp_c Catch2::Catch2WithMain)
target_include_directories(tuner_tests PRIVATE .)
target_compile_options(tuner_tests PRIVATE -Wall -Wextra -Werror)

include(Catch)
catch_discover_tests(tuner_tests TEST_SPEC "~[timing]")
# Timing must not share the CPU with the parallel tests.
add_test(NAME timing COMMAND tuner_tests "[timing]")
set_tests_properties(timing PROPERTIES RUN_SERIAL TRUE)

add_executable(alloc_test alloc_test.cpp)
target_link_libraries(alloc_test PRIVATE tuner::dsp_c)
target_include_directories(alloc_test PRIVATE .)
target_compile_options(alloc_test PRIVATE -Wall -Wextra -Werror)
add_test(NAME alloc_test COMMAND alloc_test)
