# Advanced Usage Guide

This guide covers advanced features of GhostMark including XPath queries, SAX parsing, and performance optimization techniques.

## XPath Queries

XPath provides a powerful way to query and extract data from XML documents.

### Basic XPath Patterns

```zig
const std = @import("std");
const ghostmark = @import("ghostmark");

pub fn xpathExamples() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml =
        \\<library>
        \\    <book id="1" category="fiction">
        \\        <title>The Great Novel</title>
        \\        <author>Jane Doe</author>
        \\        <price>19.99</price>
        \\    </book>
        \\    <book id="2" category="tech">
        \\        <title>Zig Programming</title>
        \\        <author>John Smith</author>
        \\        <price>29.99</price>
        \\    </book>
        \\    <magazine id="3">
        \\        <title>Tech Weekly</title>
        \\    </magazine>
        \\</library>
    ;

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Find all books (descendant selector)
    var books = try ghostmark.xpath(doc, "//book", allocator);
    defer books.deinit(allocator);
    std.debug.print("Found {d} books\n", .{books.count()});

    // Find books with specific attribute
    var fiction_books = try ghostmark.xpath(doc, "//book[@category='fiction']", allocator);
    defer fiction_books.deinit(allocator);
    std.debug.print("Found {d} fiction books\n", .{fiction_books.count()});

    // Find first book (position predicate)
    var first_book = try ghostmark.xpath(doc, "//book[1]", allocator);
    defer first_book.deinit(allocator);
    if (first_book.get(0)) |book| {
        if (book.getAttribute("id")) |id| {
            std.debug.print("First book ID: {s}\n", .{id});
        }
    }

    // Find all titles
    var titles = try ghostmark.xpath(doc, "//title", allocator);
    defer titles.deinit(allocator);
    for (0..titles.count()) |i| {
        if (titles.get(i)) |title_elem| {
            for (title_elem.children.items) |child| {
                if (child == .text) {
                    std.debug.print("Title: {s}\n", .{child.text});
                }
            }
        }
    }
}
```

### Advanced XPath Queries

```zig
pub fn advancedXPath() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml =
        \\<catalog>
        \\    <product id="1" price="100" category="electronics">
        \\        <name>Laptop</name>
        \\        <specs>
        \\            <cpu>Intel i7</cpu>
        \\            <ram>16GB</ram>
        \\        </specs>
        \\    </product>
        \\    <product id="2" price="50" category="books">
        \\        <name>Programming Guide</name>
        \\    </product>
        \\    <product id="3" price="200" category="electronics">
        \\        <name>Monitor</name>
        \\    </product>
        \\</catalog>
    ;

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Complex attribute queries
    var expensive_electronics = try ghostmark.xpath(doc, "//product[@category='electronics']", allocator);
    defer expensive_electronics.deinit(allocator);

    std.debug.print("Electronics products:\n");
    for (0..expensive_electronics.count()) |i| {
        if (expensive_electronics.get(i)) |product| {
            if (product.getAttribute("price")) |price| {
                std.debug.print("- Product {s}: ${s}\n", .{
                    product.getAttribute("id") orelse "unknown",
                    price
                });
            }
        }
    }
}
```

## SAX (Streaming) Parser

SAX parsing is ideal for large documents or when you need memory-efficient processing.

### Basic SAX Usage

```zig
const std = @import("std");
const ghostmark = @import("ghostmark");

const BookExtractor = struct {
    allocator: std.mem.Allocator,
    books: std.ArrayList(Book),
    current_book: ?Book,
    current_text: ?[]u8,

    const Book = struct {
        title: []const u8,
        author: []const u8,
        id: []const u8,

        pub fn deinit(self: Book, allocator: std.mem.Allocator) void {
            allocator.free(self.title);
            allocator.free(self.author);
            allocator.free(self.id);
        }
    };

    pub fn init(allocator: std.mem.Allocator) BookExtractor {
        return BookExtractor{
            .allocator = allocator,
            .books = std.ArrayList(Book).init(allocator),
            .current_book = null,
            .current_text = null,
        };
    }

    pub fn deinit(self: *BookExtractor) void {
        for (self.books.items) |book| {
            book.deinit(self.allocator);
        }
        self.books.deinit(self.allocator);
        if (self.current_text) |text| {
            self.allocator.free(text);
        }
    }

    pub fn startElement(self: *BookExtractor, event: ghostmark.StartElementEvent) !void {
        if (std.mem.eql(u8, event.name, "book")) {
            // Found a book element, extract ID
            for (event.attributes) |attr| {
                if (std.mem.eql(u8, attr.name, "id")) {
                    self.current_book = Book{
                        .id = try self.allocator.dupe(u8, attr.value),
                        .title = "",
                        .author = "",
                    };
                    break;
                }
            }
        }
    }

    pub fn endElement(self: *BookExtractor, event: ghostmark.EndElementEvent) !void {
        if (std.mem.eql(u8, event.name, "book")) {
            if (self.current_book) |book| {
                try self.books.append(book);
                self.current_book = null;
            }
        } else if (std.mem.eql(u8, event.name, "title")) {
            if (self.current_book) |*book| {
                if (self.current_text) |text| {
                    self.allocator.free(book.title); // Free previous
                    book.title = text;
                    self.current_text = null;
                }
            }
        } else if (std.mem.eql(u8, event.name, "author")) {
            if (self.current_book) |*book| {
                if (self.current_text) |text| {
                    self.allocator.free(book.author); // Free previous
                    book.author = text;
                    self.current_text = null;
                }
            }
        }
    }

    pub fn characters(self: *BookExtractor, text: []const u8) !void {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        if (trimmed.len > 0) {
            if (self.current_text) |old_text| {
                self.allocator.free(old_text);
            }
            self.current_text = try self.allocator.dupe(u8, trimmed);
        }
    }
};

pub fn saxParsingExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml =
        \\<library>
        \\    <book id="1">
        \\        <title>The Zig Guide</title>
        \\        <author>Expert Programmer</author>
        \\    </book>
        \\    <book id="2">
        \\        <title>Systems Programming</title>
        \\        <author>Another Expert</author>
        \\    </book>
        \\</library>
    ;

    var extractor = BookExtractor.init(allocator);
    defer extractor.deinit();

    // Create SAX handler - Note: This is a simplified example
    // In actual code, you'd need proper function pointer setup
    var handler = ghostmark.SaxHandler{};

    // For the example, let's use DOM parsing instead
    // Real SAX implementation requires more complex handler setup
    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    std.debug.print("SAX parsing would process the document element by element\n");
    std.debug.print("without building the full DOM tree in memory.\n");
}
```

### Performance-Optimized SAX

```zig
pub fn largeSaxExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // For very large XML files, SAX parsing uses minimal memory
    const StreamProcessor = struct {
        element_count: u32,
        text_bytes: u64,

        pub fn startElement(self: *@This(), event: ghostmark.StartElementEvent) !void {
            self.element_count += 1;
            _ = event; // Use event data as needed
        }

        pub fn characters(self: *@This(), text: []const u8) !void {
            self.text_bytes += text.len;
        }
    };

    var processor = StreamProcessor{ .element_count = 0, .text_bytes = 0 };

    // Process large document with minimal memory usage
    std.debug.print("SAX parsing allows processing documents of any size\n");
    std.debug.print("with constant memory usage.\n");
}
```

## Namespace Handling

```zig
pub fn namespaceExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml =
        \\<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
        \\               xmlns:web="http://example.com/webservice">
        \\    <soap:Header>
        \\        <web:Authentication>
        \\            <web:Token>abc123</web:Token>
        \\        </web:Authentication>
        \\    </soap:Header>
        \\    <soap:Body>
        \\        <web:GetData>
        \\            <web:Query>SELECT * FROM users</web:Query>
        \\        </web:GetData>
        \\    </soap:Body>
        \\</soap:Envelope>
    ;

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    if (doc.root) |envelope| {
        std.debug.print("Root element: {s}\n", .{envelope.name});
        if (envelope.namespace_prefix) |prefix| {
            std.debug.print("Namespace prefix: {s}\n", .{prefix});
        }

        // Find all elements with 'web' namespace prefix
        var web_elements = try ghostmark.xpath(doc, "//web:*", allocator);
        defer web_elements.deinit(allocator);
        std.debug.print("Found {d} web namespace elements\n", .{web_elements.count()});
    }
}
```

## CDATA and Special Content

```zig
pub fn specialContentExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<document>
        \\    <!-- This is a comment -->
        \\    <code-sample>
        \\        <![CDATA[
        \\            function example() {
        \\                return x < y && y > z;
        \\            }
        \\        ]]>
        \\    </code-sample>
        \\    <html-content>
        \\        <![CDATA[<h1>Title</h1><p>Content with <b>bold</b> text</p>]]>
        \\    </html-content>
        \\    <?process-instruction target="value"?>
        \\</document>
    ;

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Check XML declaration
    if (doc.xml_declaration) |decl| {
        std.debug.print("XML Declaration: {s} {s}\n", .{ decl.target, decl.data });
    }

    // Process different node types
    if (doc.root) |root| {
        for (root.children.items) |child| {
            switch (child) {
                .comment => |comment| {
                    std.debug.print("Comment: {s}\n", .{comment});
                },
                .element => |elem| {
                    std.debug.print("Element: {s}\n", .{elem.name});
                    for (elem.children.items) |elem_child| {
                        if (elem_child == .cdata) {
                            std.debug.print("  CDATA: {s}\n", .{elem_child.cdata});
                        }
                    }
                },
                .processing_instruction => |pi| {
                    std.debug.print("Processing Instruction: {s} = {s}\n", .{ pi.target, pi.data });
                },
                else => {},
            }
        }
    }
}
```

## HTML Processing

```zig
pub fn htmlExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const html =
        \\<html>
        \\    <head>
        \\        <title>Example Page</title>
        \\        <meta charset="utf-8">
        \\        <link rel="stylesheet" href="style.css">
        \\    </head>
        \\    <body>
        \\        <h1>Welcome</h1>
        \\        <p>This is a <strong>sample</strong> HTML page.</p>
        \\        <img src="image.jpg" alt="Sample Image">
        \\        <br>
        \\        <hr>
        \\    </body>
        \\</html>
    ;

    // Use HTML parsing mode for better HTML handling
    var doc = try ghostmark.parseHtml(allocator, html);
    defer doc.deinit();

    // Extract all text content
    var text_nodes = try ghostmark.xpath(doc, "//text()", allocator);
    defer text_nodes.deinit(allocator);

    // Find specific HTML elements
    var links = try ghostmark.xpath(doc, "//link", allocator);
    defer links.deinit(allocator);
    std.debug.print("Found {d} link elements\n", .{links.count()});

    var images = try ghostmark.xpath(doc, "//img", allocator);
    defer images.deinit(allocator);
    for (0..images.count()) |i| {
        if (images.get(i)) |img| {
            if (img.getAttribute("src")) |src| {
                std.debug.print("Image source: {s}\n", .{src});
            }
        }
    }
}
```

## Performance Optimization

### Memory Management

```zig
pub fn memoryOptimization() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // For large documents, consider using an arena allocator
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const large_xml = generateLargeXml(allocator); // Your function
    defer allocator.free(large_xml);

    // Parse with arena - all memory is freed at once
    var doc = try ghostmark.parse(arena_allocator, large_xml);
    // No need to call doc.deinit() - arena handles everything

    // Process document...
    _ = doc;

    // When arena.deinit() is called, all memory is freed at once
}

fn generateLargeXml(allocator: std.mem.Allocator) ![]u8 {
    // Generate or read large XML content
    return try allocator.dupe(u8, "<root><large>content</large></root>");
}
```

### Selective Feature Usage

```zig
pub fn selectiveFeatures() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml = "<data><item>value</item></data>";

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Use features conditionally based on build configuration
    const build_options = @import("build_options");

    if (build_options.enable_xpath) {
        var results = try ghostmark.xpath(doc, "//item", allocator);
        defer results.deinit(allocator);
        // Process XPath results...
    } else {
        // Fall back to manual DOM traversal
        if (doc.root) |root| {
            // Manual search implementation
            _ = root;
        }
    }

    if (build_options.enable_pretty_print) {
        try ghostmark.printWithOptions(doc, std.io.getStdOut().writer(), .{
            .indent = true,
            .indent_size = 2,
        });
    } else {
        try ghostmark.print(doc, std.io.getStdOut().writer());
    }
}
```

## Error Handling and Debugging

```zig
pub fn robustErrorHandling() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const problematic_xml = "<root><unclosed><nested></root>";

    // Comprehensive error handling
    const doc = ghostmark.parse(allocator, problematic_xml) catch |err| switch (err) {
        error.InvalidXml => {
            std.debug.print("Invalid XML structure detected\n");
            return;
        },
        error.MismatchedTag => {
            std.debug.print("XML tags don't match - check for unclosed tags\n");
            return;
        },
        error.UnexpectedEndOfInput => {
            std.debug.print("XML input ended unexpectedly\n");
            return;
        },
        error.InvalidAttribute => {
            std.debug.print("Malformed XML attribute found\n");
            return;
        },
        error.InvalidEntityReference => {
            std.debug.print("Unknown entity reference in XML\n");
            return;
        },
        error.OutOfMemory => {
            std.debug.print("Not enough memory to parse XML\n");
            return;
        },
        else => return err, // Propagate unexpected errors
    };

    _ = doc;
}
```

## Best Practices

### 1. Memory Management
- Always call `deinit()` on documents and XPath results
- Consider arena allocators for temporary processing
- Use SAX parsing for large documents

### 2. Performance
- Disable unused features in build configuration
- Use XPath for complex queries instead of manual DOM traversal
- Batch XPath queries when possible

### 3. Error Handling
- Always handle parsing errors explicitly
- Validate input when possible
- Use appropriate error messages for debugging

### 4. Code Organization
- Separate parsing logic from business logic
- Use structured approaches for data extraction
- Consider creating custom SAX handlers for specific use cases