///! Main renderer module for Ghostty Android
///!
///! This manages all rendering pipelines and state for the terminal renderer.

const std = @import("std");
const gl = @import("gl_es.zig");
const Pipeline = @import("pipeline.zig");
const Buffer = @import("buffer.zig").Buffer;
const Texture = @import("texture.zig");
const shaders = @import("shaders.zig");
const shader_module = @import("shader.zig");
const DynamicFontSystem = @import("dynamic_font_system.zig").DynamicFontSystem;
const font_metrics = @import("font_metrics.zig");
const TerminalManager = @import("terminal_manager.zig");
const screen_extractor = @import("screen_extractor.zig");

const log = std.log.scoped(.renderer);

/// Animation duration constants (in nanoseconds)
const RIPPLE_DURATION_NS: i64 = 300_000_000; // 300ms
const SWEEP_DURATION_NS: i64 = 250_000_000; // 250ms

/// Microphone indicator state for always-on voice input
pub const MicIndicatorState = enum(u8) {
    off = 0,        // Hidden - no indicator shown
    idle = 1,       // Blue - connected, waiting for speech
    active = 2,     // Green with pulse - speech detected, recording
    err = 3,        // Red - error state
    processing = 4, // Amber with pulse - waiting for transcription response
};

const Self = @This();

/// Allocator for renderer resources
allocator: std.mem.Allocator,

/// Dynamic font system with full UTF-8 support
font_system: DynamicFontSystem,

/// Terminal manager for VT processing
terminal_manager: TerminalManager,

/// Mutex for thread-safe access to terminal_manager
/// Allows processInput to be called from any thread while render runs on GL thread
terminal_mutex: std.Thread.Mutex = .{},

/// Surface dimensions in pixels
width: u32 = 0,
height: u32 = 0,

/// Screen DPI (dots per inch) from Android
dpi: u16 = 160, // Default to mdpi baseline

/// Grid dimensions (terminal columns x rows)
grid_cols: u16 = 80,
grid_rows: u16 = 24,

/// Global uniforms buffer (UBO at binding point 1)
uniforms_buffer: Buffer(shaders.Uniforms),

/// Current uniforms state
uniforms: shaders.Uniforms,

/// Background color rendering pipeline
bg_color_pipeline: Pipeline,

/// Cell backgrounds SSBO (binding point 1) - holds per-cell background colors
cells_bg_buffer: Buffer(u32),

/// Cell backgrounds rendering pipeline
cell_bg_pipeline: Pipeline,

/// Grayscale font atlas (R8 texture) - for regular text glyphs
atlas_grayscale: Texture,

/// Color font atlas (RGBA8 texture) - for color emoji glyphs
atlas_color: Texture,

/// Atlas dimensions UBO (binding point 2)
atlas_dims_buffer: Buffer(shaders.AtlasDimensions),

/// Glyph instances buffer for cell_text pipeline
glyphs_buffer: Buffer(shaders.CellText),

/// Cell text rendering pipeline
cell_text_pipeline: Pipeline,

/// Ripple effect rendering pipeline (full-screen pass)
ripple_pipeline: Pipeline,

/// Sweep effect rendering pipeline (full-screen pass)
sweep_pipeline: Pipeline,

/// Tint overlay rendering pipeline (full-screen pass for session differentiation)
tint_pipeline: Pipeline,

/// Tint color (RGBA packed as u32) - set via setTintColor()
tint_color: u32 = 0,

/// Tint alpha (0.0 = invisible, 1.0 = fully opaque)
tint_alpha: f32 = 0.0,

/// Number of glyphs to render (for testing)
num_test_glyphs: u32 = 0,

/// FPS overlay glyph buffer (separate from main glyphs to avoid scroll interference)
fps_glyphs_buffer: Buffer(shaders.CellText),

/// VAO for FPS overlay (separate from main VAO to draw from fps_glyphs_buffer)
fps_vao: gl.VertexArray,

/// Number of FPS overlay glyphs
num_fps_glyphs: u32 = 0,

/// Visual scroll pixel offset for smooth sub-row scrolling (0 to cell_height)
/// This is used to provide smooth scrolling between row boundaries
scroll_pixel_offset: f32 = 0.0,

/// Whether to display FPS overlay
show_fps: bool = false,

/// FPS tracking fields
last_frame_time: i64 = 0,
frame_count: u32 = 0,
current_fps: u32 = 0,

/// Frame timing diagnostics
last_render_time: i64 = 0,
frame_times: [60]i64 = [_]i64{0} ** 60,  // Last 60 frame times in nanoseconds
frame_time_index: u32 = 0,
slow_frame_count: u32 = 0,  // Frames taking > 16.6ms (60fps threshold)
current_jitter_ms: f32 = 0.0,  // Current frame jitter (max - min)
current_max_ms: f32 = 0.0,  // Current max frame time
sync_time_ns: i64 = 0,  // Time spent in syncFromTerminal

/// Microphone indicator state
mic_indicator_state: MicIndicatorState = .off,

/// Mic indicator glyph buffer (separate from main glyphs)
mic_glyphs_buffer: Buffer(shaders.CellText),

/// VAO for mic indicator (separate from main VAO)
mic_vao: gl.VertexArray,

/// Number of mic indicator glyphs
num_mic_glyphs: u32 = 0,

/// Mic indicator pulse animation progress (0.0 to 1.0)
mic_pulse_progress: f32 = 0.0,

/// Ripple animation start time (nanoseconds, 0 = not active)
ripple_start_time_ns: i64 = 0,

/// Sweep animation start time (nanoseconds, 0 = not active)
sweep_start_time_ns: i64 = 0,

/// Cursor state for rendering (app-level state passed to cursor style helper)
focused: bool = true,
blink_visible: bool = true,
preedit_active: bool = false,

/// Initialize the renderer with optional initial dimensions and font size
/// If initial_font_size_px is 0, uses the default font size
pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, dpi: u16, initial_font_size_px: u32) !Self {
    log.info("Initializing renderer with dimensions: {d}x{d}, font size: {d}px", .{ width, height, initial_font_size_px });

    // Load and compile bg_color shaders
    const bg_color_vertex_src = shader_module.loadShaderCode("shaders/glsl/full_screen.v.glsl");
    const bg_color_fragment_src = shader_module.loadShaderCode("shaders/glsl/bg_color.f.glsl");

    // Create background color pipeline (no vertex attributes - full-screen triangle)
    const bg_color_pipeline = try Pipeline.init(null, .{
        .vertex_src = bg_color_vertex_src,
        .fragment_src = bg_color_fragment_src,
        .blending_enabled = false, // First pass, no blending needed
    });
    errdefer bg_color_pipeline.deinit();

    // Load and compile cell_bg shaders
    const cell_bg_vertex_src = shader_module.loadShaderCode("shaders/glsl/full_screen.v.glsl");
    const cell_bg_fragment_src = shader_module.loadShaderCode("shaders/glsl/cell_bg.f.glsl");

    // Create cell backgrounds pipeline (also uses full-screen triangle)
    const cell_bg_pipeline = try Pipeline.init(null, .{
        .vertex_src = cell_bg_vertex_src,
        .fragment_src = cell_bg_fragment_src,
        .blending_enabled = true, // Blend over bg_color
    });
    errdefer cell_bg_pipeline.deinit();

    // Create uniforms buffer
    var uniforms_buffer = try Buffer(shaders.Uniforms).init(.{
        .target = .uniform,
        .usage = .dynamic_draw,
    }, 1);
    errdefer uniforms_buffer.deinit();

    // Bind uniforms buffer to binding point 0 (matches shader layout)
    // Note: We use binding 0 for UBO since binding 1 is used for SSBO
    uniforms_buffer.bindBase(0);

    // Initialize dynamic font system with full UTF-8 support
    // Use provided font size if specified, otherwise use default
    const font_size = if (initial_font_size_px > 0)
        font_metrics.FontSize.fromPixels(@floatFromInt(initial_font_size_px), dpi)
    else
        font_metrics.FontSize.default(dpi);

    var font_system = try DynamicFontSystem.init(allocator, font_size);
    errdefer font_system.deinit();

    log.info("Font system initialized with {d:.1}pt font at {d} DPI", .{ font_size.points, dpi });

    // Get the actual cell size from the font system
    const actual_cell_size = font_system.getCellSize();
    const cell_width = @as(u32, @intFromFloat(actual_cell_size[0]));
    const cell_height = @as(u32, @intFromFloat(actual_cell_size[1]));

    const font_size_px = font_size.toPixels();
    log.info("Font metrics: {d:.1}pt = {d:.1}px at {d} DPI", .{ font_size.points, font_size_px, dpi });
    log.info("Cell dimensions: {d}x{d} pixels", .{ cell_width, cell_height });

    // Calculate viewport padding needed to prevent glyph clipping
    // Glyphs can extend past their cell boundaries due to font bearings
    const padding = font_system.getViewportPadding();
    log.info("Viewport padding: right={d}px, bottom={d}px", .{ padding.right, padding.bottom });

    // Calculate grid dimensions based on screen size and font-derived cell size
    const screen_w = if (width > 0) width else 800;
    const screen_h = if (height > 0) height else 600;

    log.info("Screen dimensions: {d}x{d} pixels", .{ screen_w, screen_h });
    log.info("Calculating grid: screen_width({d}) / cell_width({d}) = {d} cols", .{
        screen_w, cell_width, screen_w / cell_width
    });
    log.info("Calculating grid: screen_height({d}) / cell_height({d}) = {d} rows", .{
        screen_h, cell_height, screen_h / cell_height
    });

    const grid = font_metrics.GridCalculator.calculate(
        screen_w,
        screen_h,
        cell_width,
        cell_height,
        24,  // min_cols - reduced for mobile screens
        16   // min_rows - reduced for mobile screens
    );
    const initial_grid_cols = grid.cols;
    const initial_grid_rows = grid.rows;

    log.info("Final terminal grid: {d} cols × {d} rows", .{
        initial_grid_cols,
        initial_grid_rows,
    });

    // Verify the calculation
    const actual_width_used = initial_grid_cols * cell_width;
    const actual_height_used = initial_grid_rows * cell_height;
    log.info("Grid uses {d}x{d} pixels of {d}x{d} available", .{
        actual_width_used, actual_height_used, screen_w, screen_h
    });

    // Create cell backgrounds SSBO
    // Allocate buffers with maximum capacity to handle resizing (512x512 = 262k cells)
    const max_cells: u32 = 512 * 512;

    var cells_bg_buffer = try Buffer(u32).init(.{
        .target = .shader_storage,
        .usage = .dynamic_draw,
    }, max_cells);
    errdefer cells_bg_buffer.deinit();

    // Initialize with cleared data (no checkerboard pattern needed)
    const cell_colors = try allocator.alloc(u32, max_cells);
    defer allocator.free(cell_colors);

    // Clear all cells to transparent
    @memset(cell_colors, 0);

    // Upload cleared data to GPU
    try cells_bg_buffer.sync(cell_colors);

    // Bind SSBO to binding point 1 (matches shader layout)
    cells_bg_buffer.bindBase(1);

    // Initialize terminal manager with calculated dimensions
    var terminal_manager = try TerminalManager.init(allocator, @intCast(initial_grid_cols), @intCast(initial_grid_rows));
    errdefer terminal_manager.deinit();

    log.info("Terminal manager initialized ({d}x{d})", .{ initial_grid_cols, initial_grid_rows });

    // Get atlas dimensions from dynamic font system
    const font_atlas_dims = font_system.getAtlasDimensions();
    const atlas_width: u32 = font_atlas_dims[0];
    const atlas_height: u32 = font_atlas_dims[1];

    log.info("Atlas dimensions: {d}x{d}", .{ atlas_width, atlas_height });

    // Get the first grayscale atlas texture ID from the dynamic font system
    // The DynamicFontSystem manages its own atlases internally
    const grayscale_texture_id = font_system.getGrayscaleAtlas(0) orelse {
        log.err("No grayscale atlas available from DynamicFontSystem", .{});
        return error.NoGrayscaleAtlas;
    };

    // Create a Texture wrapper around the existing OpenGL texture
    const atlas_grayscale = Texture{
        .texture = gl.Texture{ .id = grayscale_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .red,
    };
    errdefer {} // Don't deinit - DynamicFontSystem owns this texture

    // Get the first RGBA atlas texture ID from the dynamic font system
    // This is used for color emoji
    const rgba_texture_id = font_system.getRgbaAtlas(0) orelse {
        log.err("No RGBA atlas available from DynamicFontSystem", .{});
        return error.NoRgbaAtlas;
    };

    // Create a Texture wrapper around the existing OpenGL texture
    const atlas_color = Texture{
        .texture = gl.Texture{ .id = rgba_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .rgba,
    };
    errdefer {} // Don't deinit - DynamicFontSystem owns this texture

    // Create atlas dimensions UBO
    var atlas_dims_buffer = try Buffer(shaders.AtlasDimensions).init(.{
        .target = .uniform,
        .usage = .static_draw,
    }, 1);
    errdefer atlas_dims_buffer.deinit();

    const atlas_dims = shaders.AtlasDimensions{
        .grayscale_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
        .color_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
    };
    try atlas_dims_buffer.sync(&[_]shaders.AtlasDimensions{atlas_dims});

    // Bind atlas dimensions to binding point 2
    atlas_dims_buffer.bindBase(2);

    // Load and compile cell_text shaders
    const cell_text_vertex_src = shader_module.loadShaderCode("shaders/glsl/cell_text.v.glsl");
    const cell_text_fragment_src = shader_module.loadShaderCode("shaders/glsl/cell_text.f.glsl");

    // Create glyphs instance buffer FIRST (before pipeline)
    // Allocate with max capacity to handle terminal resizing
    var glyphs_buffer = try Buffer(shaders.CellText).init(.{
        .target = .array,
        .usage = .dynamic_draw,
    }, max_cells);
    errdefer glyphs_buffer.deinit();

    // Create FPS overlay buffer (capacity for bg blocks + text glyphs, 2 lines)
    var fps_glyphs_buffer = try Buffer(shaders.CellText).init(.{
        .target = .array,
        .usage = .dynamic_draw,
    }, 128);
    errdefer fps_glyphs_buffer.deinit();

    // Create VAO for FPS overlay (must be separate from main VAO because
    // OpenGL ES 3.1 VAOs store the buffer ID when glVertexAttribPointer is called)
    const fps_vao = try gl.VertexArray.create();
    errdefer fps_vao.delete();

    // Configure FPS VAO with fps_glyphs_buffer bound
    fps_vao.bind();
    fps_glyphs_buffer.buffer.bind(fps_glyphs_buffer.opts.target);
    try Pipeline.autoConfigureAttributes(shaders.CellText, .per_instance);
    gl.VertexArray.unbind();

    // Create mic indicator buffer (capacity for bg block + mic glyph)
    var mic_glyphs_buffer = try Buffer(shaders.CellText).init(.{
        .target = .array,
        .usage = .dynamic_draw,
    }, 4); // 2 for background, 2 for glyphs
    errdefer mic_glyphs_buffer.deinit();

    // Create VAO for mic indicator (separate from main VAO)
    const mic_vao = try gl.VertexArray.create();
    errdefer mic_vao.delete();

    // Configure mic VAO with mic_glyphs_buffer bound
    mic_vao.bind();
    mic_glyphs_buffer.buffer.bind(mic_glyphs_buffer.opts.target);
    try Pipeline.autoConfigureAttributes(shaders.CellText, .per_instance);
    gl.VertexArray.unbind();

    // Bind the buffer so it's active when VAO attributes are configured
    glyphs_buffer.buffer.bind(glyphs_buffer.opts.target);

    // NOW create the pipeline - the VAO will be configured with the buffer bound
    const cell_text_pipeline = try Pipeline.init(shaders.CellText, .{
        .vertex_src = cell_text_vertex_src,
        .fragment_src = cell_text_fragment_src,
        .blending_enabled = true, // Blend text over background
        .step_fn = .per_instance, // Each glyph instance gets its own attributes
    });
    errdefer cell_text_pipeline.deinit();

    // Set sampler uniforms (OpenGL ES 3.1 doesn't support layout(binding) for samplers)
    cell_text_pipeline.program.use();
    const atlas_grayscale_loc = cell_text_pipeline.program.getUniformLocation("atlas_grayscale");
    log.info("atlas_grayscale uniform location: {}", .{atlas_grayscale_loc});
    if (atlas_grayscale_loc >= 0) {
        gl.uniform1i(atlas_grayscale_loc, 0); // Texture unit 0
    } else {
        log.warn("atlas_grayscale uniform not found!", .{});
    }

    const atlas_color_loc = cell_text_pipeline.program.getUniformLocation("atlas_color");
    log.info("atlas_color uniform location: {}", .{atlas_color_loc});
    if (atlas_color_loc >= 0) {
        gl.uniform1i(atlas_color_loc, 1); // Texture unit 1
    } else {
        log.warn("atlas_color uniform not found!", .{});
    }

    // Note: We leave the program bound after setting uniforms
    // The uniforms are part of the program state and will persist

    // Load and compile ripple shaders
    const ripple_vertex_src = shader_module.loadShaderCode("shaders/glsl/full_screen.v.glsl");
    const ripple_fragment_src = shader_module.loadShaderCode("shaders/glsl/ripple.f.glsl");

    // Create ripple pipeline (full-screen pass with blending)
    const ripple_pipeline = try Pipeline.init(null, .{
        .vertex_src = ripple_vertex_src,
        .fragment_src = ripple_fragment_src,
        .blending_enabled = true, // Blend ripple over everything
    });
    errdefer ripple_pipeline.deinit();

    // Load and compile sweep shaders
    const sweep_vertex_src = shader_module.loadShaderCode("shaders/glsl/full_screen.v.glsl");
    const sweep_fragment_src = shader_module.loadShaderCode("shaders/glsl/sweep.f.glsl");

    // Create sweep pipeline (full-screen pass with blending)
    const sweep_pipeline = try Pipeline.init(null, .{
        .vertex_src = sweep_vertex_src,
        .fragment_src = sweep_fragment_src,
        .blending_enabled = true, // Blend sweep over everything
    });
    errdefer sweep_pipeline.deinit();

    // Load and compile tint overlay shaders
    const tint_vertex_src = shader_module.loadShaderCode("shaders/glsl/full_screen.v.glsl");
    const tint_fragment_src = shader_module.loadShaderCode("shaders/glsl/tint_overlay.f.glsl");

    // Create tint overlay pipeline (full-screen pass with blending for session differentiation)
    const tint_pipeline = try Pipeline.init(null, .{
        .vertex_src = tint_vertex_src,
        .fragment_src = tint_fragment_src,
        .blending_enabled = true, // Blend tint over everything
    });
    errdefer tint_pipeline.deinit();

    // Extract terminal state and sync to GPU
    // (This will be done in a temporary renderer-like struct before full init)
    _ = 0; // Reserved for future test glyph count

    // Initialize default uniforms with actual dimensions
    const actual_width = if (width > 0) @as(f32, @floatFromInt(width)) else 800.0;
    const actual_height = if (height > 0) @as(f32, @floatFromInt(height)) else 600.0;

    // Projection matrix must match screen_size exactly for text/background alignment
    // Previously included padding which caused text to scale differently from backgrounds
    // (text was scaled by screen_size/projection_size, causing ~3.4px drift per row)
    // Note: padding is still logged below for debugging but not used in projection
    const projection_width = actual_width;
    const projection_height = actual_height;

    // Set OpenGL viewport to actual screen size
    gl.viewport(
        0,
        0,
        @intFromFloat(actual_width),
        @intFromFloat(actual_height),
    );
    log.info("Viewport set to {d}x{d} (actual screen size)", .{
        @as(u32, @intFromFloat(actual_width)),
        @as(u32, @intFromFloat(actual_height))
    });

    const uniforms = shaders.Uniforms{
        .projection_matrix = shaders.createOrthoMatrix(projection_width, projection_height),
        .screen_size = .{ actual_width, actual_height },
        .cell_size = font_system.getCellSize(), // Use actual font metrics
        .grid_size_packed_2u16 = shaders.Uniforms.pack2u16(@intCast(initial_grid_cols), @intCast(initial_grid_rows)),
        .grid_padding = .{ 0.0, 0.0, 0.0, 0.0 },
        .padding_extend = .{
            .right = true,  // Extend rightmost cell colors into right padding
            .down = true,   // Extend bottommost cell colors into bottom padding
        },
        .min_contrast = 1.0,
        .cursor_pos_packed_2u16 = shaders.Uniforms.pack2u16(255, 255), // Off-screen to avoid color override
        .cursor_color_packed_4u8 = shaders.Uniforms.pack4u8(255, 255, 255, 255), // White
        .bg_color_packed_4u8 = shaders.Uniforms.pack4u8(40, 20, 60, 255), // Purple (for testing)
        .bools = .{
            .cursor_wide = false,
            .use_display_p3 = false,
            .use_linear_blending = false,
            .use_linear_correction = false,
        },
        .font_decoration_metrics = font_system.getDecorationMetrics(), // Font-based decoration positions
        .baseline = font_system.getBaseline(), // Baseline position for glyph positioning
    };

    log.info("Cell size from font: {d}x{d}", .{ uniforms.cell_size[0], uniforms.cell_size[1] });
    log.info("Renderer initialized successfully with {d}x{d} grid ({d}x{d} screen)", .{
        initial_grid_cols,
        initial_grid_rows,
        actual_width,
        actual_height,
    });

    return .{
        .allocator = allocator,
        .font_system = font_system,
        .terminal_manager = terminal_manager,
        .width = if (width > 0) width else 0,
        .height = if (height > 0) height else 0,
        .dpi = dpi,
        .grid_cols = @intCast(initial_grid_cols),
        .grid_rows = @intCast(initial_grid_rows),
        .uniforms_buffer = uniforms_buffer,
        .uniforms = uniforms,
        .bg_color_pipeline = bg_color_pipeline,
        .cells_bg_buffer = cells_bg_buffer,
        .cell_bg_pipeline = cell_bg_pipeline,
        .atlas_grayscale = atlas_grayscale,
        .atlas_color = atlas_color,
        .atlas_dims_buffer = atlas_dims_buffer,
        .glyphs_buffer = glyphs_buffer,
        .fps_glyphs_buffer = fps_glyphs_buffer,
        .fps_vao = fps_vao,
        .mic_glyphs_buffer = mic_glyphs_buffer,
        .mic_vao = mic_vao,
        .cell_text_pipeline = cell_text_pipeline,
        .ripple_pipeline = ripple_pipeline,
        .sweep_pipeline = sweep_pipeline,
        .tint_pipeline = tint_pipeline,
        .num_test_glyphs = 0,
    };
}

pub fn deinit(self: *Self) void {
    log.info("Destroying renderer", .{});
    self.tint_pipeline.deinit();
    self.sweep_pipeline.deinit();
    self.ripple_pipeline.deinit();
    self.cell_text_pipeline.deinit();
    self.mic_vao.delete();
    self.mic_glyphs_buffer.deinit();
    self.fps_vao.delete();
    self.fps_glyphs_buffer.deinit();
    self.glyphs_buffer.deinit();
    self.atlas_dims_buffer.deinit();
    self.atlas_color.deinit();
    self.atlas_grayscale.deinit();
    self.cell_bg_pipeline.deinit();
    self.cells_bg_buffer.deinit();
    self.bg_color_pipeline.deinit();
    self.uniforms_buffer.deinit();
    self.terminal_manager.deinit();
    self.font_system.deinit();
}

/// Update surface size and recalculate projection matrix
pub fn resize(self: *Self, width: u32, height: u32) !void {
    log.info("Resizing renderer to {d}x{d}", .{ width, height });

    self.width = width;
    self.height = height;

    // Update screen size in uniforms
    self.uniforms.screen_size = .{
        @floatFromInt(width),
        @floatFromInt(height),
    };

    // Projection matrix must match screen_size exactly for text/background alignment
    // Previously included padding which caused text to scale differently from backgrounds
    const projection_width = @as(f32, @floatFromInt(width));
    const projection_height = @as(f32, @floatFromInt(height));

    self.uniforms.projection_matrix = shaders.createOrthoMatrix(
        projection_width,
        projection_height,
    );

    // Set OpenGL viewport to actual screen size
    gl.viewport(
        0,
        0,
        @intCast(width),
        @intCast(height),
    );

    // Calculate terminal grid dimensions based on screen size and cell size
    const cell_width = @as(u32, @intFromFloat(self.uniforms.cell_size[0]));
    const cell_height = @as(u32, @intFromFloat(self.uniforms.cell_size[1]));

    // Get viewport padding and subtract from screen size for accurate grid calculation
    const padding = self.font_system.getViewportPadding();
    const usable_width = width -| padding.right;
    const usable_height = height -| padding.bottom;

    // Use GridCalculator for proper grid dimension calculation
    const grid = font_metrics.GridCalculator.calculate(
        usable_width,
        usable_height,
        cell_width,
        cell_height,
        24,  // min_cols - reduced for mobile screens
        16   // min_rows - reduced for mobile screens
    );
    const new_cols = grid.cols;
    const new_rows = grid.rows;

    // Only resize terminal if dimensions actually changed
    if (new_cols != self.grid_cols or new_rows != self.grid_rows) {
        log.info("Resizing terminal from {d}x{d} to {d}x{d}", .{
            self.grid_cols, self.grid_rows, new_cols, new_rows
        });

        log.info("Terminal will wrap at column {d} (visible width)", .{new_cols});

        try self.terminal_manager.resize(new_cols, new_rows);
        self.grid_cols = new_cols;
        self.grid_rows = new_rows;

        // Update uniforms with new grid size
        self.uniforms.grid_size_packed_2u16 = shaders.Uniforms.pack2u16(new_cols, new_rows);
    }

    log.info("Cell size: {d}x{d}, Grid: {d}x{d}", .{
        self.uniforms.cell_size[0], self.uniforms.cell_size[1],
        self.grid_cols, self.grid_rows
    });

    // Upload updated uniforms to GPU
    try self.syncUniforms();
}

/// Sync uniforms buffer with current state
fn syncUniforms(self: *Self) !void {
    try self.uniforms_buffer.sync(&[_]shaders.Uniforms{self.uniforms});
}

/// Update animation progress based on elapsed time.
/// Called each frame from render() to drive ripple and sweep animations.
fn updateAnimations(self: *Self, now: i64) void {
    // Update ripple animation
    if (self.ripple_start_time_ns > 0) {
        const elapsed = now - self.ripple_start_time_ns;
        if (elapsed >= RIPPLE_DURATION_NS) {
            // Animation complete - reset
            self.uniforms.ripple_progress = 0.0;
            self.ripple_start_time_ns = 0;
        } else {
            // Calculate raw progress (0.0 to 1.0)
            const raw_progress = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(RIPPLE_DURATION_NS));
            // Apply decelerate easing: 1 - (1 - t)^2
            const eased = 1.0 - (1.0 - raw_progress) * (1.0 - raw_progress);
            self.uniforms.ripple_progress = eased;
        }
    }

    // Update sweep animation
    if (self.sweep_start_time_ns > 0) {
        const elapsed = now - self.sweep_start_time_ns;
        if (elapsed >= SWEEP_DURATION_NS) {
            // Animation complete - reset
            self.uniforms.sweep_progress = 0.0;
            self.uniforms.sweep_direction = 0;
            self.sweep_start_time_ns = 0;
        } else {
            // Calculate raw progress (0.0 to 1.0)
            const raw_progress = @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(SWEEP_DURATION_NS));
            // Apply decelerate easing: 1 - (1 - t)^2
            const eased = 1.0 - (1.0 - raw_progress) * (1.0 - raw_progress);
            self.uniforms.sweep_progress = eased;
        }
    }
}

/// Render a frame
pub fn render(self: *Self) !void {
    // Update FPS counter
    const now: i64 = @truncate(std.time.nanoTimestamp());
    self.frame_count += 1;

    // Frame timing diagnostics - measure time since last render
    const frame_delta = if (self.last_render_time > 0) now - self.last_render_time else 0;
    self.last_render_time = now;

    // Track frame times in circular buffer
    self.frame_times[self.frame_time_index] = frame_delta;
    self.frame_time_index = (self.frame_time_index + 1) % 60;

    // Detect slow frames (> 16.6ms = 60fps, > 11.1ms = 90fps)
    const slow_threshold: i64 = 11_111_111; // 11.1ms for 90fps
    const very_slow_threshold: i64 = 33_333_333; // 33.3ms = 30fps

    if (frame_delta > slow_threshold and frame_delta > 0) {
        self.slow_frame_count += 1;
        const frame_ms = @as(f32, @floatFromInt(frame_delta)) / 1_000_000.0;

        if (frame_delta > very_slow_threshold) {
            log.warn("SLOW FRAME: {d:.1}ms (frame #{d}, slow frames: {d})", .{
                frame_ms,
                self.frame_count,
                self.slow_frame_count,
            });
        }
    }

    // Update FPS every 500ms
    // Guard against clock issues (negative elapsed, division by zero)
    const elapsed = now - self.last_frame_time;
    if (elapsed >= 500_000_000) { // 500ms in nanoseconds
        // Calculate FPS: frames / (elapsed_seconds)
        // Clamp to reasonable range to avoid overflow
        const fps = @divFloor(@as(i64, self.frame_count) * 1_000_000_000, elapsed);
        self.current_fps = if (fps > 0 and fps <= 9999) @intCast(fps) else if (fps > 9999) 9999 else 0;

        // Log frame timing stats every 500ms
        var min_time: i64 = std.math.maxInt(i64);
        var max_time: i64 = 0;
        var sum_time: i64 = 0;
        var valid_count: u32 = 0;

        for (self.frame_times) |t| {
            if (t > 0) {
                min_time = @min(min_time, t);
                max_time = @max(max_time, t);
                sum_time += t;
                valid_count += 1;
            }
        }

        if (valid_count > 0) {
            const min_ms = @as(f32, @floatFromInt(min_time)) / 1_000_000.0;
            const max_ms = @as(f32, @floatFromInt(max_time)) / 1_000_000.0;
            const jitter_ms = max_ms - min_ms;

            // Store for display in FPS overlay
            self.current_jitter_ms = jitter_ms;
            self.current_max_ms = max_ms;
        }

        self.frame_count = 0;
        self.last_frame_time = now;
        self.slow_frame_count = 0;
    }

    // Skip syncing during synchronized output mode (ESC[?2026h).
    // This prevents partial/flickering frames during batched terminal updates.
    // We still render the existing buffers to avoid visual freeze.
    if (!self.terminal_manager.isSynchronizedOutputActive()) {
        // Sync renderer state from terminal (extract cells and update GPU buffers)
        const sync_start: i64 = @truncate(std.time.nanoTimestamp());
        try self.syncFromTerminal();
        const sync_end: i64 = @truncate(std.time.nanoTimestamp());
        self.sync_time_ns = sync_end - sync_start;
    }

    // Sync FPS overlay to separate buffer (rendered with scroll_pixel_offset=0)
    try self.syncFpsOverlay();

    // Sync mic indicator to separate buffer (rendered with scroll_pixel_offset=0)
    try self.syncMicIndicator();

    // Clear with transparent black (will be overwritten by bg_color shader)
    gl.clearColor(0.0, 0.0, 0.0, 0.0);
    gl.clear(gl.GL_COLOR_BUFFER_BIT);

    // Update animation progress (ripple, sweep) based on elapsed time
    self.updateAnimations(now);

    // Ensure uniforms are up to date
    try self.syncUniforms();

    // Render background color using full-screen triangle
    self.bg_color_pipeline.use();
    gl.drawArrays(gl.GL_TRIANGLES, 0, 3); // Draw 3 vertices for full-screen triangle

    // Render cell backgrounds (blended over bg_color)
    self.cell_bg_pipeline.use();
    gl.drawArrays(gl.GL_TRIANGLES, 0, 3); // Draw 3 vertices for full-screen triangle

    // Check for errors after cell backgrounds (non-fatal for now)
    gl.checkError() catch |err| {
        log.warn("GL error after cell_bg rendering (non-fatal): {}", .{err});
    };

    // Render cell text (blended over cell backgrounds)
    // First activate the pipeline (which binds the VAO)
    self.cell_text_pipeline.use();
    gl.checkError() catch |err| {
        log.err("GL error after pipeline.use(): {}", .{err});
    };

    // Then bind the glyphs buffer to the active VAO
    log.debug("Binding glyphs buffer", .{});
    self.glyphs_buffer.buffer.bind(self.glyphs_buffer.opts.target);
    gl.checkError() catch |err| {
        log.err("GL error after buffer bind: {}", .{err});
    };

    // Bind font atlas textures to their respective texture units
    log.debug("Binding atlas textures", .{});
    self.atlas_grayscale.bindToUnit(0); // Texture unit 0
    gl.checkError() catch |err| {
        log.err("GL error after grayscale texture bind: {}", .{err});
    };

    self.atlas_color.bindToUnit(1);     // Texture unit 1
    gl.checkError() catch |err| {
        log.err("GL error after color texture bind: {}", .{err});
    };

    // Draw glyphs using instanced rendering (4 vertices per glyph instance)
    if (self.num_test_glyphs > 0) {
        log.debug("Drawing {} glyphs with instanced rendering", .{self.num_test_glyphs});
        gl.drawArraysInstanced(gl.GL_TRIANGLE_STRIP, 0, 4, @intCast(self.num_test_glyphs));
        gl.checkError() catch |err| {
            log.err("GL error after drawArraysInstanced: {}", .{err});
        };
    } else {
        log.warn("num_test_glyphs is 0, skipping text rendering", .{});
    }

    // ============================================================================
    // Ripple Effect Pass (rendered on top of text, but under FPS)
    // ============================================================================
    if (self.uniforms.ripple_progress > 0.0 and self.uniforms.ripple_max_radius > 0.0) {
        self.ripple_pipeline.use();
        gl.drawArrays(gl.GL_TRIANGLES, 0, 3);
        gl.checkError() catch |err| {
            log.warn("GL error after ripple rendering: {}", .{err});
        };
    }

    // ============================================================================
    // Sweep Effect Pass (rendered on top of text, but under FPS)
    // ============================================================================
    if (self.uniforms.sweep_direction != 0 and self.uniforms.sweep_progress > 0.0) {
        self.sweep_pipeline.use();
        gl.drawArrays(gl.GL_TRIANGLES, 0, 3);
        gl.checkError() catch |err| {
            log.warn("GL error after sweep rendering: {}", .{err});
        };
    }

    // ============================================================================
    // Tint Overlay Pass (session differentiation - rendered on top of effects)
    // ============================================================================
    if (self.tint_alpha > 0.0) {
        // Update tint uniforms
        self.uniforms.tint_color_packed_4u8 = self.tint_color;
        self.uniforms.tint_alpha = self.tint_alpha;
        try self.syncUniforms();

        self.tint_pipeline.use();
        gl.drawArrays(gl.GL_TRIANGLES, 0, 3);
        gl.checkError() catch |err| {
            log.warn("GL error after tint rendering: {}", .{err});
        };
    }

    // ============================================================================
    // FPS Overlay Pass (rendered with scroll_pixel_offset=0 to stay fixed)
    // ============================================================================
    if (self.num_fps_glyphs > 0) {
        // Save current scroll offset
        const saved_scroll_offset = self.uniforms.scroll_pixel_offset;

        // Temporarily set scroll_pixel_offset to 0 so FPS doesn't scroll
        self.uniforms.scroll_pixel_offset = 0.0;
        try self.syncUniforms();

        // Bind the FPS VAO (which is configured to use fps_glyphs_buffer)
        // We must use a separate VAO because in OpenGL ES 3.1, the VAO stores
        // the buffer ID when glVertexAttribPointer is called
        self.fps_vao.bind();

        // Draw FPS glyphs
        log.debug("Drawing {} FPS glyphs", .{self.num_fps_glyphs});
        gl.drawArraysInstanced(gl.GL_TRIANGLE_STRIP, 0, 4, @intCast(self.num_fps_glyphs));
        gl.checkError() catch |err| {
            log.err("GL error after FPS drawArraysInstanced: {}", .{err});
        };

        // Restore original scroll offset
        self.uniforms.scroll_pixel_offset = saved_scroll_offset;
        // Note: We don't need to sync uniforms again since this is the end of render()
    }

    // ============================================================================
    // Mic Indicator Pass (rendered at top-left corner, with scroll_pixel_offset=0)
    // ============================================================================
    if (self.num_mic_glyphs > 0) {
        // Save current scroll offset
        const saved_scroll_offset = self.uniforms.scroll_pixel_offset;

        // Temporarily set scroll_pixel_offset to 0 so mic indicator doesn't scroll
        self.uniforms.scroll_pixel_offset = 0.0;
        try self.syncUniforms();

        // Bind the mic VAO (which is configured to use mic_glyphs_buffer)
        self.mic_vao.bind();

        // Draw mic indicator glyphs
        log.debug("Drawing {} mic indicator glyphs", .{self.num_mic_glyphs});
        gl.drawArraysInstanced(gl.GL_TRIANGLE_STRIP, 0, 4, @intCast(self.num_mic_glyphs));
        gl.checkError() catch |err| {
            log.err("GL error after mic indicator drawArraysInstanced: {}", .{err});
        };

        // Restore original scroll offset
        self.uniforms.scroll_pixel_offset = saved_scroll_offset;
    }
}

/// Update background color
pub fn setBackgroundColor(self: *Self, r: u8, g: u8, b: u8, a: u8) void {
    self.uniforms.bg_color_packed_4u8 = shaders.Uniforms.pack4u8(r, g, b, a);
}

/// Accent line height in pixels
const ACCENT_LINE_HEIGHT: f32 = 6.0;
/// Padding below the accent line
const ACCENT_LINE_PADDING: f32 = 2.0;

/// Set tint overlay color for session differentiation
/// The color is applied as a thin accent line at the top of the terminal
/// @param color ARGB color packed as u32 (e.g., 0xFF4CAF50 for green)
/// @param alpha Opacity from 0.0 (invisible) to 1.0 (fully opaque)
pub fn setTintColor(self: *Self, color: u32, alpha: f32) void {
    self.tint_color = color;
    self.tint_alpha = alpha;

    // Set the thickness uniform for the shader
    self.uniforms.tint_thickness = ACCENT_LINE_HEIGHT;

    // Adjust top grid padding to make room for the accent line
    if (alpha > 0.0) {
        self.uniforms.grid_padding[0] = ACCENT_LINE_HEIGHT + ACCENT_LINE_PADDING;
    } else {
        self.uniforms.grid_padding[0] = 0.0;
    }

    log.info("Tint color set: 0x{X:0>8}, alpha: {d:.2}, top_padding: {d:.1}", .{ color, alpha, self.uniforms.grid_padding[0] });
}

/// Update font size dynamically by rebuilding the font system and atlases
pub fn updateFontSize(self: *Self, new_font_size: u32) !void {
    log.info("Updating font size to {d}px", .{new_font_size});

    // 1. Deinitialize old font system
    self.font_system.deinit();

    // 2. Create new font system with new size
    // Convert pixels to points using the stored DPI
    const font_size_pts = (@as(f32, @floatFromInt(new_font_size)) * 72.0) / @as(f32, @floatFromInt(self.dpi));
    // Create a new font size from the point size
    const font_size = font_metrics.FontSize{
        .points = @floatCast(font_size_pts),
        .dpi = self.dpi,
    };
    self.font_system = try DynamicFontSystem.init(self.allocator, font_size);
    errdefer self.font_system.deinit();

    log.info("New font system initialized with size {d:.1}pt ({d}px) at {d} DPI", .{ font_size_pts, new_font_size, self.dpi });

    // 3. Get new atlas dimensions
    const font_atlas_dims = self.font_system.getAtlasDimensions();
    const atlas_width: u32 = font_atlas_dims[0];
    const atlas_height: u32 = font_atlas_dims[1];

    log.info("New atlas dimensions: {d}x{d}", .{ atlas_width, atlas_height });

    // 4. Update atlas references
    // The DynamicFontSystem manages its own atlases, so we just need to update our references
    const grayscale_texture_id = self.font_system.getGrayscaleAtlas(0) orelse {
        log.err("No grayscale atlas available from DynamicFontSystem", .{});
        return error.NoGrayscaleAtlas;
    };

    const rgba_texture_id = self.font_system.getRgbaAtlas(0) orelse {
        log.err("No RGBA atlas available from DynamicFontSystem", .{});
        return error.NoRgbaAtlas;
    };

    // Update the texture wrappers with the new IDs
    // Don't deinit - DynamicFontSystem owns the textures
    self.atlas_grayscale = Texture{
        .texture = gl.Texture{ .id = grayscale_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .red,
    };

    self.atlas_color = Texture{
        .texture = gl.Texture{ .id = rgba_texture_id },
        .width = atlas_width,
        .height = atlas_height,
        .format = .rgba,
    };

    log.info("Atlas references updated", .{});

    // 6. Update atlas dimensions UBO
    const atlas_dims = shaders.AtlasDimensions{
        .grayscale_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
        .color_size = .{ @floatFromInt(atlas_width), @floatFromInt(atlas_height) },
    };
    try self.atlas_dims_buffer.sync(&[_]shaders.AtlasDimensions{atlas_dims});

    log.info("Atlas dimensions buffer updated", .{});

    // 7. Update cell size and decoration metrics in uniforms
    const cell_size = self.font_system.getCellSize();
    self.uniforms.cell_size = cell_size;
    self.uniforms.font_decoration_metrics = self.font_system.getDecorationMetrics(); // Update decoration metrics
    self.uniforms.baseline = self.font_system.getBaseline(); // Update baseline for glyph positioning

    log.info("Cell size updated to: {}x{}", .{ cell_size[0], cell_size[1] });

    // 8. Recalculate grid dimensions based on new cell size
    const new_cell_width = @as(u32, @intFromFloat(cell_size[0]));
    const new_cell_height = @as(u32, @intFromFloat(cell_size[1]));

    // Get updated padding and subtract from screen size for accurate grid calculation
    const padding = self.font_system.getViewportPadding();
    const usable_width = self.width -| padding.right;
    const usable_height = self.height -| padding.bottom;

    const grid = font_metrics.GridCalculator.calculate(
        usable_width,
        usable_height,
        new_cell_width,
        new_cell_height,
        24,  // min_cols - reduced for mobile screens (same as init/resize)
        16   // min_rows - reduced for mobile screens (same as init/resize)
    );

    // Only resize terminal if dimensions actually changed
    if (grid.cols != self.grid_cols or grid.rows != self.grid_rows) {
        log.info("Font size change: resizing terminal {d}x{d} → {d}x{d}", .{
            self.grid_cols, self.grid_rows, grid.cols, grid.rows
        });

        // Before resize, log current terminal state
        const old_size = self.terminal_manager.getSize();
        log.info("Terminal size before resize: {d}x{d}", .{ old_size.cols, old_size.rows });

        // Sample some terminal content before resize
        const terminal = self.terminal_manager.getTerminal();
        const screen = terminal.screens.get(.primary).?;
        log.info("Before resize: screen has {} total rows, cursor at row {}", .{
            screen.pages.total_rows, screen.cursor.y
        });

        try self.terminal_manager.resize(grid.cols, grid.rows);

        // After resize, verify the new size and content
        const new_size = self.terminal_manager.getSize();
        log.info("Terminal size after resize: {d}x{d}", .{ new_size.cols, new_size.rows });

        // Check if content changed after resize
        const screen_after = terminal.screens.get(.primary).?;
        log.info("After resize: screen has {} total rows, cursor at row {}", .{
            screen_after.pages.total_rows, screen_after.cursor.y
        });

        self.grid_cols = grid.cols;
        self.grid_rows = grid.rows;

        // Update grid size in uniforms
        self.uniforms.grid_size_packed_2u16 = shaders.Uniforms.pack2u16(grid.cols, grid.rows);
    }

    // Sync all uniform changes
    try self.uniforms_buffer.sync(&[_]shaders.Uniforms{self.uniforms});

    // 9. Re-sync terminal content after resize to trigger proper reflow
    // This is crucial - the terminal has been resized and we need to
    // extract the reflowed content from ghostty-vt
    // Don't generate test glyphs here - syncFromTerminal will populate
    // the glyphs buffer with actual terminal content
    try self.syncFromTerminal();
}

/// Process VT input in a thread-safe manner.
/// Can be called from any thread - will acquire mutex and process input.
/// Note: This does NOT sync to GPU - that happens in the render loop.
pub fn processInput(self: *Self, data: []const u8) !void {
    self.terminal_mutex.lock();
    defer self.terminal_mutex.unlock();
    try self.terminal_manager.processInput(data);
}

/// Update renderer buffers from terminal state (thread-safe).
/// Called from the GL render loop.
pub fn syncFromTerminal(self: *Self) !void {
    self.terminal_mutex.lock();
    defer self.terminal_mutex.unlock();

    // Extract cell data from terminal
    const cells = try screen_extractor.extractCells(
        self.allocator,
        self.terminal_manager.getTerminal(),
    );
    defer screen_extractor.freeCells(self.allocator, cells);

    // Allocate temp buffers for GPU data
    const num_cells: usize = @intCast(self.grid_cols * self.grid_rows);
    var cell_bg_colors = try self.allocator.alloc(u32, num_cells);
    defer self.allocator.free(cell_bg_colors);

    var text_glyphs = try std.ArrayList(shaders.CellText).initCapacity(self.allocator, num_cells);
    defer text_glyphs.deinit(self.allocator);

    // Clear all backgrounds to default
    @memset(cell_bg_colors, 0);

    // Get selection bounds for highlighting
    const selection_bounds = self.terminal_manager.getSelectionBounds();

    // Process each cell
    for (cells) |cell| {
        const idx: usize = @as(usize, cell.row) * @as(usize, self.grid_cols) + @as(usize, cell.col);

        // Check if cell is within selection
        const is_selected = if (selection_bounds) |bounds| blk: {
            // Check if cell row is within selection rows
            if (cell.row < bounds.start_row or cell.row > bounds.end_row) {
                break :blk false;
            }
            // For single-row selection
            if (bounds.start_row == bounds.end_row) {
                break :blk cell.col >= bounds.start_col and cell.col <= bounds.end_col;
            }
            // For first row of multi-row selection
            if (cell.row == bounds.start_row) {
                break :blk cell.col >= bounds.start_col;
            }
            // For last row of multi-row selection
            if (cell.row == bounds.end_row) {
                break :blk cell.col <= bounds.end_col;
            }
            // Middle rows are fully selected
            break :blk true;
        } else false;

        // Pack background color (RGBA8) - use selection color if selected
        if (is_selected) {
            // Selection highlight color: semi-transparent blue
            cell_bg_colors[idx] = shaders.Uniforms.pack4u8(100, 149, 237, 180);
        } else {
            cell_bg_colors[idx] = shaders.Uniforms.pack4u8(
                cell.bg_color[0],
                cell.bg_color[1],
                cell.bg_color[2],
                cell.bg_color[3],
            );
        }

        // Skip wide character continuation cells
        if (cell.is_wide_continuation) {
            continue;
        }

        // Skip null characters (empty/uninitialized cells)
        if (cell.codepoint == 0) {
            continue;
        }

        // Only add renderable glyphs (skip spaces with default colors, unless inverse for cursor)
        if (cell.codepoint != ' ' or cell.fg_color[0] != 255 or cell.fg_color[1] != 255 or cell.fg_color[2] != 255 or cell.inverse) {
            // Convert CellData attributes to CellText attributes
            const attributes = shaders.CellText.Attributes{
                .bold = cell.bold,
                .italic = cell.italic,
                .dim = cell.dim,
                .strikethrough = cell.strikethrough,
                .underline = @enumFromInt(@intFromEnum(cell.underline)),
                .inverse = cell.inverse,
            };

            // For inverse video, render a background rectangle first
            if (cell.inverse) {
                // Render a full block character as background with swapped colors
                const block_char: u32 = 0x2588; // █ Full block character

                // Create attributes without inverse (we're manually swapping colors)
                const bg_attributes = shaders.CellText.Attributes{
                    .bold = false,
                    .italic = false,
                    .dim = false,
                    .strikethrough = false,
                    .underline = .none,
                    .inverse = false,
                };

                // Render the background block with original foreground color (which becomes background in inverse)
                try text_glyphs.append(self.allocator, (&self.font_system).makeCellText(
                    @intCast(block_char),
                    cell.col,
                    cell.row,
                    cell.fg_color, // Use fg color for the background block
                    bg_attributes,
                    1, // Block char is always single-width
                ));
            }

            try text_glyphs.append(self.allocator, (&self.font_system).makeCellText(
                cell.codepoint,
                cell.col,
                cell.row,
                cell.fg_color,
                attributes,
                cell.width, // Pass character width (1 for normal, 2 for wide chars)
            ));

            // Strikethrough is now rendered in the fragment shader as a graphical overlay
            // No need to add separate strikethrough characters anymore

            // Underline is now rendered in the fragment shader as a graphical overlay
            // No need to add separate underline characters anymore
        }
    }

    // Update render state and get cursor style using the cursor style helper.
    // This properly handles visibility modes, blink state, password input, focus, etc.
    try self.terminal_manager.updateRenderState();
    const cursor_style_opt = self.terminal_manager.getCursorStyle(.{
        .focused = self.focused,
        .blink_visible = self.blink_visible,
        .preedit = self.preedit_active,
    });

    // Get cursor viewport position from render state
    const cursor_viewport = self.terminal_manager.getCursorViewport();

    // Render cursor if style is not null (cursor should be visible)
    if (cursor_style_opt) |cursor_style| {
        if (cursor_viewport) |vp| {
            const viewport_x: u16 = vp.x;
            const viewport_y: u16 = vp.y;

            // Update cursor position in uniforms
            self.uniforms.cursor_pos_packed_2u16 = shaders.Uniforms.pack2u16(viewport_x, viewport_y);

            // Map cursor style to Unicode character
            const cursor_char: u21 = switch (cursor_style) {
                .block => 0x2588, // █ Full block
                .bar => 0x258F, // ▏ Left one-eighth block (thin vertical bar)
                .underline => 0x2581, // ▁ Lower one-eighth block (thin underline)
                .block_hollow => 0x25A1, // □ White square (hollow block)
                .lock => 0x25A3, // ▣ White square containing black square (password input)
            };

            // Add cursor glyph at the viewport position
            const cursor_color = [4]u8{ 255, 255, 255, 255 }; // White cursor
            var cursor_glyph = (&self.font_system).makeCellText(
                cursor_char,
                viewport_x,
                viewport_y,
                cursor_color,
                .{}, // No special attributes
                1, // Single width
            );
            cursor_glyph.bools.is_cursor_glyph = true;
            try text_glyphs.append(self.allocator, cursor_glyph);
        } else {
            // Cursor is outside viewport (scrolled off-screen)
            self.uniforms.cursor_pos_packed_2u16 = shaders.Uniforms.pack2u16(255, 255);
        }
    } else {
        // Cursor hidden (blink off, visibility disabled, etc.)
        self.uniforms.cursor_pos_packed_2u16 = shaders.Uniforms.pack2u16(255, 255);
    }

    // Upload to GPU
    try self.cells_bg_buffer.sync(cell_bg_colors);
    try self.glyphs_buffer.sync(text_glyphs.items);
    self.num_test_glyphs = @intCast(text_glyphs.items.len);

    // Sync uniforms to GPU (includes cursor position update)
    try self.syncUniforms();
}

/// Process VT input and sync to renderer (legacy API for GL thread usage).
/// For thread-safe input processing from any thread, use processInput() instead.
/// Respects synchronized output mode (ESC[?2026h/l) - only syncs when mode is inactive.
/// This allows batched updates to complete before rendering.
pub fn processTerminalInput(self: *Self, data: []const u8) !void {
    // Use thread-safe processInput
    try self.processInput(data);

    // Only sync after processing if synchronized output mode is not active.
    // If the input contained ESC[?2026l (end sync), the mode will be off now,
    // and we'll sync the complete batched state.
    // Note: This check is safe because render loop also checks before syncing.
    self.terminal_mutex.lock();
    const sync_active = self.terminal_manager.isSynchronizedOutputActive();
    self.terminal_mutex.unlock();

    if (!sync_active) {
        try self.syncFromTerminal();
    }
}

// ============================================================================
// Scrolling API
// ============================================================================

/// Get the number of scrollback rows available
pub fn getScrollbackRows(self: *Self) usize {
    return self.terminal_manager.getScrollbackRows();
}

/// Get the font line spacing (cell height) for scroll calculations
pub fn getFontLineSpacing(self: *Self) f32 {
    return self.uniforms.cell_size[1];
}

/// Get the content height in pixels (rows with content * line spacing)
pub fn getContentHeight(self: *Self) f32 {
    const content_rows = self.terminal_manager.getContentRows();
    const line_spacing = self.uniforms.cell_size[1];
    return @as(f32, @floatFromInt(content_rows)) * line_spacing;
}

/// Scroll the viewport by a delta number of rows
/// Positive delta scrolls down (towards newer content/active area)
/// Negative delta scrolls up (towards older content/scrollback)
pub fn scrollDelta(self: *Self, delta: i32) void {
    self.terminal_manager.scrollDelta(delta);
}

/// Check if viewport is at the bottom (following active area)
pub fn isViewportAtBottom(self: *Self) bool {
    return self.terminal_manager.isViewportAtBottom();
}

/// Get the current scroll offset from the top (0 = at top of scrollback)
pub fn getViewportOffset(self: *Self) usize {
    return self.terminal_manager.getViewportOffset();
}

/// Scroll viewport to the bottom (active area)
pub fn scrollToBottom(self: *Self) void {
    self.terminal_manager.scrollToBottom();
}

/// Scroll viewport to an absolute row offset
/// Row 0 is the top of scrollback, and increases towards the active area
/// Use getViewportOffset() to get the current offset for later restoration
pub fn scrollToViewportOffset(self: *Self, row: usize) void {
    self.terminal_manager.scrollToViewportOffset(row);
}

/// Save the current viewport anchor for scroll preservation across resize.
/// Call this BEFORE resize operations.
pub fn saveViewportAnchor(self: *Self) void {
    self.terminal_manager.saveViewportAnchor();
}

/// Restore the viewport to the previously saved anchor after resize.
/// Call this AFTER resize operations.
pub fn restoreViewportAnchor(self: *Self) void {
    self.terminal_manager.restoreViewportAnchor();
}

// ============================================================================
// Cursor State API (for future JNI binding)
// ============================================================================

/// Set whether the terminal surface has focus.
/// When unfocused, the cursor renders as a hollow block.
pub fn setFocused(self: *Self, focused: bool) void {
    self.focused = focused;
}

/// Set the blink visible state for cursor animation.
/// When false and cursor is blinking, cursor is hidden.
pub fn setBlinkVisible(self: *Self, visible: bool) void {
    self.blink_visible = visible;
}

/// Set whether IME preedit/composition is active.
/// When active, cursor always shows as a block.
pub fn setPreeditActive(self: *Self, active: bool) void {
    self.preedit_active = active;
}

/// Set the visual scroll pixel offset for smooth sub-row scrolling
/// This offset is applied in the shaders to shift content by a sub-row amount
/// for smooth scrolling animation between row boundaries.
pub fn setScrollPixelOffset(self: *Self, offset: f32) void {
    self.scroll_pixel_offset = offset;
    self.uniforms.scroll_pixel_offset = offset;
}

// ============================================================================
// FPS Overlay
// ============================================================================

/// Enable or disable FPS display overlay
pub fn setShowFps(self: *Self, show: bool) void {
    log.info("setShowFps: {}", .{show});
    self.show_fps = show;
}

/// Set the microphone indicator state
pub fn setMicIndicatorState(self: *Self, state: u8) void {
    const new_state = std.meta.intToEnum(MicIndicatorState, state) catch .off;
    log.info("setMicIndicatorState: {} -> {}", .{ self.mic_indicator_state, new_state });
    self.mic_indicator_state = new_state;
    // Reset pulse animation when state changes to active or processing
    if (new_state == .active or new_state == .processing) {
        self.mic_pulse_progress = 0.0;
    }
}

/// Sync FPS overlay glyphs to the separate FPS buffer
/// This is called from render() and updates fps_glyphs_buffer directly.
fn syncFpsOverlay(self: *Self) !void {
    if (!self.show_fps) {
        self.num_fps_glyphs = 0;
        return;
    }
    if (self.grid_cols < 8) {
        self.num_fps_glyphs = 0;
        return;
    }

    // Format display strings - show FPS, jitter, and sync time
    // Line 1: "FPS:XXX J:XXms" (FPS and jitter)
    // Line 2: "Mx:XXms S:XXms" (max frame time and sync time)
    var line1_buf: [20]u8 = undefined;
    var line2_buf: [20]u8 = undefined;

    const jitter_int: u32 = @intFromFloat(self.current_jitter_ms);
    const max_int: u32 = @intFromFloat(self.current_max_ms);
    const sync_ms = @as(f32, @floatFromInt(self.sync_time_ns)) / 1_000_000.0;
    const sync_int: u32 = @intFromFloat(sync_ms);

    const line1 = std.fmt.bufPrint(&line1_buf, "{d:3}fps J:{d:2}ms", .{ self.current_fps, jitter_int }) catch "???";
    const line2 = std.fmt.bufPrint(&line2_buf, "Mx:{d:2} Sy:{d:2}ms", .{ max_int, sync_int }) catch "???";

    // Colors for FPS overlay
    const bg_color = [4]u8{ 0, 0, 0, 220 }; // Semi-transparent black background

    // Color based on jitter - green if good, yellow if moderate, red if bad
    const text_color: [4]u8 = if (self.current_jitter_ms < 5.0)
        [4]u8{ 0, 255, 0, 255 } // Green - smooth
    else if (self.current_jitter_ms < 15.0)
        [4]u8{ 255, 255, 0, 255 } // Yellow - moderate jitter
    else
        [4]u8{ 255, 80, 80, 255 }; // Red - high jitter (laggy)

    // No special attributes
    const attributes = shaders.CellText.Attributes{};

    // Build glyph array for FPS overlay (2 lines now)
    var fps_glyphs: [128]shaders.CellText = undefined;
    var glyph_count: u32 = 0;

    const block_char: u32 = 0x2588; // █ Full block character

    // Helper to add a line of text at a given row
    const addLine = struct {
        fn add(
            glyphs: *[128]shaders.CellText,
            count: *u32,
            text: []const u8,
            row: u16,
            grid_cols: u16,
            bg: [4]u8,
            fg: [4]u8,
            attrs: shaders.CellText.Attributes,
            font_sys: *DynamicFontSystem,
        ) void {
            const text_len: u16 = @intCast(@min(text.len, grid_cols));
            const start_col: u16 = grid_cols -| text_len;

            // Add background blocks
            for (text, 0..) |_, i| {
                const col = start_col +| @as(u16, @intCast(i));
                if (col >= grid_cols) break;
                if (count.* >= 64) break;

                glyphs[count.*] = font_sys.makeCellText(
                    block_char,
                    col,
                    row,
                    bg,
                    attrs,
                    1,
                );
                count.* += 1;
            }

            // Add text glyphs
            for (text, 0..) |char, i| {
                const col = start_col +| @as(u16, @intCast(i));
                if (col >= grid_cols) break;
                if (count.* >= 128) break;

                glyphs[count.*] = font_sys.makeCellText(
                    char,
                    col,
                    row,
                    fg,
                    attrs,
                    1,
                );
                count.* += 1;
            }
        }
    }.add;

    // Add line 1 at row 0
    addLine(&fps_glyphs, &glyph_count, line1, 0, self.grid_cols, bg_color, text_color, attributes, &self.font_system);

    // Add line 2 at row 1
    addLine(&fps_glyphs, &glyph_count, line2, 1, self.grid_cols, bg_color, text_color, attributes, &self.font_system);

    // Upload to FPS buffer
    try self.fps_glyphs_buffer.sync(fps_glyphs[0..glyph_count]);
    self.num_fps_glyphs = glyph_count;
}

/// Sync mic indicator glyphs to the separate mic buffer
/// This is called from render() and updates mic_glyphs_buffer directly.
fn syncMicIndicator(self: *Self) !void {
    if (self.mic_indicator_state == .off) {
        self.num_mic_glyphs = 0;
        return;
    }

    // Update pulse animation progress for active and processing states
    if (self.mic_indicator_state == .active or self.mic_indicator_state == .processing) {
        // Processing pulses faster (0.08) than active (0.05)
        const pulse_speed: f32 = if (self.mic_indicator_state == .processing) 0.08 else 0.05;
        self.mic_pulse_progress += pulse_speed;
        if (self.mic_pulse_progress > 1.0) {
            self.mic_pulse_progress = 0.0;
        }
    }

    // Use a mic icon character (🎤 = U+1F3A4 might not render well, use a simpler indicator)
    // We'll use ● (U+25CF) or ◉ (U+25C9) as a simple filled circle indicator
    const indicator_char: u32 = 0x25CF; // ● Black circle

    // Colors based on state
    const text_color: [4]u8 = switch (self.mic_indicator_state) {
        .off => [4]u8{ 0, 0, 0, 0 }, // Should not reach here
        .idle => [4]u8{ 66, 165, 245, 255 }, // Blue (#42A5F5)
        .active => blk: {
            // Pulse effect: interpolate alpha based on progress
            const pulse_alpha: u8 = @intFromFloat(200.0 + 55.0 * @sin(self.mic_pulse_progress * std.math.pi * 2.0));
            break :blk [4]u8{ 76, 175, 80, pulse_alpha }; // Green (#4CAF50) with pulsing alpha
        },
        .err => [4]u8{ 244, 67, 54, 255 }, // Red (#F44336)
        .processing => blk: {
            // Pulse effect: interpolate alpha based on progress (faster pulse)
            const pulse_alpha: u8 = @intFromFloat(200.0 + 55.0 * @sin(self.mic_pulse_progress * std.math.pi * 2.0));
            break :blk [4]u8{ 255, 152, 0, pulse_alpha }; // Amber (#FF9800) with pulsing alpha
        },
    };

    // Background color (dark semi-transparent)
    const bg_color = [4]u8{ 0, 0, 0, 200 };

    // No special attributes
    const attributes = shaders.CellText.Attributes{};

    var mic_glyphs: [4]shaders.CellText = undefined;
    var glyph_count: u32 = 0;

    // Position at top-right corner
    const right_col: u16 = if (self.grid_cols > 0) self.grid_cols - 1 else 0;

    // Add background block (full block character)
    const block_char: u32 = 0x2588; // █ Full block character
    mic_glyphs[glyph_count] = (&self.font_system).makeCellText(
        block_char,
        right_col, // top-right column
        0, // row 0
        bg_color,
        attributes,
        1, // single width
    );
    glyph_count += 1;

    // Add the indicator glyph on top
    mic_glyphs[glyph_count] = (&self.font_system).makeCellText(
        indicator_char,
        right_col, // top-right column
        0, // row 0
        text_color,
        attributes,
        1, // single width
    );
    glyph_count += 1;

    // Upload to mic buffer
    try self.mic_glyphs_buffer.sync(mic_glyphs[0..glyph_count]);
    self.num_mic_glyphs = glyph_count;
}

// ============================================================================
// Ripple Effect
// ============================================================================

/// Start a ripple effect at the given position.
/// Animation is driven by the render loop using nanoTimestamp.
/// @param center_x X coordinate in screen pixels
/// @param center_y Y coordinate in screen pixels
/// @param max_radius Maximum radius the ripple will expand to
pub fn startRipple(self: *Self, center_x: f32, center_y: f32, max_radius: f32) void {
    self.uniforms.ripple_center = .{ center_x, center_y };
    self.uniforms.ripple_max_radius = max_radius;
    self.uniforms.ripple_progress = 0.0;
    self.ripple_start_time_ns = @truncate(std.time.nanoTimestamp());
}

/// Update the ripple animation progress.
/// @param progress Animation progress from 0.0 (start) to 1.0 (end)
pub fn updateRipple(self: *Self, progress: f32) void {
    self.uniforms.ripple_progress = progress;
}

// ============================================================================
// Sweep Effect
// ============================================================================

/// Sweep direction constants
pub const SweepDirection = enum(u32) {
    none = 0,
    up = 1,
    down = 2,
};

/// Start a sweep effect in the given direction.
/// Animation is driven by the render loop using nanoTimestamp.
/// @param direction 1 = sweep up (bottom to top), 2 = sweep down (top to bottom)
pub fn startSweep(self: *Self, direction: u32) void {
    self.uniforms.sweep_direction = direction;
    self.uniforms.sweep_progress = 0.0;
    self.sweep_start_time_ns = @truncate(std.time.nanoTimestamp());
}

/// Update the sweep animation progress.
/// @param progress Animation progress from 0.0 (start) to 1.0 (end)
pub fn updateSweep(self: *Self, progress: f32) void {
    self.uniforms.sweep_progress = progress;
    // Only clear direction when animation completes (not at start!)
    if (progress >= 1.0) {
        self.uniforms.sweep_direction = 0;
    }
}
