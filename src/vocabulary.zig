const std = @import("std");

/// Basic vocabulary module for natural-language VM interaction.
/// This is a placeholder module — the full vocabulary system will be
/// ported from the Python source in a future phase.

pub fn createDefaultVocabulary(allocator: std.mem.Allocator) !std.ArrayList(VocabEntry) {
    var entries = std.ArrayList(VocabEntry).init(allocator);
    try entries.append(.{ .pattern = "compute A + B", .name = "add" });
    try entries.append(.{ .pattern = "compute A * B", .name = "multiply" });
    try entries.append(.{ .pattern = "factorial of N", .name = "factorial" });
    try entries.append(.{ .pattern = "double N", .name = "double" });
    try entries.append(.{ .pattern = "hello", .name = "hello" });
    return entries;
}

pub const VocabEntry = struct {
    pattern: []const u8,
    name: []const u8,
};

test "vocabulary creation" {
    const allocator = std.testing.allocator;
    var vocab = try createDefaultVocabulary(allocator);
    defer vocab.deinit();
    try std.testing.expectEqual(@as(usize, 5), vocab.items.len);
    try std.testing.expectEqualStrings("add", vocab.items[0].name);
}
