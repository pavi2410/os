const abi_net = @import("abi_net");
const syscall = @import("syscall.zig");

pub const AddressFamily = abi_net.AddressFamily;
pub const SocketType = abi_net.SocketType;
pub const IpProtocol = abi_net.IpProtocol;

pub const SockaddrIn = abi_net.SockaddrIn;
pub const NetConfig = abi_net.NetConfig;
pub const NeighEntry = abi_net.NeighEntry;

pub fn sockaddrIn(addr: [4]u8, port_host: u16) SockaddrIn {
    return abi_net.sockaddrIn(addr, port_host);
}

pub fn socket(domain: AddressFamily, sock_type: SocketType, protocol: ?IpProtocol) isize {
    const proto: u32 = if (protocol) |p| @intCast(@intFromEnum(p)) else 0;
    return syscall.socket(@intFromEnum(domain), @intFromEnum(sock_type), proto);
}

pub fn bind(fd: u32, addr: *const SockaddrIn) isize {
    return syscall.bind(fd, addr, @sizeOf(SockaddrIn));
}

pub fn connect(fd: u32, addr: *const SockaddrIn) isize {
    return syscall.connect(fd, addr, @sizeOf(SockaddrIn));
}

pub fn send(fd: u32, buf: [*]const u8, len: usize, flags: u32) isize {
    return syscall.send(fd, buf, len, flags);
}

pub fn recv(fd: u32, buf: [*]u8, len: usize, flags: u32) isize {
    return syscall.recv(fd, buf, len, flags);
}

pub fn sendto(fd: u32, buf: [*]const u8, len: usize, flags: u32, dest: *const SockaddrIn) isize {
    return syscall.sendto(fd, buf, len, flags, dest, @sizeOf(SockaddrIn));
}

pub fn recvfrom(fd: u32, buf: [*]u8, len: usize, flags: u32, src: ?*SockaddrIn, addrlen: ?*u32) isize {
    return syscall.recvfrom(fd, buf, len, flags, src, addrlen);
}

pub fn getnetconfig(out: *NetConfig) isize {
    return syscall.getnetconfig(out);
}

pub fn getneighbors(buf: [*]NeighEntry, max: usize) isize {
    return syscall.getneighbors(buf, max);
}
