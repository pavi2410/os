//! Linux mmap protection and mapping flags shared by kernel and userspace.

/// Linux `PROT_*` bits as a packed flag word.
pub const Prot = packed struct(u32) {
    read: bool = false,
    write: bool = false,
    exec: bool = false,
    _: u29 = 0,

    pub fn fromLinux(n: u32) Prot {
        return @bitCast(n);
    }

    pub fn toLinux(self: Prot) u32 {
        return @bitCast(self);
    }

    pub fn merge(self: Prot, other: Prot) Prot {
        return fromLinux(self.toLinux() | other.toLinux());
    }

    pub fn violatesWx(self: Prot) bool {
        return self.write and self.exec;
    }
};

/// Linux `MAP_*` subset used by this OS.
pub const MapFlags = packed struct(u32) {
    shared: bool = false,
    private: bool = false,
    _pad0: u2 = 0,
    fixed: bool = false,
    anonymous: bool = false,
    _: u26 = 0,

    pub fn fromLinux(n: u32) MapFlags {
        return @bitCast(n);
    }

    pub fn toLinux(self: MapFlags) u32 {
        return @bitCast(self);
    }

    pub fn merge(self: MapFlags, other: MapFlags) MapFlags {
        return fromLinux(self.toLinux() | other.toLinux());
    }

    pub fn hasUnsupported(self: MapFlags) bool {
        const supported = MapFlags{ .private = true, .fixed = true, .anonymous = true };
        return self.toLinux() & ~supported.toLinux() != 0;
    }
};

comptime {
    if (@as(u32, @bitCast(Prot{ .read = true })) != 0x1) @compileError("Prot.read must be bit 0");
    if (@as(u32, @bitCast(Prot{ .write = true })) != 0x2) @compileError("Prot.write must be bit 1");
    if (@as(u32, @bitCast(Prot{ .exec = true })) != 0x4) @compileError("Prot.exec must be bit 2");
    if (@as(u32, @bitCast(MapFlags{ .shared = true })) != 0x01) @compileError("MapFlags.shared must be bit 0");
    if (@as(u32, @bitCast(MapFlags{ .private = true })) != 0x02) @compileError("MapFlags.private must be bit 1");
    if (@as(u32, @bitCast(MapFlags{ .fixed = true })) != 0x10) @compileError("MapFlags.fixed must be bit 4");
    if (@as(u32, @bitCast(MapFlags{ .anonymous = true })) != 0x20) @compileError("MapFlags.anonymous must be bit 5");
}
