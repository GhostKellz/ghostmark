# GhostMark Documentation

Welcome to the comprehensive documentation for GhostMark - a high-performance XML/HTML processing library for Zig.

## 📚 Documentation Structure

- **[API Reference](api-reference.md)** - Complete API documentation
- **[Build Configuration](build-configuration.md)** - Build flags and compilation options
- **[Getting Started](getting-started.md)** - Quick start guide and examples
- **[Advanced Usage](advanced-usage.md)** - SAX parsing, XPath, and performance optimization
- **[Migration Guide](migration-guide.md)** - Upgrading from MVP to Beta
- **[Performance Guide](performance-guide.md)** - Benchmarks and optimization tips
- **[Examples](examples/)** - Code samples and tutorials

## 🚀 Quick Start

```zig
const ghostmark = @import("ghostmark");
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const xml = "<book><title>Zig Programming</title><author>Ghost</author></book>";

    // Parse XML
    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Query with XPath
    var results = try ghostmark.xpath(doc, "//title", allocator);
    defer results.deinit(allocator);

    // Pretty print
    try ghostmark.print(doc, std.io.getStdOut().writer());
}
```

## 🏗️ Build Options

```bash
# Full featured build (default)
zig build

# Minimal build (DOM parsing only)
zig build -Dminimal=true

# Custom feature selection
zig build -Denable-xpath=false -Denable-sax=false
```

## 🎯 Key Features

### ✅ DOM Parsing
- Full XML/HTML document object model
- Attribute handling with namespace support
- Memory-efficient element traversal

### ✅ SAX Parsing
- Event-driven streaming parser
- Low memory footprint for large documents
- Custom callback handlers

### ✅ XPath Support
- Element selection with predicates
- Attribute-based filtering
- Position-based queries

### ✅ Advanced Features
- CDATA section handling
- XML comments (optional)
- Processing instructions
- Entity reference decoding
- Pretty printing with indentation

### ✅ Build System
- Optional feature compilation
- Zig-style modular builds
- Minimal footprint configurations

## 📖 Version Information

**Current Version**: Beta (v0.2.0)
**Zig Compatibility**: 0.16.0-dev+
**License**: See LICENSE file

## 🤝 Contributing

See the main repository for contributing guidelines and development setup.