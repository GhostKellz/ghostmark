const std = @import("std");
const ghostmark = @import("ghostmark");

// Performance Benchmarks vs libxml2
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("GhostMark Performance Benchmarks\n", .{});
    std.debug.print("================================\n\n", .{});

    try benchmarkSimpleXML(allocator);
    try benchmarkComplexXML(allocator);
    try benchmarkLargeXML(allocator);
    try benchmarkXPathQueries(allocator);
}

fn benchmarkSimpleXML(allocator: std.mem.Allocator) !void {
    const xml = "<root><child>text</child></root>";
    const iterations = 10000;

    std.debug.print("Benchmark: Simple XML parsing ({} iterations)\n", .{iterations});

    const start_time = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        var doc = try ghostmark.parse(allocator, xml);
        doc.deinit();
    }
    const end_time = std.time.nanoTimestamp();

    const total_time = end_time - start_time;
    const avg_time = @divTrunc(total_time, iterations);

    std.debug.print("  Total time: {} ns ({} ms)\n", .{ total_time, @divTrunc(total_time, 1_000_000) });
    std.debug.print("  Average per parse: {} ns\n", .{avg_time});
    std.debug.print("  Parses per second: {}\n\n", .{@divTrunc(1_000_000_000, avg_time)});
}

fn benchmarkComplexXML(allocator: std.mem.Allocator) !void {
    const xml =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<catalog xmlns:book="http://example.com/book">
        \\  <!-- Library catalog -->
        \\  <book:book id="1" isbn="978-0123456789">
        \\    <book:title>Advanced XML Processing</book:title>
        \\    <book:author nationality="USA">
        \\      <book:name>John Smith</book:name>
        \\      <book:email>john.smith@example.com</book:email>
        \\    </book:author>
        \\    <book:chapters>
        \\      <book:chapter number="1">
        \\        <book:title>Introduction to XML</book:title>
        \\        <book:content><![CDATA[XML is a markup language.]]></book:content>
        \\      </book:chapter>
        \\    </book:chapters>
        \\  </book:book>
        \\</catalog>
    ;

    const iterations = 1000;

    std.debug.print("Benchmark: Complex XML parsing ({} iterations)\n", .{iterations});

    const start_time = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        var doc = try ghostmark.parse(allocator, xml);
        doc.deinit();
    }
    const end_time = std.time.nanoTimestamp();

    const total_time = end_time - start_time;
    const avg_time = @divTrunc(total_time, iterations);

    std.debug.print("  Total time: {} ns ({} ms)\n", .{ total_time, @divTrunc(total_time, 1_000_000) });
    std.debug.print("  Average per parse: {} ns\n", .{avg_time});
    std.debug.print("  Parses per second: {}\n\n", .{@divTrunc(1_000_000_000, avg_time)});
}

fn benchmarkLargeXML(allocator: std.mem.Allocator) !void {
    // Generate a large XML document
    var xml_buffer = std.ArrayList(u8){};
    defer xml_buffer.deinit(allocator);

    try xml_buffer.appendSlice(allocator, "<root>\n");
    for (0..1000) |i| {
        var temp_buf: [256]u8 = undefined;
        const item_str = try std.fmt.bufPrint(&temp_buf, "  <item id=\"{}\">\n", .{i});
        try xml_buffer.appendSlice(allocator, item_str);

        const name_str = try std.fmt.bufPrint(&temp_buf, "    <name>Item {}</name>\n", .{i});
        try xml_buffer.appendSlice(allocator, name_str);

        const value_str = try std.fmt.bufPrint(&temp_buf, "    <value>{}</value>\n", .{i * 2});
        try xml_buffer.appendSlice(allocator, value_str);

        try xml_buffer.appendSlice(allocator, "    <description>This is a test item with some content.</description>\n");
        try xml_buffer.appendSlice(allocator, "  </item>\n");
    }
    try xml_buffer.appendSlice(allocator, "</root>");

    const iterations = 10;

    std.debug.print("Benchmark: Large XML parsing (1000 elements, {} iterations)\n", .{iterations});

    const start_time = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        var doc = try ghostmark.parse(allocator, xml_buffer.items);
        doc.deinit();
    }
    const end_time = std.time.nanoTimestamp();

    const total_time = end_time - start_time;
    const avg_time = @divTrunc(total_time, iterations);

    std.debug.print("  XML size: {} bytes\n", .{xml_buffer.items.len});
    std.debug.print("  Total time: {} ns ({} ms)\n", .{ total_time, @divTrunc(total_time, 1_000_000) });
    std.debug.print("  Average per parse: {} ns ({} ms)\n", .{ avg_time, @divTrunc(avg_time, 1_000_000) });
    std.debug.print("  MB/s throughput: {d:.2}\n\n", .{@as(f64, @floatFromInt(xml_buffer.items.len)) / (@as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0) / 1_000_000.0});
}

fn benchmarkXPathQueries(allocator: std.mem.Allocator) !void {
    if (!@hasDecl(ghostmark, "xpath")) {
        std.debug.print("XPath benchmarks skipped (XPath not enabled)\n\n");
        return;
    }

    const xml =
        \\<library>
        \\  <books>
        \\    <book category="fiction"><title>Book 1</title></book>
        \\    <book category="non-fiction"><title>Book 2</title></book>
        \\    <book category="fiction"><title>Book 3</title></book>
        \\  </books>
        \\</library>
    ;

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    const queries = [_][]const u8{
        "//book",
        "//book[@category='fiction']",
        "//book[1]",
        "//title",
    };

    const iterations = 1000;

    std.debug.print("Benchmark: XPath queries ({} iterations each)\n", .{iterations});

    for (queries) |query| {
        const start_time = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            var result = try ghostmark.xpath(doc, query, allocator);
            result.deinit(allocator);
        }
        const end_time = std.time.nanoTimestamp();

        const total_time = end_time - start_time;
        const avg_time = @divTrunc(total_time, iterations);

        std.debug.print("  Query '{s}': {} ns avg, {} queries/sec\n", .{ query, avg_time, @divTrunc(1_000_000_000, avg_time) });
    }
    std.debug.print("\n", .{});
}