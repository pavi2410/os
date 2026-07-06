pub fn slot(size: u16, idx: u16) usize {
    return @intCast(idx % size);
}

pub fn advance(idx: u16) u16 {
    var next = idx;
    next +%= 1;
    return next;
}

pub fn hasUsed(used_idx: u16, last_used_idx: u16) bool {
    return used_idx != last_used_idx;
}
