cmake_minimum_required(VERSION 3.10.2)
project(native_io)

add_library(
    native_io
    SHARED
    native_downloader.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    native_io
    ${log-lib}
)
