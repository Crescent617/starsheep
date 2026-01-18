const std = @import("std");

pub fn Either(L: type, R: type) type {
    return union(enum) {
        L: L,
        R: R,
    };
}

pub fn Arc(T: type) type {
    return struct {
        const Ptr = struct {
            data: T,
            ref_count: std.atomic.Value(usize) = .init(1),
        };
        ptr: *Ptr,

        pub fn init(alloc: std.mem.Allocator, value: T) !Arc(T) {
            const alloc_ptr = try alloc.create(Ptr);
            alloc_ptr.* = Ptr{
                .data = value,
            };
            return Arc(T){
                .ptr = alloc_ptr,
            };
        }

        pub fn retain(self: Arc(T)) Arc(T) {
            _ = self.ptr.ref_count.fetchAdd(1, .seq_cst);
            return self;
        }

        pub fn release(self: Arc(T), alloc: std.mem.Allocator) void {
            const ret = self.ptr.ref_count.fetchSub(1, .seq_cst);
            if (ret == 1) {
                alloc.destroy(self.ptr);
            }
        }

        pub fn get(self: Arc(T)) *T {
            return &self.ptr.data;
        }
    };
}
