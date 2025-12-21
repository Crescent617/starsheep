pub fn Either(L: type, R: type) type {
    return union(enum) {
        L: L,
        R: R,
    };
}
