# Ghostmark Documentation

## API Reference

### Document

Represents an XML/HTML document.

```zig
pub const Document = struct {
    allocator: std.mem.Allocator,
    root: ?*Element,

    pub fn init(allocator: std.mem.Allocator) Document
    pub fn deinit(self: *Document) void
};
```

### Element

Represents an XML/HTML element.

```zig
pub const Element = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(Node),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Element
    pub fn deinit(self: *Element) void
};
```

### Attribute

Represents an XML/HTML attribute.

```zig
pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};
```

### Node

Union type for element content.

```zig
pub const Node = union(enum) {
    element: *Element,
    text: []const u8,
};
```

## Functions

### parse

Parse XML string into a Document.

```zig
pub fn parse(allocator: std.mem.Allocator, xml: []const u8) !Document
```

**Parameters:**
- `allocator`: Memory allocator
- `xml`: XML string to parse

**Returns:** Parsed Document

**Errors:** `InvalidXml` if parsing fails

### print

Print Document to a writer.

```zig
pub fn print(doc: Document, writer: anytype) !void
```

**Parameters:**
- `doc`: Document to print
- `writer`: Any type that implements `writeAll` and `print`

## Examples

### Basic Parsing

```zig
const std = @import("std");
const ghostmark = @import("ghostmark");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const xml = "<book><title>Zig Programming</title><author>Ghost</author></book>";

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Access root element
    if (doc.root) |root| {
        std.debug.print("Root element: {s}\n", .{root.name});
    }
}
```

### Traversing Elements

```zig
// Assuming doc is parsed
if (doc.root) |root| {
    for (root.children.items) |child| {
        switch (child) {
            .element => |elem| {
                std.debug.print("Child element: {s}\n", .{elem.name});
            },
            .text => |text| {
                std.debug.print("Text content: {s}\n", .{text});
            },
        }
    }
}
```

## Error Handling

The parser returns `error.InvalidXml` for malformed XML. Always handle this error:

```zig
var doc = ghostmark.parse(allocator, xml) catch |err| {
    std.debug.print("Failed to parse XML: {}\n", .{err});
    return err;
};
```

## Memory Management

- Always call `doc.deinit()` to free memory
- The library uses the provided allocator for all allocations
- Elements and text content are owned by the Document