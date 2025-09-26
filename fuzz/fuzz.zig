const std = @import("std");
const ghostmark = @import("ghostmark");

// Fuzzing Test Setup for GhostMark
// This file provides fuzzing harnesses for testing robustness

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("GhostMark Fuzzing Test Suite\n", .{});
    std.debug.print("============================\n\n", .{});

    try fuzzBasicXML(allocator);
    try fuzzMalformedXML(allocator);
    try fuzzLargeInputs(allocator);
    try fuzzSpecialCharacters(allocator);
}

// Fuzz basic XML parsing with random variations
fn fuzzBasicXML(allocator: std.mem.Allocator) !void {
    std.debug.print("Fuzz Test: Basic XML variations\n", .{});

    const base_templates = [_][]const u8{
        "<root></root>",
        "<root><child/></root>",
        "<root attr=\"value\"><child>text</child></root>",
        "<?xml version=\"1.0\"?><root/>",
        "<root><!-- comment --></root>",
        "<root><![CDATA[data]]></root>",
    };

    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
    const random = rng.random();

    var tests_passed: u32 = 0;
    var tests_total: u32 = 0;

    for (base_templates) |template| {
        for (0..100) |_| {
            // Generate a fuzzed version of the template
            const fuzzed = try fuzzString(allocator, template, random);
            defer allocator.free(fuzzed);

            tests_total += 1;

            // Try to parse the fuzzed XML
            const result = ghostmark.parse(allocator, fuzzed);
            if (result) |doc| {
                var mutable_doc = doc;
                mutable_doc.deinit();
                tests_passed += 1;
            } else |err| {
                // Expected for many fuzzed inputs
                std.mem.doNotOptimizeAway(err);
            }
        }
    }

    std.debug.print("  Passed: {}/{} ({d:.1}%)\n\n", .{ tests_passed, tests_total, @as(f32, @floatFromInt(tests_passed)) * 100.0 / @as(f32, @floatFromInt(tests_total)) });
}

// Fuzz specifically malformed XML to test error handling
fn fuzzMalformedXML(allocator: std.mem.Allocator) !void {
    std.debug.print("Fuzz Test: Malformed XML handling\n", .{});

    const malformed_templates = [_][]const u8{
        "<root><unclosed>",
        "<root></wrong>",
        "<root attr=\"unclosed>",
        "<root attr=unquoted>",
        "<>invalid</>",
        "<root>&invalid;</root>",
        "<root attr=\"val1\" attr=\"val2\"/>", // duplicate attribute
    };

    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp() + 1)));
    const random = rng.random();

    var errors_handled: u32 = 0;
    var tests_total: u32 = 0;

    for (malformed_templates) |template| {
        for (0..50) |_| {
            // Generate a fuzzed version of the malformed template
            const fuzzed = try fuzzString(allocator, template, random);
            defer allocator.free(fuzzed);

            tests_total += 1;

            // All of these should return errors
            const result = ghostmark.parse(allocator, fuzzed);
            if (result) |doc| {
                var mutable_doc = doc;
                mutable_doc.deinit();
                // Unexpected success
            } else |err| {
                errors_handled += 1;
                std.mem.doNotOptimizeAway(err);
            }
        }
    }

    std.debug.print("  Errors handled correctly: {}/{} ({d:.1}%)\n\n", .{ errors_handled, tests_total, @as(f32, @floatFromInt(errors_handled)) * 100.0 / @as(f32, @floatFromInt(tests_total)) });
}

// Fuzz with very large inputs to test memory handling
fn fuzzLargeInputs(allocator: std.mem.Allocator) !void {
    std.debug.print("Fuzz Test: Large input handling\n", .{});

    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp() + 2)));
    const random = rng.random();

    var tests_passed: u32 = 0;
    var tests_total: u32 = 0;

    // Test various large input sizes
    const sizes = [_]usize{ 1024, 4096, 16384, 65536 };

    for (sizes) |size| {
        for (0..10) |_| {
            // Generate large random XML-like input
            const large_input = try generateLargeXML(allocator, size, random);
            defer allocator.free(large_input);

            tests_total += 1;

            // Try to parse (may fail due to malformed content, but shouldn't crash)
            const result = ghostmark.parse(allocator, large_input);
            if (result) |doc| {
                var mutable_doc = doc;
                mutable_doc.deinit();
                tests_passed += 1;
            } else |err| {
                // Expected for many randomly generated inputs
                std.mem.doNotOptimizeAway(err);
                tests_passed += 1; // Count as passed if it doesn't crash
            }
        }
    }

    std.debug.print("  Handled without crash: {}/{} ({d:.1}%)\n\n", .{ tests_passed, tests_total, @as(f32, @floatFromInt(tests_passed)) * 100.0 / @as(f32, @floatFromInt(tests_total)) });
}

// Fuzz with special characters and encoding edge cases
fn fuzzSpecialCharacters(allocator: std.mem.Allocator) !void {
    std.debug.print("Fuzz Test: Special characters and encoding\n", .{});

    const special_chars = [_]u8{ 0, 1, 2, 127, 255, '<', '>', '&', '"', '\'' };
    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp() + 3)));
    const random = rng.random();

    var tests_handled: u32 = 0;
    var tests_total: u32 = 0;

    for (0..200) |_| {
        // Generate XML with random special characters
        const special_xml = try generateSpecialCharXML(allocator, &special_chars, random);
        defer allocator.free(special_xml);

        tests_total += 1;

        // Should handle gracefully (parse or return appropriate error)
        const result = ghostmark.parse(allocator, special_xml);
        if (result) |doc| {
            var mutable_doc = doc;
            mutable_doc.deinit();
            tests_handled += 1;
        } else |err| {
            // Count as handled if it returns a proper error
            std.mem.doNotOptimizeAway(err);
            tests_handled += 1;
        }
    }

    std.debug.print("  Special characters handled: {}/{} ({d:.1}%)\n\n", .{ tests_handled, tests_total, @as(f32, @floatFromInt(tests_handled)) * 100.0 / @as(f32, @floatFromInt(tests_total)) });
}

// Helper function to fuzz a string with random mutations
fn fuzzString(allocator: std.mem.Allocator, input: []const u8, random: std.Random) ![]u8 {
    var result = try allocator.dupe(u8, input);

    // Apply random mutations
    const mutation_count = random.intRangeAtMost(u32, 0, 5);
    for (0..mutation_count) |_| {
        const mutation_type = random.intRangeAtMost(u32, 0, 3);
        switch (mutation_type) {
            0 => {
                // Character substitution
                if (result.len > 0) {
                    const pos = random.intRangeAtMost(usize, 0, result.len - 1);
                    result[pos] = @as(u8, @intCast(random.intRangeAtMost(u32, 32, 126)));
                }
            },
            1 => {
                // Character deletion
                if (result.len > 1) {
                    const pos = random.intRangeAtMost(usize, 0, result.len - 1);
                    std.mem.copyForwards(u8, result[pos..], result[pos + 1..]);
                    result = result[0..result.len - 1];
                }
            },
            2 => {
                // Character insertion (simplified - just duplicate a character)
                if (result.len > 0) {
                    const pos = random.intRangeAtMost(usize, 0, result.len - 1);
                    const new_result = try allocator.alloc(u8, result.len + 1);
                    std.mem.copyForwards(u8, new_result[0..pos], result[0..pos]);
                    new_result[pos] = result[pos];
                    std.mem.copyForwards(u8, new_result[pos + 1..], result[pos..]);
                    allocator.free(result);
                    result = new_result;
                }
            },
            else => {},
        }
    }

    return result;
}

// Generate large XML-like content
fn generateLargeXML(allocator: std.mem.Allocator, size: usize, random: std.Random) ![]u8 {
    var result = try allocator.alloc(u8, size);

    // Start with valid XML structure
    const prefix = "<root>";
    const suffix = "</root>";

    if (size < prefix.len + suffix.len) {
        // Too small, just return minimal XML
        allocator.free(result);
        return try allocator.dupe(u8, "<a/>");
    }

    std.mem.copyForwards(u8, result[0..prefix.len], prefix);
    std.mem.copyForwards(u8, result[size - suffix.len..], suffix);

    // Fill middle with random content
    const middle_start = prefix.len;
    const middle_end = size - suffix.len;

    for (middle_start..middle_end) |i| {
        result[i] = @as(u8, @intCast(random.intRangeAtMost(u32, 32, 126)));
    }

    return result;
}

// Generate XML with special characters
fn generateSpecialCharXML(allocator: std.mem.Allocator, special_chars: []const u8, random: std.Random) ![]u8 {
    const base = "<root attr=\"value\">text</root>";
    var result = try allocator.dupe(u8, base);

    // Insert some special characters randomly
    const insert_count = random.intRangeAtMost(u32, 1, 3);
    for (0..insert_count) |_| {
        if (result.len > 0) {
            const pos = random.intRangeAtMost(usize, 0, result.len - 1);
            const special_char = special_chars[random.intRangeAtMost(usize, 0, special_chars.len - 1)];
            result[pos] = special_char;
        }
    }

    return result;
}