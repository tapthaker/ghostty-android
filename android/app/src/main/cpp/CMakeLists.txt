cmake_minimum_required(VERSION 3.22.1)

project("ghostty_bridge")

# Find the libghostty-vt headers
set(GHOSTTY_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../libghostty-vt/include")

# Add the JNI bridge library
add_library(ghostty_bridge SHARED
    ghostty_bridge.c
)

# Include directories
target_include_directories(ghostty_bridge PRIVATE
    ${GHOSTTY_INCLUDE_DIR}
)

# Link against libghostty-vt (pre-built .so)
# Link against libghostty_renderer (pre-built .so, built separately with Zig)
target_link_libraries(ghostty_bridge
    ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libghostty-vt.so
    ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libghostty_renderer.so
    android
    log
    GLESv3  # OpenGL ES 3.1
    EGL     # EGL for context management
)
