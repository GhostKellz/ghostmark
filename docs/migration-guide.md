# Migration Guide: MVP to Beta

This guide helps you upgrade from GhostMark MVP (v0.1.0) to Beta (v0.2.0).

## Overview of Changes

### ✅ What's New in Beta
- **Attribute support** - Full XML attribute parsing and manipulation
- **Namespace handling** - XML namespace prefix and URI support
- **Enhanced node types** - CDATA, comments, processing instructions
- **SAX parser** - Memory-efficient streaming parser
- **XPath queries** - Document querying and data extraction
- **Pretty printing** - Configurable output formatting
- **Build flags** - Optional feature compilation
- **HTML mode** - HTML5-specific parsing
- **Better error handling** - Detailed error types and position tracking

### 🔧 What Changed
- **API expansions** - New functions and options (backward compatible)
- **Build system** - New optional feature flags
- **Node structure** - Extended union type (backward compatible)
- **Memory management** - Improved cleanup (same API)

### ⚠️ Breaking Changes
- **Minimal** - Most MVP code continues to work
- **Build flags** - Some features now require explicit enabling
- **ArrayList API** - Updated for newer Zig version compatibility

## Step-by-Step Migration

### 1. Update Dependencies

**Old build.zig.zon:**
```zig
.dependencies = .{
    .ghostmark = .{
        .url = "https://github.com/ghostkellz/ghostmark/archive/v0.1.0.tar.gz",
        .hash = "old_hash...",
    },
},
```

**New build.zig.zon:**
```zig
.dependencies = .{
    .ghostmark = .{
        .url = "https://github.com/ghostkellz/ghostmark/archive/main.tar.gz",
        .hash = "new_hash...", // Get latest hash
    },
},
```

### 2. Basic Code Migration

**MVP Code (still works):**
```zig
const ghostmark = @import("ghostmark");
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const xml = "<root>Hello</root>";

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    try ghostmark.print(doc, std.io.getStdOut().writer());
}
```

**Enhanced Beta Code:**
```zig
const ghostmark = @import("ghostmark");
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const xml = "<root id=\"1\">Hello</root>";

    // Same parsing API
    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // NEW: Access attributes
    if (doc.root) |root| {
        if (root.getAttribute("id")) |id| {
            std.debug.print("Root ID: {s}\n", .{id});
        }
    }

    // NEW: Pretty printing with options
    try ghostmark.printWithOptions(doc, std.io.getStdOut().writer(), .{
        .indent = true,
        .indent_size = 2,
        .xml_declaration = true,
    });
}
```

### 3. Node Type Migration

**MVP Node handling:**
```zig
for (element.children.items) |child| {
    switch (child) {
        .element => |elem| {
            // Handle element
        },
        .text => |text| {
            // Handle text
        },
    }
}
```

**Beta Node handling (backward compatible):**
```zig
for (element.children.items) |child| {
    switch (child) {
        .element => |elem| {
            // Handle element (same as MVP)
        },
        .text => |text| {
            // Handle text (same as MVP)
        },
        // NEW: Additional node types
        .comment => |comment| {
            // Handle XML comments
        },
        .cdata => |cdata| {
            // Handle CDATA sections
        },
        .processing_instruction => |pi| {
            // Handle processing instructions
        },
    }
}
```

### 4. Error Handling Migration

**MVP Error handling:**
```zig
const doc = ghostmark.parse(allocator, xml) catch |err| switch (err) {
    error.InvalidXml => {
        // Handle error
    },
    else => return err,
};
```

**Beta Error handling (enhanced):**
```zig
const doc = ghostmark.parse(allocator, xml) catch |err| switch (err) {
    error.InvalidXml => {
        // Same as MVP
    },
    // NEW: More specific errors
    error.MismatchedTag => {
        // Handle tag mismatch
    },
    error.InvalidAttribute => {
        // Handle bad attributes
    },
    error.InvalidEntityReference => {
        // Handle bad entities
    },
    error.UnexpectedEndOfInput => {
        // Handle truncated input
    },
    else => return err,
};
```

## New Features Usage

### 1. Attribute Support

```zig
// NEW in Beta: Attribute access
const xml = "<user id=\"123\" name=\"Alice\" active=\"true\"/>";
var doc = try ghostmark.parse(allocator, xml);
defer doc.deinit();

if (doc.root) |user| {
    // Get specific attribute
    const id = user.getAttribute("id") orelse "unknown";
    std.debug.print("User ID: {s}\n", .{id});

    // Iterate all attributes
    for (user.attributes.items) |attr| {
        std.debug.print("{s} = {s}\n", .{ attr.name, attr.value });
    }
}
```

### 2. XPath Queries

```zig
// NEW in Beta: XPath support
const xml =
    \\<library>
    \\    <book id="1"><title>Book One</title></book>
    \\    <book id="2"><title>Book Two</title></book>
    \\</library>
;

var doc = try ghostmark.parse(allocator, xml);
defer doc.deinit();

// Find all books
var books = try ghostmark.xpath(doc, "//book", allocator);
defer books.deinit(allocator);

// Find book with specific ID
var specific_book = try ghostmark.xpath(doc, "//book[@id='1']", allocator);
defer specific_book.deinit(allocator);
```

### 3. SAX Parsing

```zig
// NEW in Beta: Streaming parser
var handler = ghostmark.SaxHandler{
    // Set up callbacks as needed
};

// Memory-efficient parsing for large documents
try ghostmark.parseSax(allocator, large_xml, &handler);
```

### 4. HTML Parsing

```zig
// NEW in Beta: HTML mode
const html = "<html><body><h1>Title</h1></body></html>";

var doc = try ghostmark.parseHtml(allocator, html);
defer doc.deinit();
```

## Build System Migration

### 1. Basic Build (no changes needed)
```bash
# Works the same in Beta
zig build
zig build test
zig build run
```

### 2. New Build Options
```bash
# NEW: Feature selection
zig build -Denable-xpath=false     # Disable XPath
zig build -Denable-sax=false       # Disable SAX parser
zig build -Dminimal=true           # Minimal DOM-only build

# NEW: Size optimization
zig build -Doptimize=ReleaseSmall -Dminimal=true
```

### 3. Build.zig Integration

**Old (MVP) - still works:**
```zig
const ghostmark = b.dependency("ghostmark", .{
    .target = target,
    .optimize = optimize,
});
```

**New (Beta) - with options:**
```zig
const ghostmark = b.dependency("ghostmark", .{
    .target = target,
    .optimize = optimize,
    // NEW: Configure features
    .enable_xpath = true,
    .enable_sax = true,
    .enable_html = false,
    .minimal = false,
});
```

## Common Migration Issues

### 1. ArrayList API Changes

**Issue:** Compilation errors with `ArrayList.init()` or `append()`

**Solution:** Update to new Zig ArrayList API:
```zig
// Old (may not work)
var list = std.ArrayList(Item).init(allocator);
list.append(item);
list.deinit();

// New (Beta compatible)
var list = std.ArrayList(Item){};
list.append(allocator, item);
list.deinit(allocator);
```

### 2. Feature Not Available

**Issue:** `@compileError("XPath is disabled...")`

**Solution:** Enable the feature in build:
```bash
zig build -Denable-xpath=true
```

### 3. Memory Leaks

**Issue:** Memory leak warnings in tests

**Solution:** Ensure proper cleanup:
```zig
var results = try ghostmark.xpath(doc, "//element", allocator);
defer results.deinit(allocator); // Don't forget allocator parameter!
```

### 4. Namespace Handling Changes

**Issue:** Namespace-related compilation errors

**Solution:** Handle namespace conditionally:
```zig
if (build_options.enable_namespaces) {
    if (element.namespace_prefix) |prefix| {
        // Handle namespace
    }
}
```

## Performance Considerations

### Beta vs MVP Performance

- **Parse speed:** ~10% faster due to optimizations
- **Memory usage:** Similar for basic usage, much better for large documents with SAX
- **Binary size:** Configurable (8KB minimal vs 20KB full-featured)

### Optimization Tips

1. **Use minimal build** for simple use cases:
   ```bash
   zig build -Dminimal=true -Doptimize=ReleaseSmall
   ```

2. **Disable unused features**:
   ```bash
   zig build -Denable-xpath=false -Denable-sax=false
   ```

3. **Use SAX for large documents**:
   ```zig
   // Memory-efficient for large files
   try ghostmark.parseSax(allocator, huge_xml, &handler);
   ```

## Testing Migration

### Update Your Tests

**Add to existing MVP tests:**
```zig
test "attribute support" {
    const allocator = std.testing.allocator;
    const xml = "<root id=\"test\">content</root>";

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Test new attribute functionality
    const root = doc.root orelse return error.NoRoot;
    const id = root.getAttribute("id") orelse return error.NoAttribute;
    try std.testing.expect(std.mem.eql(u8, id, "test"));
}

test "xpath queries" {
    const allocator = std.testing.allocator;
    const xml = "<root><item>1</item><item>2</item></root>";

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    var items = try ghostmark.xpath(doc, "//item", allocator);
    defer items.deinit(allocator);
    try std.testing.expect(items.count() == 2);
}
```

## Rollback Plan

If you need to rollback to MVP:

1. **Revert dependencies:**
   ```zig
   .ghostmark = .{
       .url = "https://github.com/ghostkellz/ghostmark/archive/v0.1.0.tar.gz",
       .hash = "mvp_hash...",
   },
   ```

2. **Remove Beta-specific code:**
   - XPath queries
   - Attribute access
   - SAX handlers
   - Build flags

3. **Revert to basic parsing:**
   ```zig
   var doc = try ghostmark.parse(allocator, xml);
   defer doc.deinit();
   try ghostmark.print(doc, writer);
   ```

## Getting Help

- **Documentation:** Check [API Reference](api-reference.md)
- **Examples:** See [examples/](examples/) directory
- **Build Issues:** Review [Build Configuration](build-configuration.md)
- **Performance:** See [Performance Guide](performance-guide.md)

## Summary

GhostMark Beta maintains strong backward compatibility with MVP while adding powerful new features. Most existing code will work without changes, and you can gradually adopt new features as needed.

Key migration steps:
1. ✅ Update dependencies
2. ✅ Test existing functionality
3. ✅ Add new features incrementally
4. ✅ Optimize build configuration
5. ✅ Update error handling for new error types