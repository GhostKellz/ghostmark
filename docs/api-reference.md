# GhostMark API Reference

Complete API documentation for GhostMark XML/HTML processing library.

## Core Types

### Document

Main container for XML/HTML documents.

```zig
pub const Document = struct {
    allocator: std.mem.Allocator,
    root: ?*Element,
    processing_instructions: std.ArrayList(ProcessingInstruction),
    xml_declaration: ?ProcessingInstruction,

    pub fn init(allocator: std.mem.Allocator) Document
    pub fn deinit(self: *Document) void
};
```

**Fields:**
- `root` - Root element of the document
- `processing_instructions` - List of processing instructions
- `xml_declaration` - XML declaration if present

### Element

Represents an XML/HTML element with attributes and children.

```zig
pub const Element = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    namespace_prefix: ?[]const u8,
    namespace_uri: ?[]const u8,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(Node),
    self_closing: bool,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Element
    pub fn deinit(self: *Element) void
    pub fn addAttribute(self: *Element, name: []const u8, value: []const u8) !void
    pub fn getAttribute(self: *Element, name: []const u8) ?[]const u8
};
```

**Methods:**
- `addAttribute()` - Add an attribute to the element
- `getAttribute()` - Retrieve attribute value by name

### Attribute

XML/HTML attribute with optional namespace support.

```zig
pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
    namespace_prefix: ?[]const u8,
};
```

### Node

Union type representing element content.

```zig
pub const Node = union(enum) {
    element: *Element,
    text: []const u8,
    comment: []const u8,        // Available with enable_comments
    cdata: []const u8,
    processing_instruction: ProcessingInstruction,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void
};
```

### ProcessingInstruction

XML processing instruction (like `<?xml version="1.0"?>`).

```zig
pub const ProcessingInstruction = struct {
    target: []const u8,
    data: []const u8,
};
```

## Parsing Functions

### parse

Parse XML string into a Document.

```zig
pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!Document
```

**Parameters:**
- `allocator` - Memory allocator
- `input` - XML string to parse

**Returns:** Parsed Document

**Errors:** See [ParseError](#parseerror)

### parseWithMode

Parse with specific mode (XML or HTML).

```zig
pub fn parseWithMode(allocator: std.mem.Allocator, input: []const u8, mode: ParseMode) ParseError!Document
```

**Parameters:**
- `mode` - `.xml` or `.html`

### parseHtml

Parse HTML string (requires `enable_html` build flag).

```zig
pub fn parseHtml(allocator: std.mem.Allocator, input: []const u8) ParseError!Document
```

## SAX Parser (Streaming)

### SaxHandler

Callback structure for SAX parsing events.

```zig
pub const SaxHandler = struct {
    startDocument: ?*const fn (handler: *Self) ParseError!void = null,
    endDocument: ?*const fn (handler: *Self) ParseError!void = null,
    startElement: ?*const fn (handler: *Self, event: StartElementEvent) ParseError!void = null,
    endElement: ?*const fn (handler: *Self, event: EndElementEvent) ParseError!void = null,
    characters: ?*const fn (handler: *Self, text: []const u8) ParseError!void = null,
    comment: ?*const fn (handler: *Self, text: []const u8) ParseError!void = null,
    cdata: ?*const fn (handler: *Self, text: []const u8) ParseError!void = null,
    processingInstruction: ?*const fn (handler: *Self, pi: ProcessingInstruction) ParseError!void = null,
    xmlDeclaration: ?*const fn (handler: *Self, decl: ProcessingInstruction) ParseError!void = null,
};
```

### parseSax

Stream-parse XML with event callbacks.

```zig
pub fn parseSax(allocator: std.mem.Allocator, input: []const u8, handler: *SaxHandler) ParseError!void
```

**Example:**
```zig
var handler = SaxHandler{
    .startElement = myStartElementHandler,
    .characters = myCharactersHandler,
};
try parseSax(allocator, xml_string, &handler);
```

## XPath Support

### XPathResult

Container for XPath query results.

```zig
pub const XPathResult = struct {
    elements: std.ArrayList(*Element),

    pub fn init(allocator: std.mem.Allocator) XPathResult
    pub fn deinit(self: *XPathResult, allocator: std.mem.Allocator) void
    pub fn count(self: *XPathResult) usize
    pub fn get(self: *XPathResult, index: usize) ?*Element
};
```

### xpath

Query document using XPath expressions.

```zig
pub fn xpath(doc: Document, expression: []const u8, allocator: std.mem.Allocator) !XPathResult
```

**Supported XPath Patterns:**
- `//element` - Descendant-or-self selector
- `/element` - Absolute path from root
- `element` - Direct child selector
- `element[n]` - Position predicate (1-based)
- `element[@attr='value']` - Attribute predicate

**Example:**
```zig
var results = try xpath(doc, "//book[@id='123']", allocator);
defer results.deinit(allocator);
```

## Output Functions

### print

Print document to writer with default formatting.

```zig
pub fn print(doc: Document, writer: anytype) !void
```

### printWithOptions

Print with custom formatting options.

```zig
pub fn printWithOptions(doc: Document, writer: anytype, options: PrintOptions) !void
```

### PrintOptions

Formatting configuration for output.

```zig
pub const PrintOptions = struct {
    indent: bool = true,
    indent_size: u32 = 2,
    encoding: []const u8 = "UTF-8",
    xml_declaration: bool = true,
};
```

**Example:**
```zig
try printWithOptions(doc, writer, PrintOptions{
    .indent = true,
    .indent_size = 4,
    .xml_declaration = false,
});
```

## Error Types

### ParseError

All parsing errors returned by the library.

```zig
pub const ParseError = error{
    InvalidXml,
    UnexpectedEndOfInput,
    InvalidEntityReference,
    MismatchedTag,
    InvalidAttribute,
    InvalidNamespace,
    OutOfMemory,
};
```

### Position

Error position tracking (available in parser context).

```zig
pub const Position = struct {
    line: u32,
    column: u32,
};
```

## Build-Time Configuration

The following features can be enabled/disabled at build time:

- `enable_html` - HTML5 parsing support
- `enable_xpath` - XPath query functionality
- `enable_sax` - SAX streaming parser
- `enable_validation` - Schema validation (future)
- `enable_pretty_print` - Pretty printing
- `enable_namespaces` - XML namespace support
- `enable_comments` - Comment preservation
- `minimal` - Minimal DOM-only build

**Conditional Compilation Example:**
```zig
if (build_options.enable_xpath) {
    var results = try xpath(doc, "//element", allocator);
    defer results.deinit(allocator);
}
```

## Memory Management

- Always call `deinit()` on `Document` and `XPathResult`
- The library uses the provided allocator for all allocations
- All string data is owned by the Document after parsing
- SAX parsing requires manual memory management in callbacks

## Thread Safety

GhostMark is **not thread-safe**. Each thread should use its own `Document` instances and allocators.