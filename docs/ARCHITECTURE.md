# Ghostty Android - Architecture Documentation

## Overview

Ghostty Android is designed as a hybrid native-Android terminal emulator, splitting responsibilities between a high-performance native core (libghostty-vt in Zig) and a modern Android UI layer (Kotlin + Jetpack Compose).

## Design Principles

1. **Separation of Concerns**: Terminal parsing is native, rendering is Android-native
2. **Performance First**: Use SIMD parsing and GPU acceleration wherever possible
3. **Modern Stack**: Leverage latest Android and Zig tooling
4. **Zero JavaScript**: No WebView dependencies for performance and size
5. **Open Source**: MIT licensed, community-driven development

## Component Architecture

### 1. Native Layer (libghostty-vt)

**Responsibility**: Terminal sequence parsing and state management

```
┌─────────────────────────────────────────┐
│        libghostty-vt (Zig/C)            │
├─────────────────────────────────────────┤
│  VT Parser                              │
│  - ANSI/VT100/VT220/VT520 sequences     │
│  - SIMD-optimized parsing               │
│  - OSC, CSI, DCS support                │
│                                          │
│  Terminal State                         │
│  - Character grid (2D buffer)           │
│  - Cursor position & attributes         │
│  - Scrollback buffer                    │
│  - Tab stops, margins                   │
│                                          │
│  Advanced Features                      │
│  - Kitty Graphics Protocol              │
│  - Tmux control mode                    │
│  - Sixel graphics                       │
└─────────────────────────────────────────┘
         ↕ C ABI (JNI/FFI)
```

**Key Characteristics**:
- Written in Zig (compiles to native ARM64/ARMv7)
- Zero dependencies (doesn't even link libc)
- Exposes C-compatible API for Android JNI
- Stateless parser with explicit state management
- Memory-efficient ring buffers for scrollback

**API Surface** (preliminary - based on libghostty-vt):
```c
// Initialize terminal
ghostty_vt_t* ghostty_vt_init(int rows, int cols);

// Parse input data
int ghostty_vt_parse(ghostty_vt_t* vt, const char* data, size_t len);

// Query terminal state
const ghostty_cell_t* ghostty_vt_get_cell(ghostty_vt_t* vt, int row, int col);
void ghostty_vt_get_cursor(ghostty_vt_t* vt, int* row, int* col);

// Resize terminal
void ghostty_vt_resize(ghostty_vt_t* vt, int rows, int cols);

// Cleanup
void ghostty_vt_destroy(ghostty_vt_t* vt);
```

### 2. JNI Bridge Layer

**Responsibility**: Connect Kotlin code to native libghostty-vt

```kotlin
// Kotlin wrapper around native library
class GhosttyVT(rows: Int, cols: Int) {
    private var nativeHandle: Long = 0

    init {
        System.loadLibrary("ghostty_vt")
        nativeHandle = nativeInit(rows, cols)
    }

    // Parse terminal data
    fun parse(data: ByteArray): Int {
        return nativeParse(nativeHandle, data)
    }

    // Get terminal state for rendering
    fun getTerminalGrid(): TerminalGrid {
        return nativeGetGrid(nativeHandle)
    }

    // JNI declarations
    private external fun nativeInit(rows: Int, cols: Int): Long
    private external fun nativeParse(handle: Long, data: ByteArray): Int
    private external fun nativeGetGrid(handle: Long): TerminalGrid
    private external fun nativeDestroy(handle: Long)
}
```

**Optimizations**:
- Use direct ByteBuffers to avoid copying between Java and native
- Batch state queries (get entire dirty region instead of cell-by-cell)
- Cache frequently accessed state on Kotlin side
- Use reentrant locks for thread-safe access

### 3. Rendering Layer (Jetpack Compose)

**Responsibility**: GPU-accelerated terminal display

```
┌─────────────────────────────────────────┐
│     Compose TerminalView                │
├─────────────────────────────────────────┤
│  Canvas (Hardware Layer)                │
│  ┌──────────────────────────────────┐  │
│  │  Text Rendering (Android Paint)  │  │
│  │  - TextPaint for glyphs          │  │
│  │  - StaticLayout for text         │  │
│  │  - Shader for effects            │  │
│  └──────────────────────────────────┘  │
│                                          │
│  Dirty Region Tracking                  │
│  - Only redraw changed cells            │
│  - Coalesce updates (batch redraws)     │
│  - Double buffering                     │
└─────────────────────────────────────────┘
```

**Compose Implementation**:

```kotlin
@Composable
fun TerminalView(
    terminalState: TerminalState,
    modifier: Modifier = Modifier
) {
    // Hardware-accelerated layer
    Canvas(
        modifier = modifier
            .graphicsLayer {
                // Enable hardware acceleration
                compositingStrategy = CompositingStrategy.Offscreen
            }
    ) {
        val cellWidth = size.width / terminalState.cols
        val cellHeight = size.height / terminalState.rows

        // Draw only dirty cells
        terminalState.dirtyRegions.forEach { region ->
            drawTerminalRegion(
                region = region,
                cellWidth = cellWidth,
                cellHeight = cellHeight
            )
        }
    }
}
```

**GPU Acceleration Details**:
- Compose Canvas uses Android's RenderThread for GPU rendering
- Hardware layer enables GPU-accelerated composition
- Text rendering uses Android's optimized TextPaint (GPU-backed on modern devices)
- Background rendering happens off UI thread

### 4. Input Handling

**Responsibility**: Convert Android input to terminal escape sequences

```kotlin
class TerminalInputHandler(private val vt: GhosttyVT) {

    // Handle keyboard input
    fun onKeyEvent(event: KeyEvent): Boolean {
        val sequence = when (event.keyCode) {
            KeyEvent.KEYCODE_ENTER -> "\r"
            KeyEvent.KEYCODE_TAB -> "\t"
            KeyEvent.KEYCODE_DEL -> "\x7f"
            KeyEvent.KEYCODE_DPAD_UP -> "\u001b[A"
            KeyEvent.KEYCODE_DPAD_DOWN -> "\u001b[B"
            // ... etc
            else -> event.unicodeChar.toChar().toString()
        }

        sendToTerminal(sequence.toByteArray())
        return true
    }

    // Handle touch input (selection, scrolling)
    fun onTouchEvent(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> startSelection(event.x, event.y)
            MotionEvent.ACTION_MOVE -> updateSelection(event.x, event.y)
            MotionEvent.ACTION_UP -> endSelection()
        }
    }
}
```

## Data Flow

### Terminal Output Flow

```
PTY/Process Output
    ↓
[ByteArray] Terminal data
    ↓
GhosttyVT.parse() (JNI)
    ↓
libghostty-vt parses sequences (native)
    ↓
Updates terminal state (grid, cursor, etc)
    ↓
[JNI callback] Notify Kotlin of changes
    ↓
TerminalState updates (Kotlin)
    ↓
Compose recomposition triggered
    ↓
Canvas redraws dirty regions (GPU)
    ↓
Display updated
```

### Terminal Input Flow

```
User Input (keyboard/touch)
    ↓
TerminalInputHandler processes event
    ↓
Convert to VT escape sequence
    ↓
[ByteArray] Escape sequence
    ↓
Send to PTY/Process
    ↓
Command executes
    ↓
(back to output flow)
```

## Performance Optimizations

### 1. Dirty Region Tracking

Only redraw changed portions of the terminal:

```kotlin
data class DirtyRegion(
    val startRow: Int,
    val endRow: Int,
    val startCol: Int,
    val endCol: Int
)

// libghostty-vt tracks dirty cells internally
// Expose via JNI to avoid full grid query
fun getDirtyRegions(): List<DirtyRegion>
```

### 2. Direct ByteBuffer Usage

Avoid copying data between Java and native:

```kotlin
// Use direct ByteBuffer for zero-copy parsing
val inputBuffer = ByteBuffer.allocateDirect(8192)
val bytesRead = inputStream.read(inputBuffer)
vt.parseDirect(inputBuffer, bytesRead)
```

### 3. Batched Rendering

Coalesce multiple updates into single redraw:

```kotlin
// Debounce rapid updates
val renderDebouncer = Debouncer(16L) { // ~60fps
    terminalState.invalidate()
}

// On terminal update
renderDebouncer.debounce()
```

### 4. GPU Text Rendering

Use Android's GPU-accelerated text rendering:

```kotlin
val textPaint = TextPaint().apply {
    isAntiAlias = true
    // Use hardware acceleration when available
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        hinting = Paint.HINTING_ON
    }
}
```

## Memory Management

### Native Memory

- libghostty-vt allocates terminal grid and scrollback
- JNI layer holds reference to native pointer
- Explicit cleanup via `destroy()` method
- Use Kotlin `AutoCloseable` for safety

```kotlin
class GhosttyVT : AutoCloseable {
    override fun close() {
        if (nativeHandle != 0L) {
            nativeDestroy(nativeHandle)
            nativeHandle = 0
        }
    }
}
```

### Android Memory

- Compose state uses Kotlin's efficient data structures
- Grid updates use copy-on-write for efficient recomposition
- Bitmap caching for frequently rendered glyphs
- Aggressive recycling of temporary allocations

## Threading Model

```
┌──────────────────────────────────────────┐
│          Main/UI Thread                  │
│  - Compose recomposition                 │
│  - User input handling                   │
│  - Lightweight state updates             │
└──────────────────────────────────────────┘
             ↕ (post to)
┌──────────────────────────────────────────┐
│        Background Thread                 │
│  - PTY I/O (read/write)                  │
│  - Terminal parsing (JNI calls)          │
│  - Heavy state updates                   │
└──────────────────────────────────────────┘
             ↕ (posts to)
┌──────────────────────────────────────────┐
│        RenderThread (Android)            │
│  - GPU rendering                         │
│  - Canvas drawing                        │
│  - Composition                           │
└──────────────────────────────────────────┘
```

## Future Architecture Considerations

### 1. Multiple Renderers

Support different rendering backends:

- **Compose Canvas** (current): Good balance, easy to implement
- **OpenGL ES**: Maximum performance, more complex
- **Vulkan**: Best performance, Android 7+ only, very complex

### 2. Shared Terminal State

If integrating with ClaudeLink:

```kotlin
// Shared ViewModel between local and remote terminals
class TerminalViewModel {
    val terminalState: StateFlow<TerminalState>

    // Can be backed by local PTY or remote WebSocket
    val backend: TerminalBackend
}
```

### 3. Plugin System

Extensibility for custom features:

- Color scheme plugins
- Font renderers
- Input method plugins
- Protocol handlers (SSH, Telnet, etc.)

## Testing Strategy

### Unit Tests
- Terminal parsing (via libghostty-vt tests)
- Input conversion (keyboard → escape sequences)
- State management

### Integration Tests
- JNI bridge functionality
- Full parse → render pipeline
- Memory leak detection

### Performance Tests
- Parsing throughput benchmarks
- Rendering FPS measurements
- Memory usage profiling
- Battery usage testing

### UI Tests
- Compose UI tests
- Accessibility testing
- Different screen sizes/densities

---

**Document Version**: 1.0
**Last Updated**: 2025-11-01
**Status**: Architecture defined, implementation pending
