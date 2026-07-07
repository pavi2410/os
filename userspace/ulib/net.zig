const abi_net = @import("abi_net");
const syscall = @import("syscall.zig");

pub const AF_INET = abi_net.AF_INET;
pub const SOCK_STREAM = abi_net.SOCK_STREAM;
pub const SOCK_DGRAM = abi_net.SOCK_DGRAM;
pub const IPPROTO_ICMP: u32 = @intCast(abi_net.IPPROTO_ICMP);
pub const IPPROTO_TCP: u32 = @intCast(abi_net.IPPROTO_TCP);
pub const IPPROTO_UDP: u32 = @intCast(abi_net.IPPROTO_UDP);

pub const SockaddrIn = abi_net.SockaddrIn;
pub const NetConfig = abi_net.NetConfig;
pub const NeighEntry = abi_net.NeighEntry;

pub fn sockaddrIn(addr: [4]u8, port_host: u16) SockaddrIn {
    return abi_net.sockaddrIn(addr, port_host);
}

pub fn socket(domain: u32, sock_type: u32, protocol: u32) isize {
    return syscall.socket(domain, sock_type, protocol);
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
