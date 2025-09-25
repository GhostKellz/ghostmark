# Getting Started with GhostMark

This guide will help you get up and running with GhostMark quickly.

## Installation

### Adding to Your Project

Add GhostMark to your `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .ghostmark = .{
            .url = "https://github.com/ghostkellz/ghostmark/archive/main.tar.gz",
            .hash = "12345...", // Replace with actual hash
        },
    },
}
```

### Updating build.zig

```zig
const ghostmark = b.dependency("ghostmark", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("ghostmark", ghostmark.module("ghostmark"));
```

### Quick Build Test

```bash
zig build
```

## Basic Usage

### 1. Simple XML Parsing

```zig
const std = @import("std");
const ghostmark = @import("ghostmark");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml =
        \\<library>
        \\    <book id="1">
        \\        <title>The Zig Programming Language</title>
        \\        <author>Andrew Kelley</author>
        \\        <year>2024</year>
        \\    </book>
        \\    <book id="2">
        \\        <title>Systems Programming with Zig</title>
        \\        <author>Ghost Developer</author>
        \\        <year>2024</year>
        \\    </book>
        \\</library>
    ;

    // Parse the XML
    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Access the root element
    if (doc.root) |root| {
        std.debug.print("Root element: {s}\n", .{root.name});
        std.debug.print("Number of children: {d}\n", .{root.children.items.len});
    }
}
```

### 2. Working with Attributes

```zig
const std = @import("std");
const ghostmark = @import("ghostmark");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml = "<user id=\"123\" name=\"Alice\" role=\"admin\"/>";

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    if (doc.root) |user| {
        // Get attribute values
        if (user.getAttribute("id")) |id| {
            std.debug.print("User ID: {s}\n", .{id});
        }

        if (user.getAttribute("name")) |name| {
            std.debug.print("User Name: {s}\n", .{name});
        }

        if (user.getAttribute("role")) |role| {
            std.debug.print("User Role: {s}\n", .{role});
        }

        // List all attributes
        std.debug.print("All attributes:\n");
        for (user.attributes.items) |attr| {
            std.debug.print("  {s} = \"{s}\"\n", .{ attr.name, attr.value });
        }
    }
}
```

### 3. Traversing the DOM Tree

```zig
const std = @import("std");
const ghostmark = @import("ghostmark");

fn printElement(element: *const ghostmark.Element, depth: u32) void {
    // Print indentation
    var i: u32 = 0;
    while (i < depth) : (i += 1) {
        std.debug.print("  ");
    }

    // Print element name
    std.debug.print("<{s}", .{element.name});

    // Print attributes
    for (element.attributes.items) |attr| {
        std.debug.print(" {s}=\"{s}\"", .{ attr.name, attr.value });
    }

    if (element.children.items.len == 0) {
        std.debug.print("/>\n");
        return;
    }

    std.debug.print(">\n");

    // Print children
    for (element.children.items) |child| {
        switch (child) {
            .element => |elem| printElement(elem, depth + 1),
            .text => |text| {
                if (std.mem.trim(u8, text, " \t\n\r").len > 0) {
                    var j: u32 = 0;
                    while (j <= depth) : (j += 1) {
                        std.debug.print("  ");
                    }
                    std.debug.print("Text: {s}\n", .{std.mem.trim(u8, text, " \t\n\r")});
                }
            },
            .comment => |comment| {
                var j: u32 = 0;
                while (j <= depth) : (j += 1) {
                    std.debug.print("  ");
                }
                std.debug.print("Comment: {s}\n", .{comment});
            },
            .cdata => |cdata| {
                var j: u32 = 0;
                while (j <= depth) : (j += 1) {
                    std.debug.print("  ");
                }
                std.debug.print("CDATA: {s}\n", .{cdata});
            },
            .processing_instruction => |pi| {
                var j: u32 = 0;
                while (j <= depth) : (j += 1) {
                    std.debug.print("  ");
                }
                std.debug.print("PI: {s} {s}\n", .{ pi.target, pi.data });
            },
        }
    }

    // Print closing tag
    i = 0;
    while (i < depth) : (i += 1) {
        std.debug.print("  ");
    }
    std.debug.print("</{s}>\n", .{element.name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml =
        \\<catalog>
        \\    <!-- Book catalog -->
        \\    <book isbn="978-0123456789">
        \\        <title>Advanced Zig</title>
        \\        <description><![CDATA[A comprehensive guide to <advanced> Zig programming]]></description>
        \\    </book>
        \\    <?process-instruction data="value"?>
        \\</catalog>
    ;

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    if (doc.root) |root| {
        printElement(root, 0);
    }
}
```

## Common Patterns

### Error Handling

```zig
const xml = "<invalid><unclosed>";

const doc = ghostmark.parse(allocator, xml) catch |err| switch (err) {
    error.InvalidXml => {
        std.debug.print("Invalid XML format\n");
        return;
    },
    error.MismatchedTag => {
        std.debug.print("Mismatched XML tags\n");
        return;
    },
    error.OutOfMemory => {
        std.debug.print("Out of memory\n");
        return;
    },
    else => return err,
};
```

### Finding Elements

```zig
fn findElementsByName(element: *const ghostmark.Element, name: []const u8, results: *std.ArrayList(*const ghostmark.Element)) !void {
    if (std.mem.eql(u8, element.name, name)) {
        try results.append(element);
    }

    for (element.children.items) |child| {
        if (child == .element) {
            try findElementsByName(child.element, name, results);
        }
    }
}

pub fn findBooks(doc: ghostmark.Document, allocator: std.mem.Allocator) !void {
    var books = std.ArrayList(*const ghostmark.Element).init(allocator);
    defer books.deinit();

    if (doc.root) |root| {
        try findElementsByName(root, "book", &books);

        std.debug.print("Found {d} books:\n", .{books.items.len});
        for (books.items) |book| {
            if (book.getAttribute("title")) |title| {
                std.debug.print("- {s}\n", .{title});
            }
        }
    }
}
```

### Pretty Printing

```zig
const std = @import("std");
const ghostmark = @import("ghostmark");

pub fn prettyPrintXml(doc: ghostmark.Document) !void {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit(allocator);

    // Note: In current version, use std output directly
    try ghostmark.printWithOptions(doc, std.io.getStdOut().writer(), .{
        .indent = true,
        .indent_size = 4,
        .xml_declaration = true,
    });
}
```

## Next Steps

1. **[Advanced Usage](advanced-usage.md)** - Learn about XPath queries, SAX parsing, and performance optimization
2. **[API Reference](api-reference.md)** - Complete API documentation
3. **[Examples](examples/)** - More comprehensive examples
4. **[Build Configuration](build-configuration.md)** - Customize your build with feature flags

## Common Issues

### Memory Leaks
Always call `deinit()` on your `Document`:
```zig
var doc = try ghostmark.parse(allocator, xml);
defer doc.deinit(); // Essential!
```

### Build Errors
Make sure you're using a compatible Zig version:
```bash
zig version  # Should be 0.16.0-dev or later
```

### Feature Not Available
Some features require build flags:
```bash
# If XPath doesn't work:
zig build -Denable-xpath=true
```