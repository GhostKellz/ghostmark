# GhostMark Examples

This directory contains practical examples demonstrating GhostMark's features.

## Running Examples

### Prerequisites
- Zig 0.16.0-dev or later
- GhostMark library added to your project

### Basic Setup

1. **Create a new Zig project:**
   ```bash
   mkdir ghostmark-examples
   cd ghostmark-examples
   zig init
   ```

2. **Add GhostMark dependency to `build.zig.zon`:**
   ```zig
   .dependencies = .{
       .ghostmark = .{
           .url = "https://github.com/ghostkellz/ghostmark/archive/main.tar.gz",
           .hash = "...", // Use actual hash
       },
   },
   ```

3. **Update `build.zig`:**
   ```zig
   const ghostmark = b.dependency("ghostmark", .{
       .target = target,
       .optimize = optimize,
   });
   exe.root_module.addImport("ghostmark", ghostmark.module("ghostmark"));
   ```

## Available Examples

### 1. Basic Parsing (`basic-parsing.zig`)
**What it demonstrates:**
- Simple XML document parsing
- Accessing elements and attributes
- Handling different node types (text, comments, CDATA, processing instructions)
- Pretty printing with formatting options

**Run with:**
```bash
zig run basic-parsing.zig
```

**Key concepts:**
- `ghostmark.parse()` - Parse XML into DOM
- `doc.root` - Access root element
- `element.attributes` - Access attributes
- `element.children` - Access child nodes
- Node type switching (`.element`, `.text`, `.comment`, `.cdata`, `.processing_instruction`)

### 2. XPath Queries (`xpath-queries.zig`)
**What it demonstrates:**
- XPath query syntax and patterns
- Finding elements by tag name, attributes, and position
- Complex queries with multiple criteria
- Processing query results

**Run with:**
```bash
zig run xpath-queries.zig -Denable-xpath=true
```

**Key concepts:**
- `ghostmark.xpath()` - Execute XPath queries
- `//element` - Descendant selector
- `element[@attr='value']` - Attribute predicates
- `element[1]` - Position predicates
- `XPathResult` - Managing query results

### 3. SAX Streaming (Coming Soon)
**What it will demonstrate:**
- Memory-efficient streaming parsing
- Event-driven processing
- Custom SAX handlers
- Processing large documents

### 4. HTML Processing (Coming Soon)
**What it will demonstrate:**
- HTML5-specific parsing mode
- Handling self-closing tags
- Case-insensitive processing
- Web scraping scenarios

### 5. Performance Optimization (Coming Soon)
**What it will demonstrate:**
- Choosing the right parser type
- Memory allocation strategies
- Build configuration optimization
- Benchmarking techniques

## Example Patterns

### Error Handling Pattern
```zig
const doc = ghostmark.parse(allocator, xml) catch |err| switch (err) {
    error.InvalidXml => {
        std.debug.print("Invalid XML format\n");
        return;
    },
    error.MismatchedTag => {
        std.debug.print("Mismatched XML tags\n");
        return;
    },
    else => return err,
};
```

### Resource Management Pattern
```zig
// Always use defer for cleanup
var doc = try ghostmark.parse(allocator, xml);
defer doc.deinit();

var results = try ghostmark.xpath(doc, "//element", allocator);
defer results.deinit(allocator);
```

### Attribute Processing Pattern
```zig
for (element.attributes.items) |attr| {
    std.debug.print("{s} = \"{s}\"\n", .{ attr.name, attr.value });
}

// Or get specific attribute
if (element.getAttribute("id")) |id| {
    std.debug.print("Element ID: {s}\n", .{id});
}
```

### DOM Traversal Pattern
```zig
fn processElement(element: *const ghostmark.Element, depth: u32) void {
    // Print current element
    printIndent(depth);
    std.debug.print("Element: {s}\n", .{element.name});

    // Process children
    for (element.children.items) |child| {
        switch (child) {
            .element => |elem| processElement(elem, depth + 1),
            .text => |text| {
                printIndent(depth + 1);
                std.debug.print("Text: {s}\n", .{text});
            },
            else => {},
        }
    }
}
```

## Build Configurations

### Full-Featured Build
```bash
zig build # All features enabled by default
```

### Minimal Build
```bash
zig build -Dminimal=true
```

### Custom Feature Selection
```bash
# Only DOM and XPath
zig build -Denable-xpath=true -Denable-sax=false -Denable-html=false

# Only SAX parsing
zig build -Denable-sax=true -Denable-xpath=false -Dminimal=false
```

## Common Use Cases

### 1. Configuration File Processing
```zig
// Small XML config files
const config_xml = loadConfigFile(); // Your function
var doc = try ghostmark.parse(allocator, config_xml);
defer doc.deinit();

// Extract configuration values...
```

### 2. API Response Processing
```zig
// Medium-sized API responses with XPath
var results = try ghostmark.xpath(doc, "//user[@active='true']", allocator);
defer results.deinit(allocator);
```

### 3. Large File Processing
```zig
// Use SAX for large documents
var handler = MyStreamHandler.init();
try ghostmark.parseSax(allocator, large_xml, &handler);
```

### 4. Web Scraping
```zig
// HTML documents
var doc = try ghostmark.parseHtml(allocator, html_content);
defer doc.deinit();

var links = try ghostmark.xpath(doc, "//a[@href]", allocator);
defer links.deinit(allocator);
```

## Performance Tips

1. **Choose the right parser:**
   - DOM for small-medium documents with random access
   - SAX for large documents or streaming

2. **Use appropriate build flags:**
   - Disable unused features for smaller binaries
   - Enable only what you need

3. **Memory management:**
   - Use arena allocators for batch processing
   - Always call `deinit()` on documents and results

4. **Query optimization:**
   - Batch XPath queries when possible
   - Use specific selectors instead of broad searches

## Next Steps

- Read the [API Reference](../api-reference.md) for complete function documentation
- Check [Advanced Usage](../advanced-usage.md) for complex scenarios
- See [Performance Guide](../performance-guide.md) for optimization techniques
- Review [Build Configuration](../build-configuration.md) for feature customization