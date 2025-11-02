///! Buffer management for OpenGL ES 3.1
///!
///! This module provides typed buffer wrappers for managing vertex buffers,
///! uniform buffers (UBO), and shader storage buffers (SSBO).

const std = @import("std");
const gl = @import("gl_es.zig");

/// Options for initializing a buffer.
pub const Options = struct {
    target: gl.Buffer.Target = .array,
    usage: gl.Buffer.Usage = .dynamic_draw,
};

/// OpenGL data storage for a certain set of equal types. This is usually
/// used for vertex buffers, UBOs, SSBOs, etc. This helpful wrapper makes it
/// easy to prealloc, shrink, grow, and sync buffers with OpenGL.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Underlying GL buffer object.
        buffer: gl.Buffer,

        /// Options this buffer was allocated with.
        opts: Options,

        /// Current allocated length of the data store.
        /// Note this is the number of `T`s, not the size in bytes.
        len: usize,

        /// Initialize a buffer with the given length pre-allocated.
        pub fn init(opts: Options, len: usize) !Self {
            const buffer = try gl.Buffer.create();
            errdefer buffer.delete();

            buffer.bind(opts.target);
            defer gl.Buffer.unbind(opts.target);

            gl.Buffer.setData(
                opts.target,
                len * @sizeOf(T),
                null,
                opts.usage,
            );

            return .{
                .buffer = buffer,
                .opts = opts,
                .len = len,
            };
        }

        /// Init the buffer filled with the given data.
        pub fn initFill(opts: Options, data: []const T) !Self {
            const buffer = try gl.Buffer.create();
            errdefer buffer.delete();

            buffer.bind(opts.target);
            defer gl.Buffer.unbind(opts.target);

            gl.Buffer.setData(
                opts.target,
                data.len * @sizeOf(T),
                data.ptr,
                opts.usage,
            );

            return .{
                .buffer = buffer,
                .opts = opts,
                .len = data.len,
            };
        }

        pub fn deinit(self: Self) void {
            self.buffer.delete();
        }

        /// Sync new contents to the buffer. The data is expected to be the
        /// complete contents of the buffer. If the amount of data is larger
        /// than the buffer length, the buffer will be reallocated.
        ///
        /// If the amount of data is smaller than the buffer length, the
        /// remaining data in the buffer is left untouched.
        pub fn sync(self: *Self, data: []const T) !void {
            self.buffer.bind(self.opts.target);
            defer gl.Buffer.unbind(self.opts.target);

            // If we need more space than our buffer has, we need to reallocate.
            if (data.len > self.len) {
                // Reallocate the buffer to hold double what we require.
                self.len = data.len * 2;
                gl.Buffer.setData(
                    self.opts.target,
                    self.len * @sizeOf(T),
                    null,
                    self.opts.usage,
                );
            }

            // We can fit within the buffer so we can just replace bytes.
            if (data.len > 0) {
                gl.Buffer.setSubData(
                    self.opts.target,
                    0,
                    data.len * @sizeOf(T),
                    data.ptr,
                );
            }
        }

        /// Like Buffer.sync but takes data from an array of ArrayLists,
        /// rather than a single array. Returns the number of items synced.
        pub fn syncFromArrayLists(
            self: *Self,
            lists: []const std.ArrayListUnmanaged(T),
        ) !usize {
            self.buffer.bind(self.opts.target);
            defer gl.Buffer.unbind(self.opts.target);

            var total_len: usize = 0;
            for (lists) |list| {
                total_len += list.items.len;
            }

            // If we need more space than our buffer has, we need to reallocate.
            if (total_len > self.len) {
                // Reallocate the buffer to hold double what we require.
                self.len = total_len * 2;
                gl.Buffer.setData(
                    self.opts.target,
                    self.len * @sizeOf(T),
                    null,
                    self.opts.usage,
                );
            }

            // We can fit within the buffer so we can just replace bytes.
            var offset: usize = 0;
            for (lists) |list| {
                if (list.items.len > 0) {
                    gl.Buffer.setSubData(
                        self.opts.target,
                        offset,
                        list.items.len * @sizeOf(T),
                        list.items.ptr,
                    );
                    offset += list.items.len * @sizeOf(T);
                }
            }

            return total_len;
        }

        /// Bind this buffer to a uniform buffer binding point (for UBOs)
        pub fn bindBase(self: Self, index: u32) void {
            self.buffer.bindBase(self.opts.target, index);
        }
    };
}
