add_executable(tuner_bench main.cpp)
target_link_libraries(tuner_bench PRIVATE tuner::core)
target_include_directories(tuner_bench PRIVATE ${PROJECT_SOURCE_DIR}/tests)
target_compile_options(tuner_bench PRIVATE -Wall -Wextra -Werror)
