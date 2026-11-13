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
)
target_link_libraries(tuner_tests PRIVATE tuner::core Catch2::Catch2WithMain)
target_include_directories(tuner_tests PRIVATE .)
target_compile_options(tuner_tests PRIVATE -Wall -Wextra -Werror)

include(Catch)
catch_discover_tests(tuner_tests)
