# Ghostty OpenGL Renderer Analysis for Android

## Executive Summary

Ghostty uses a modern OpenGL 4.3+ architecture with GLSL 430 core shaders. The renderer is highly optimized for GPU-accelerated terminal rendering with:
- Per-cell glyph rendering using instanced geometry
- Dual glyph atlas (grayscale + color)
- Sophisticated color blending with linear color space support
- Per-cell dirty tracking with row-based clearing
- Swap chain support for multi-buffered rendering

**Key Finding:** The renderer relies on OpenGL 4.3 features. Android supports OpenGL ES 3.1, which would require significant adaptation.

---

## 1. CORE RENDERER ARCHITECTURE

### 1.1 Graphics API Hierarchy

```
GraphicsAPI (OpenGL wrapper)
  ├── Target (Framebuffer + Renderbuffer)
  ├── Frame (Draw context for a frame)
  ├── RenderPass (Collection of steps to same target)
  ├── Step (Input buffers + pipelines + geometry)
  ├── Pipeline (Compiled vertex + fragment shaders)
  ├── Buffer (GPU vertex/uniform data)
  ├── Texture (GPU texture storage)
  └── Sampler (Texture sampling state)
```

### 1.2 Main OpenGL.zig Structure

**Key Constants:**
```zig
pub const MIN_VERSION_MAJOR = 4;
pub const MIN_VERSION_MINOR = 3;  // Requires OpenGL 4.3
pub const swap_chain_count = 1;   // No multi-buffering for OpenGL
pub const custom_shader_target: shadertoy.Target = .glsl;
pub const custom_shader_y_is_down = false;  // Y axis is up in OpenGL
```

**Core Fields:**
```zig
alloc: std.mem.Allocator
blending: configpkg.Config.AlphaBlending
last_target: ?Target = null  // For repeated presentation
```

### 1.3 State Interaction Flow

The renderer gets terminal content via `renderer.State`:
```zig
pub const State = struct {
    terminal: *Terminal,           // Terminal data
    inspector: ?*Inspector,        // Inspector if active
    preedit: ?Preedit,            // Dead key state
    mouse: Mouse,                  // Mouse position/modifiers
};
```

The generic renderer (`generic.zig`) manages:
- `cellpkg.Contents` - Grid of cell data for rendering
- `shaderpkg.Uniforms` - Global shader uniforms (projection, grid size, etc.)
- Font atlas management and glyph rasterization

### 1.4 Rendering Pipeline

**Frame Lifecycle:**
```
1. drawFrameStart()           - Pre-frame setup
2. beginFrame()               - Create frame context
3. renderPass()               - Create render pass with attachments
4. [Issue draw steps]         - Submit geometry to pipelines
5. complete()                 - Finish frame, present target
6. frameCompleted(health)     - Callback with health status
7. drawFrameEnd()             - Post-frame cleanup
```

**Draw Order (from shaders.zig):**
```zig
pipeline_descs: []const struct { [:0]const u8, PipelineDescription } = &.{
    .{ "bg_color", {...} },      // Full-screen background color
    .{ "cell_bg", {...} },       // Per-cell background colors (with blending)
    .{ "cell_text", {...} },     // Text glyphs (per-instance, with blending)
    .{ "image", {...} },         // Foreground images (per-instance)
    .{ "bg_image", {...} },      // Background image (per-instance)
};
```

---

## 2. CELL RENDERING ARCHITECTURE

### 2.1 Cell Data Structure

**Cell Contents** (`cell.zig`):
```zig
pub const Contents = struct {
    size: GridSize,                          // Terminal grid dimensions
    bg_cells: []CellBg,                     // Row × Col 4u8 colors
    fg_rows: ArrayListCollection(CellText), // Per-row foreground glyphs
    // Index 0 is cursor (rendered first)
    // Index 1..rows are regular content
    // Index rows+1 is cursor (rendered last, for underline/bar)
};
```

**Background Cell** (`CellBg`):
```zig
pub const CellBg = [4]u8;  // RGBA color
```

**Foreground Cell** (`CellText`):
```zig
pub const CellText = extern struct {
    glyph_pos: [2]u32,           // Position in atlas texture (pixels)
    glyph_size: [2]u32,          // Size in atlas texture (pixels)
    bearings: [2]i16,            // Glyph bearings (for positioning)
    grid_pos: [2]u16,            // Position in terminal grid
    color: [4]u8,                // RGBA color
    atlas: Atlas,                // Which atlas: grayscale or color
    bools: packed struct(u8) {
        no_min_contrast: bool,
        is_cursor_glyph: bool,
    },
};

pub const Atlas = enum(u8) {
    grayscale = 0,
    color = 1,
};
```

### 2.2 Glyph Rasterization & Font Atlas

**Font Atlas Creation:**
```zig
pub fn initAtlasTexture(
    self: *const OpenGL,
    atlas: *const font.Atlas,
) Texture.Error!Texture {
    // atlas.format: .grayscale (RED texture) or .bgra (SRGBA texture)
    // atlas.size: Square texture dimensions
    
    return try Texture.init(.{
        .format = format,
        .internal_format = internal_format,
        .target = .Rectangle,      // GL_TEXTURE_RECTANGLE (non-normalized coords)
        .min_filter = .nearest,     // Nearest for crisp glyphs
        .mag_filter = .nearest,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    }, atlas.size, atlas.size, null);
}
```

**Key Points:**
- Uses **Rectangle textures** (pixel-coordinate addressing, not normalized 0-1)
- Rasterization happens in `font/` module (not OpenGL)
- Two atlases:
  - **Grayscale** (RED texture, 1 byte per pixel) - standard text
  - **Color** (BGRA texture, 4 bytes per pixel) - emoji/colored glyphs

### 2.3 Cell Rendering (Vertex Shader)

**From `cell_text.v.glsl`:**
```glsl
// Per-vertex attributes (instanced)
layout(location = 0) in uvec2 glyph_pos;      // Atlas position
layout(location = 1) in uvec2 glyph_size;     // Atlas size
layout(location = 2) in ivec2 bearings;       // Glyph metrics
layout(location = 3) in uvec2 grid_pos;       // Terminal grid position
layout(location = 4) in uvec4 color;          // RGBA color
layout(location = 5) in uint atlas;           // Grayscale or color
layout(location = 6) in uint glyph_bools;    // NO_MIN_CONTRAST, IS_CURSOR_GLYPH

// Uses gl_VertexID to generate 4 vertices per instance for triangle strip:
//   0 --- 1
//   |  /  |
//   | /   |
//   2 --- 3
```

**Rendering Process:**
1. Convert grid position (cells) → world position (pixels)
2. Apply glyph bearings to position glyph correctly within cell
3. Generate quad vertices using `gl_VertexID` (0-3)
4. Calculate texture coordinates from atlas position
5. Load and blend colors (texture + background + cursor)
6. Apply minimum contrast if needed

### 2.4 Text Attributes

**Bold:** Handled in font rasterization (separate glyph variants)
**Italic:** Handled in font rasterization (separate glyph variants)
**Underline:** Separate glyph from cell content (added as additional vertex)
**Strikethrough:** Same as underline (additional vertex)
**Overline:** Same as underline (additional vertex)

All are rendered as separate `CellText` entries in the row's list.

### 2.5 Color Processing

**From `common.glsl`:**
```glsl
// Load 4-byte RGBA and linearize/premultiply
vec4 load_color(uvec4 in_color, bool linear) {
    vec4 color = vec4(in_color) / vec4(255.0f);
    if (linear) color = linearize(color);  // sRGB → linear
    color.rgb *= color.a;                   // Premultiply alpha
    return color;
}

// Linearize: sRGB → linear RGB (per WCAG spec)
vec4 linearize(vec4 srgb) {
    // Piecewise function for correct gamma handling
    bvec3 cutoff = lessThanEqual(srgb.rgb, vec3(0.04045));
    vec3 higher = pow((srgb.rgb + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = srgb.rgb / vec3(12.92);
    return vec4(mix(higher, lower, cutoff), srgb.a);
}

// Unlinearize: linear RGB → sRGB (inverse)
vec4 unlinearize(vec4 linear) {
    bvec3 cutoff = lessThanEqual(linear.rgb, vec3(0.0031308));
    vec3 higher = pow(linear.rgb, vec3(1.0 / 2.4)) * vec3(1.055) - vec3(0.055);
    vec3 lower = linear.rgb * vec3(12.92);
    return vec4(mix(higher, lower, cutoff), linear.a);
}
```

**Minimum Contrast:**
```glsl
float contrast_ratio(vec3 color1, vec3 color2) {
    // WCAG 2.0 contrast ratio calculation
    float l1 = luminance(color1) + 0.05;
    float l2 = luminance(color2) + 0.05;
    return max(l1, l2) / min(l1, l2);
}

vec4 contrasted_color(float min_ratio, vec4 fg, vec4 bg) {
    // Enforce minimum contrast by switching to white/black if needed
    if (contrast_ratio(fg.rgb, bg.rgb) < min_ratio) {
        float white_ratio = contrast_ratio(vec3(1.0), bg.rgb);
        float black_ratio = contrast_ratio(vec3(0.0), bg.rgb);
        return (white_ratio > black_ratio) ? vec4(1.0) : vec4(0.0);
    }
    return fg;
}
```

### 2.6 Fragment Shader (cell_text.f.glsl)

**Grayscale Atlas Path:**
```glsl
case ATLAS_GRAYSCALE: {
    float a = texture(atlas_grayscale, in_data.tex_coord).r;  // Alpha mask
    
    // Linear correction: Adjust alpha for gamma-incorrect appearance
    if (use_linear_correction) {
        float fg_l = luminance(color.rgb);
        float bg_l = luminance(bg.rgb);
        if (abs(fg_l - bg_l) > 0.001) {
            float blend_l = linearize(unlinearize(fg_l) * a + unlinearize(bg_l) * (1.0 - a));
            a = clamp((blend_l - bg_l) / (fg_l - bg_l), 0.0, 1.0);
        }
    }
    
    color *= a;  // Premultiplied alpha blending
    out_FragColor = color;
}
```

**Color Atlas Path:**
```glsl
case ATLAS_COLOR: {
    vec4 color = texture(atlas_color, in_data.tex_coord);  // Already premultiplied linear
    if (use_linear_blending) {
        out_FragColor = color;
        return;
    }
    // If not linear blending, unlinearize the color
    color.rgb /= vec3(color.a);
    color = unlinearize(color);
    color.rgb *= vec3(color.a);
    out_FragColor = color;
}
```

---

## 3. OPENGL USAGE

### 3.1 OpenGL Version & Features

**Requirements:**
- **OpenGL 4.3 core** (mandatory)
- **GLSL 430 core** (in shader code)
- Features used:
  - Framebuffer objects (FBO)
  - Vertex array objects (VAO)
  - Instanced rendering (`gl_InstanceID`)
  - Rectangle textures (`GL_TEXTURE_RECTANGLE`)
  - Compute-like structure with storage buffers
  - Debug output (if enabled)

**Version Check (OpenGL.zig:134-159):**
```zig
pub fn prepareContext(getProcAddress: anytype) !void {
    const version = try gl.glad.load(getProcAddress);
    const major = gl.glad.versionMajor(@intCast(version));
    const minor = gl.glad.versionMinor(@intCast(version));
    
    // Verify version
    if (major < MIN_VERSION_MAJOR or
        (major == MIN_VERSION_MAJOR and minor < MIN_VERSION_MINOR)) {
        return error.OpenGLOutdated;
    }
    
    // Enable debug output and SRGB framebuffer
    try gl.enable(gl.c.GL_DEBUG_OUTPUT);
    gl.glad.context.DebugMessageCallback.?(glDebugMessageCallback, null);
    try gl.enable(gl.c.GL_FRAMEBUFFER_SRGB);
}
```

### 3.2 Shader Compilation

**From Pipeline.zig:**
```zig
pub fn init(comptime VertexAttributes: ?type, opts: Options) !Self {
    // Compile vertex and fragment shaders
    const program = try gl.Program.createVF(
        opts.vertex_fn,    // GLSL source string
        opts.fragment_fn,   // GLSL source string
    );
    
    // Create framebuffer for off-screen rendering
    const fbo = try gl.Framebuffer.create();
    const fbobind = try fbo.bind(.framebuffer);
    defer fbobind.unbind();
    
    // Create and configure VAO with automatic attribute binding
    const vao = try gl.VertexArray.create();
    const vaobind = try vao.bind();
    defer vaobind.unbind();
    
    if (VertexAttributes) |VA| try autoAttribute(VA, vaobind, opts.step_fn);
    // ...
}
```

### 3.3 Shader Includes

**Dynamic Include Processing (shaders.zig:347-376):**
```zig
fn loadShaderCode(comptime path: []const u8) [:0]const u8 {
    return comptime processIncludes(@embedFile(path), std.fs.path.dirname(path).?);
}

fn processIncludes(contents: [:0]const u8, basedir: []const u8) [:0]const u8 {
    // Comptime processing of #include directives
    // Recursively processes common.glsl includes
}
```

Shader structure:
```glsl
#version 430 core
#include "common.glsl"  // Global uniforms, helper functions

// Shader-specific code
```

### 3.4 Uniform Buffers

**Global Uniforms Layout (shaders.zig:162-231):**
```zig
pub const Uniforms = extern struct {
    projection_matrix: math.Mat,           // 4×4 matrix (align 16)
    screen_size: [2]f32,                  // pixels (align 8)
    cell_size: [2]f32,                    // pixels (align 8)
    grid_size: [2]u16,                    // columns × rows (align 4)
    grid_padding: [4]f32,                 // top, right, bottom, left (align 16)
    padding_extend: PaddingExtend,        // Bit flags for which sides to extend (align 4)
    min_contrast: f32,                    // WCAG contrast ratio minimum (align 4)
    cursor_pos: [2]u16,                   // x, y in grid (align 4)
    cursor_color: [4]u8,                  // RGBA (align 4)
    bg_color: [4]u8,                      // RGBA (align 4)
    bools: Bools,                         // Packed flags (align 4)
};

pub const Bools = packed struct(u32) {
    cursor_wide: bool,              // Cursor spans 2 cells
    use_display_p3: bool,           // Color space indication
    use_linear_blending: bool,      // Blending mode
    use_linear_correction: bool,    // Weight correction for linear blending
    _padding: u28 = 0,
};
```

**Binding in Shader:**
```glsl
layout(binding = 1, std140) uniform Globals {
    uniform mat4 projection_matrix;
    uniform vec2 screen_size;
    // ... rest of fields
};
```

### 3.5 Storage Buffers

**Background Colors Buffer (cell_text.v.glsl:39-41):**
```glsl
layout(binding = 1, std430) readonly buffer bg_cells {
    uint bg_colors[];  // Packed 4u8 values
};
```

**Used in vertex shader to fetch background color for each cell:**
```glsl
vec4 bg = load_color(
    unpack4u8(bg_colors[grid_pos.y * grid_size.x + grid_pos.x]),
    true
);
```

### 3.6 Key OpenGL Calls

**Buffer Management (buffer.zig):**
```zig
pub fn sync(self: *Self, data: []const T) !void {
    const binding = try self.buffer.bind(self.opts.target);
    defer binding.unbind();
    
    if (data.len > self.len) {
        self.len = data.len * 2;  // Grow with 2× factor
        try binding.setDataNullManual(self.len * @sizeOf(T), self.opts.usage);
    }
    try binding.setSubData(0, data);  // Update buffer contents
}
```

**Texture Updates:**
```zig
pub fn replaceRegion(self: Self, x, y, width, height: usize, data: []const u8) Error!void {
    const texbind = self.texture.bind(self.target) catch return error.OpenGLFailed;
    defer texbind.unbind();
    texbind.subImage2D(0, x, y, width, height, self.format, .UnsignedByte, data.ptr);
}
```

**Framebuffer Blitting (OpenGL.zig:299-331):**
```zig
pub fn present(self: *OpenGL, target: Target) !void {
    // Disable SRGB during blit to preserve gamma-encoded values
    try gl.disable(gl.c.GL_FRAMEBUFFER_SRGB);
    defer gl.enable(gl.c.GL_FRAMEBUFFER_SRGB) catch |err| {...};
    
    const fbobind = try target.framebuffer.bind(.read);
    defer fbobind.unbind();
    
    // Blit from target framebuffer to default framebuffer (screen)
    gl.glad.context.BlitFramebuffer.?(0, 0, width, height, 0, 0, width, height, 
                                       gl.c.GL_COLOR_BUFFER_BIT, gl.c.GL_NEAREST);
}
```

### 3.7 Render Target

**Framebuffer + Renderbuffer (Target.zig):**
```zig
pub fn init(opts: Options) !Self {
    // Create renderbuffer with specified format
    const rbo = try gl.Renderbuffer.create();
    const bound_rbo = try rbo.bind();
    defer bound_rbo.unbind();
    try bound_rbo.storage(opts.internal_format, @intCast(opts.width), @intCast(opts.height));
    
    // Attach renderbuffer to framebuffer
    const fbo = try gl.Framebuffer.create();
    const bound_fbo = try fbo.bind(.framebuffer);
    defer bound_fbo.unbind();
    try bound_fbo.renderbuffer(.color0, rbo);
    
    return .{ .framebuffer = fbo, .renderbuffer = rbo, .width = opts.width, .height = opts.height };
}
```

**Internal Format Selection (OpenGL.zig:290-296):**
```zig
pub fn initTarget(self: *const OpenGL, width: usize, height: usize) !Target {
    return Target.init(.{
        .internal_format = if (self.blending.isLinear()) .srgba else .rgba,
        .width = width,
        .height = height,
    });
}
```

---

## 4. PERFORMANCE OPTIMIZATIONS

### 4.1 Dirty Tracking

**Row-Based Dirty Tracking (cell.zig):**
```zig
pub const Contents = struct {
    // ...
    pub fn clear(self: *Contents, y: terminal.size.CellCountInt) void {
        // Clear all cells in a row at once
        @memset(
            self.bg_cells[@as(usize, y) * self.size.columns ..][0..self.size.columns],
            .{ 0, 0, 0, 0 }
        );
        self.fg_rows.lists[y + 1].clearRetainingCapacity();
    }
};
```

Benefits:
- Only modified rows are rebuilt
- Avoids per-cell overhead
- Efficient for scrolling (most rows unchanged)

### 4.2 Incremental Rendering

**ArrayListCollection for Row Data (cell.zig:52-73):**
```zig
fg_rows: ArrayListCollection(shaderpkg.CellText) = .{},
// Each row can have a different number of glyphs
// (different widths, combining characters, etc.)
```

**Rebuilding Process (generic.zig):**
- Check if viewport/page has changed
- If changed, rebuild entire cell contents
- For unchanged viewport, only update dirty rows
- Sync only non-empty rows to GPU buffer

### 4.3 Batching & Instancing

**Per-Instance Rendering (shaders.zig:22-28):**
```zig
.{ "cell_text", .{
    .vertex_attributes = CellText,      // Per-instance data
    .vertex_fn = loadShaderCode("../shaders/glsl/cell_text.v.glsl"),
    .fragment_fn = loadShaderCode("../shaders/glsl/cell_text.f.glsl"),
    .step_fn = .per_instance,            // Draw per instance
    .blending_enabled = true,
} },
```

**Instance Divisor Setup (Pipeline.zig:82-96):**
```zig
fn autoAttribute(T: type, vaobind: gl.VertexArray.Binding, step_fn: Options.StepFunction) !void {
    const divisor: gl.c.GLuint = switch (step_fn) {
        .per_vertex => 0,      // Attribute repeats per vertex
        .per_instance => 1,    // Attribute changes per instance
        .constant => std.math.maxInt(gl.c.GLuint),  // Attribute never changes
    };
    
    // Set divisor for each attribute
    inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
        try vaobind.enableAttribArray(i);
        try vaobind.attributeBinding(i, 0);
        try vaobind.bindingDivisor(i, divisor);  // Instance divisor
        // ... set format
    }
}
```

**Drawing (conceptual):**
```
For each cell in grid:
  Add CellText instance to vertex buffer
  
Draw cells using instanced rendering:
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, num_instances)
  // 4 vertices per instance (quad), num_instances = total glyphs
```

### 4.4 Swap Chain

**Single Buffer (OpenGL.zig:32-33):**
```zig
pub const swap_chain_count = 1;
// Because OpenGL.finish() is synchronous, no multi-buffering needed
```

Unlike Metal which allows async GPU processing, OpenGL blocks on frame completion.

### 4.5 GPU Buffer Allocation Strategy

**Geometric Growth (buffer.zig:77-93):**
```zig
pub fn sync(self: *Self, data: []const T) !void {
    // If need more space, grow by 2×
    if (data.len > self.len) {
        self.len = data.len * 2;  // Exponential growth
        try binding.setDataNullManual(self.len * @sizeOf(T), self.opts.usage);
    }
    try binding.setSubData(0, data);  // Update data in-place
}
```

Rationale:
- Avoids frequent reallocations
- Reduces GPU memory fragmentation
- Most frames don't trigger reallocation

---

## 5. ANDROID COMPATIBILITY ANALYSIS

### 5.1 OpenGL ES 3.1 vs Desktop OpenGL 4.3

| Feature | Desktop GL 4.3 | OpenGL ES 3.1 | Status |
|---------|---|---|---|
| **Core Version** | 430 | 310 es | ❌ Different |
| **Texture Rect** | `GL_TEXTURE_RECTANGLE` | Not standard* | ⚠️ Needs adaptation |
| **Framebuffer Objects** | ✓ | ✓ | ✅ Compatible |
| **Vertex Arrays** | ✓ | ✓ | ✅ Compatible |
| **Instancing** | ✓ | ✓ | ✅ Compatible |
| **Rectangle Textures** | ✓ | ✗ | ❌ **Must change** |
| **Storage Buffers** | `std430` | `std430` | ✅ Compatible |
| **Std140 Uniforms** | ✓ | ✓ | ✅ Compatible |
| **Blitting FBO** | `BlitFramebuffer` | ✓ | ✅ Compatible |
| **Debug Output** | ✓ | Limited | ⚠️ Reduced |
| **sRGB Framebuffer** | `GL_FRAMEBUFFER_SRGB` | ✓ | ✅ Compatible |

**Note:** `GL_TEXTURE_RECTANGLE` is not available in OpenGL ES. Must use `GL_TEXTURE_2D` with normalized coordinates.

### 5.2 Critical Issues for Android Port

#### Issue 1: Rectangle Textures vs 2D Textures

**Current (Desktop):**
```glsl
layout(binding = 0) uniform sampler2DRect atlas_grayscale;
// Uses pixel coordinates (0 to width/height)
out_data.tex_coord = vec2(glyph_pos) + vec2(glyph_size) * corner;  // Pixel coords
```

**Required for OpenGL ES 3.1:**
```glsl
layout(binding = 0) uniform sampler2D atlas_grayscale;
// Must normalize coordinates (0.0 to 1.0)
out_data.tex_coord = (vec2(glyph_pos) + vec2(glyph_size) * corner) / vec2(textureSize(atlas_grayscale, 0));
```

**Changes needed:**
- Store atlas dimensions in uniform buffer
- Normalize texture coordinates in fragment shader
- Minimal performance impact (one extra division)

#### Issue 2: Full-Screen Vertex Shader

**Current (Desktop, GLSL 330):**
```glsl
#version 330 core
void main() {
    vec4 position;
    position.x = (gl_VertexID == 2) ? 3.0 : -1.0;
    position.y = (gl_VertexID == 0) ? -3.0 : 1.0;
    gl_Position = position;
}
```

**Required for OpenGL ES 3.1:**
```glsl
#version 310 es
void main() {
    // Same code works, but shader version must change
}
```

Compatible, just needs version update.

#### Issue 3: Shader Version Directives

**All shaders start with:**
```glsl
#version 430 core    // Desktop GL 4.3 core
```

**Must change to:**
```glsl
#version 310 es       // OpenGL ES 3.1
```

**Removed features in ES:**
- `core` keyword (ES doesn't have compatibility mode)
- Removed GLSL features aren't used in current code

#### Issue 4: Debug Output

**Current (OpenGL.zig:142-145):**
```zig
try gl.enable(gl.c.GL_DEBUG_OUTPUT);
gl.glad.context.DebugMessageCallback.?(glDebugMessageCallback, null);
```

**For Android:**
- `GL_KHR_debug` extension must be checked
- May not be available on all devices
- Wrap in extension guard

### 5.3 Adaptation Roadmap

```zig
// Proposed Android-specific configuration

pub const is_android = builtin.target.os.tag == .android;

pub const MIN_VERSION_MAJOR = if (is_android) 3 else 4;
pub const MIN_VERSION_MINOR = if (is_android) 1 else 3;

pub const GLSL_VERSION = if (is_android) "310 es" else "430 core";

pub fn initAtlasTexture(...) Texture.Error!Texture {
    const target: gl.Texture.Target = if (is_android) .@"2D" else .Rectangle;
    const min_filter: gl.Texture.MinFilter = .linear;  // Might need .nearest for ES
    
    return try Texture.init(.{
        .format = format,
        .internal_format = internal_format,
        .target = target,
        .min_filter = min_filter,
        .mag_filter = .linear,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    }, atlas.size, atlas.size, atlas_data);
}
```

### 5.4 Shader Adaptation Strategy

**Option A: Build-Time Selection**
```zig
const shader_common = 
    if (is_android)
        @embedFile("glsl/es31/common.glsl")
    else
        @embedFile("glsl/gl43/common.glsl");
```

**Option B: Runtime Compilation**
```zig
fn processShaderVersion(source: [:0]const u8, target: ShaderTarget) [:0]const u8 {
    // Replace #version line
    // Replace sampler2DRect with sampler2D
    // Add texture normalization code
}
```

**Recommended:** Option A (simpler, clearer)

### 5.5 Features That Will Work Without Changes

✅ **Will work directly:**
- Instanced rendering
- Per-cell color rendering
- Uniform buffers (std140 layout)
- Storage buffers (std430 layout)
- Framebuffer operations (except BlitFramebuffer might need FBO extension)
- Alpha blending
- Linear color space handling
- Minimum contrast calculations

✅ **Minor changes needed:**
- Shader version string
- Texture coordinate normalization
- Optional debug output (with extension check)

❌ **Major rework not needed:**
- Rendering pipeline architecture stays the same
- Cell data structures unchanged
- Glyph rasterization unchanged
- Color processing unchanged
- Dirty tracking unchanged

### 5.6 Expected Performance on Android

**Positive factors:**
- Tile-based deferred rendering (TBDR) on mobile GPUs actually benefits from this approach
- Instancing is well-optimized on mobile
- Texture Rectangle was designed for desktop efficiency; 2D textures are native to mobile

**Potential concerns:**
- Mobile GPUs have less memory bandwidth
- Battery life implications with high-frequency rendering
- Thermal management with continuous rendering

**Mitigation:**
- Existing dirty tracking helps reduce pixel shading
- Can add frame rate limiting
- Implement battery saver mode

---

## 6. SHADER CODE SUMMARY

### 6.1 Pipeline Overview

| Pipeline | Vertex | Fragment | Blending | Purpose |
|----------|--------|----------|----------|---------|
| **bg_color** | full_screen.v | bg_color.f | Disabled | Fill viewport with background |
| **cell_bg** | full_screen.v | cell_bg.f | Enabled | Per-cell background colors |
| **cell_text** | cell_text.v | cell_text.f | Enabled | Glyph rendering (main content) |
| **image** | image.v | image.f | Enabled | Foreground images |
| **bg_image** | bg_image.v | bg_image.f | Enabled | Background image |

### 6.2 Vertex Shader Strategy

**Full-Screen Shaders (bg_color, cell_bg):**
- No vertex attributes needed
- Single triangle covering viewport (using gl_VertexID = 0,1,2)
- Fragment shader does all work (computing grid positions)

**Instanced Shaders (cell_text, image, bg_image):**
- Per-instance attributes (glyph_pos, grid_pos, color, etc.)
- Generate quad (4 vertices) per instance
- Vertex shader: transform grid→world, apply metrics
- Fragment shader: sample texture, blend

### 6.3 Color Space Handling

**Two rendering modes:**

1. **Gamma-Incorrect Blending** (`USE_LINEAR_BLENDING = false`)
   - Input colors are sRGB (packed as 0-255)
   - Shaders apply gamma correction within blend
   - Result: appears correct but is mathematically incorrect
   - Faster, matches typical terminal behavior

2. **Linear Color Space** (`USE_LINEAR_BLENDING = true`)
   - Input colors linearized before blending
   - Blending happens in linear space
   - Result re-gamma-encoded for display
   - Mathematically correct
   - Optional linear correction to adjust text weight

**Minimum Contrast:**
- Ensures readability by enforcing WCAG contrast ratio
- Calculates luminance in linear space
- Switches text to white/black if contrast insufficient

---

## 7. KEY TAKEAWAYS FOR ANDROID PORT

### Summary of Changes Needed

| Item | Desktop GL | Android ES | Effort |
|------|------------|-----------|--------|
| Core API | OpenGL 4.3 | OpenGL ES 3.1 | Low |
| Texture targets | Rectangle | 2D | Low |
| Shader version | 430 core | 310 es | Trivial |
| Debug output | GL_DEBUG_OUTPUT | EXT_debug_marker | Low |
| Rendering pipeline | Unchanged | Unchanged | None |
| Color processing | Unchanged | Unchanged | None |
| Glyph rasterization | Unchanged | Unchanged | None |
| Cell data structures | Unchanged | Unchanged | None |

### Estimated Scope

- **Code changes:** ~200-300 lines
  - Shader version selection (50 lines)
  - Texture coordinate normalization (100 lines)
  - Android capability detection (50 lines)
  
- **Backward compatibility:** Full (can build both desktop and mobile)

- **Testing surface:** Relatively small
  - One visual rendering path
  - Existing automated tests apply

### Architecture Strengths for Mobile

1. **Batch-friendly:** Instancing is efficient on mobile GPUs
2. **Memory-aware:** Uses reasonable-sized buffers
3. **Power-aware:** Dirty tracking reduces unnecessary rendering
4. **Scalable:** Works with small screens easily
5. **No compute shaders:** Mobile GPUs have limited compute support

