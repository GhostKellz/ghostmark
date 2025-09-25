# Build Configuration Guide

GhostMark uses Zig's build system to provide flexible, modular compilation options. This allows you to build only the features you need, reducing binary size and compile times.

## Build Commands

### Default Build
```bash
zig build
```
Builds with all features enabled (except validation which is experimental).

### Help
```bash
zig build --help
```
Shows all available build options and their descriptions.

### Running Tests
```bash
zig build test
```

### Running the Example
```bash
zig build run
```

## Build Flags

### Feature Flags

#### `--enable-html` (default: true)
Enables HTML5 parsing support with HTML-specific handling.

```bash
# Disable HTML parsing
zig build -Denable-html=false

# Enable HTML parsing (default)
zig build -Denable-html=true
```

**Impact:**
- Adds `parseHtml()` function
- HTML void element handling
- Case-insensitive tag matching
- **Binary size:** ~2KB additional

#### `--enable-xpath` (default: true)
Enables XPath query functionality for document traversal.

```bash
# Disable XPath
zig build -Denable-xpath=false
```

**Features:**
- `xpath()` function and `XPathResult` type
- Descendant selectors (`//element`)
- Attribute predicates (`element[@attr='value']`)
- Position predicates (`element[1]`)
- **Binary size:** ~5KB additional

#### `--enable-sax` (default: true)
Enables SAX (streaming) parser for memory-efficient processing.

```bash
# Disable SAX parser
zig build -Denable-sax=false
```

**Features:**
- `parseSax()` function
- Event-driven parsing
- `SaxHandler` callback interface
- **Binary size:** ~3KB additional

#### `--enable-pretty-print` (default: true)
Enables pretty printing with indentation and formatting.

```bash
# Disable pretty printing
zig build -Denable-pretty-print=false
```

**Features:**
- `printWithOptions()` function
- Configurable indentation
- XML declaration control
- **Binary size:** ~1KB additional

#### `--enable-namespaces` (default: true)
Enables XML namespace support throughout the parser.

```bash
# Disable namespace support
zig build -Denable-namespaces=false
```

**Features:**
- Namespace prefix parsing
- Namespace-aware printing
- Reduced memory usage when disabled
- **Binary size:** ~1KB additional

#### `--enable-comments` (default: true)
Enables XML comment parsing and preservation.

```bash
# Disable comment handling
zig build -Denable-comments=false
```

**Features:**
- Comment nodes in DOM
- Comment preservation in SAX
- Reduced parsing overhead when disabled
- **Binary size:** ~0.5KB additional

#### `--enable-validation` (default: false)
**⚠️ EXPERIMENTAL** - Schema validation support (not yet implemented).

```bash
# Enable validation (future feature)
zig build -Denable-validation=true
```

### Special Build Modes

#### `--minimal` (default: false)
Creates a minimal build with only DOM parsing support.

```bash
# Minimal build - DOM parsing only
zig build -Dminimal=true
```

**Features in minimal build:**
- ✅ Basic XML parsing
- ✅ DOM tree construction
- ✅ Element/attribute access
- ❌ All other features disabled

**Binary size:** ~8KB (vs ~20KB full build)

## Build Configurations

### Development Build
```bash
# Full featured development build
zig build -Dtarget=native -Doptimize=Debug
```

### Production Build
```bash
# Optimized production build
zig build -Doptimize=ReleaseFast
```

### Embedded/Minimal Build
```bash
# Minimal size for embedded systems
zig build -Dminimal=true -Doptimize=ReleaseSmall
```

### Web/WASM Build
```bash
# WebAssembly target
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall -Dminimal=true
```

### Server/High Performance
```bash
# Full features, maximum performance
zig build -Doptimize=ReleaseFast -Denable-validation=false
```

### Client/Size Optimized
```bash
# Reduced feature set for size
zig build -Denable-sax=false -Denable-xpath=false -Doptimize=ReleaseSmall
```

## Feature Matrix

| Feature | Default | Binary Impact | Memory Impact | Use Case |
|---------|---------|---------------|---------------|----------|
| HTML parsing | ✅ | +2KB | Low | Web scraping, HTML processing |
| XPath queries | ✅ | +5KB | Medium | Document querying, data extraction |
| SAX parsing | ✅ | +3KB | Very Low | Large documents, streaming |
| Pretty printing | ✅ | +1KB | Low | Human-readable output |
| Namespaces | ✅ | +1KB | Low | XML standards compliance |
| Comments | ✅ | +0.5KB | Low | Comment preservation |
| Validation | ❌ | +10KB* | High* | Schema compliance |

*Estimated - not yet implemented

## Conditional Compilation in Code

When using build flags, you can check them in your code:

```zig
const build_options = @import("build_options");

pub fn processDocument(doc: Document) !void {
    // Always available
    const root = doc.root orelse return;

    // Conditional features
    if (build_options.enable_xpath) {
        var results = try xpath(doc, "//important", allocator);
        defer results.deinit(allocator);
        // Process XPath results...
    }

    if (build_options.enable_sax) {
        // SAX processing code...
    }

    if (build_options.enable_pretty_print) {
        try printWithOptions(doc, writer, .{ .indent = true });
    } else {
        try print(doc, writer);
    }
}
```

## Build Script Integration

For projects using GhostMark as a dependency:

```zig
// In your build.zig
const ghostmark = b.dependency("ghostmark", .{
    .target = target,
    .optimize = optimize,
    // Custom feature configuration
    .enable_html = false,      // Disable HTML if not needed
    .enable_xpath = true,      // Keep XPath
    .minimal = false,          // Full build
});

exe.root_module.addImport("ghostmark", ghostmark.module("ghostmark"));
```

## Performance Considerations

### Binary Size Impact
- **Full build:** ~20KB
- **Minimal build:** ~8KB
- **Most impactful features:** XPath (+5KB), HTML (+2KB), SAX (+3KB)

### Runtime Performance
- **Namespace parsing:** ~5-10% overhead when enabled
- **Comment parsing:** ~2-3% overhead when enabled
- **XPath queries:** O(n) tree traversal per query
- **SAX parsing:** 50-70% less memory usage than DOM

### Recommendation by Use Case

**Web scraping:**
```bash
zig build -Denable-html=true -Denable-xpath=true -Denable-sax=false
```

**Configuration parsing:**
```bash
zig build -Dminimal=true -Doptimize=ReleaseSmall
```

**Data processing pipeline:**
```bash
zig build -Denable-sax=true -Denable-xpath=false -Denable-pretty-print=false
```

**Development/debugging:**
```bash
zig build # (all features enabled)
```