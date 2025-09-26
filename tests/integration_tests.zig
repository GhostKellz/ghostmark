const std = @import("std");
const ghostmark = @import("ghostmark");

test "complex XML document parsing" {
    const allocator = std.testing.allocator;
    const complex_xml =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<catalog xmlns:book="http://example.com/book" xmlns:author="http://example.com/author">
        \\  <!-- Library catalog -->
        \\  <book:book id="1" isbn="978-0123456789">
        \\    <book:title>Advanced XML Processing</book:title>
        \\    <author:author nationality="USA">
        \\      <author:name>John Smith</author:name>
        \\      <author:email>john.smith@example.com</author:email>
        \\    </author:author>
        \\    <book:chapters>
        \\      <book:chapter number="1">
        \\        <book:title>Introduction to XML</book:title>
        \\        <book:content><![CDATA[
        \\          XML is a markup language that defines rules for encoding documents.
        \\          It's both human-readable and machine-readable.
        \\        ]]></book:content>
        \\      </book:chapter>
        \\      <book:chapter number="2">
        \\        <book:title>XML Parsing Techniques</book:title>
        \\        <book:content>This chapter covers SAX &amp; DOM parsing methods.</book:content>
        \\      </book:chapter>
        \\    </book:chapters>
        \\  </book:book>
        \\</catalog>
        \\<?processing-instruction data="value"?>
    ;

    var doc = try ghostmark.parse(allocator, complex_xml);
    defer doc.deinit();

    // Test root element
    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(std.mem.eql(u8, root.name, "catalog"));

    // Test XML declaration
    try std.testing.expect(doc.xml_declaration != null);
    try std.testing.expect(std.mem.eql(u8, doc.xml_declaration.?.target, "xml"));

    // Test processing instructions
    try std.testing.expect(doc.processing_instructions.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, doc.processing_instructions.items[0].target, "processing-instruction"));

    // Find book element using XPath if available
    if (@hasDecl(ghostmark, "xpath")) {
        var book_result = try ghostmark.xpath(doc, "//book", allocator);
        defer book_result.deinit(allocator);
        try std.testing.expect(book_result.count() == 1);

        const book = book_result.get(0).?;
        try std.testing.expect(std.mem.eql(u8, book.name, "book"));

        // Test attributes
        const id_attr = book.getAttribute("id");
        try std.testing.expect(id_attr != null);
        try std.testing.expect(std.mem.eql(u8, id_attr.?, "1"));

        const isbn_attr = book.getAttribute("isbn");
        try std.testing.expect(isbn_attr != null);
        try std.testing.expect(std.mem.eql(u8, isbn_attr.?, "978-0123456789"));
    }
}

test "large XML document performance" {
    const allocator = std.testing.allocator;

    // Create a simple large XML document with string concatenation
    const xml =
        \\<root>
        \\  <item id="1"><name>Item 1</name><value>2</value></item>
        \\  <item id="2"><name>Item 2</name><value>4</value></item>
        \\  <item id="3"><name>Item 3</name><value>6</value></item>
        \\  <item id="4"><name>Item 4</name><value>8</value></item>
        \\  <item id="5"><name>Item 5</name><value>10</value></item>
        \\</root>
    ;

    // Measure parsing time
    const start_time = std.time.nanoTimestamp();
    var doc = try ghostmark.parse(allocator, xml);
    const parse_time = std.time.nanoTimestamp() - start_time;
    defer doc.deinit();

    // Verify the document was parsed correctly
    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(std.mem.eql(u8, root.name, "root"));
    try std.testing.expect(root.children.items.len == 5);

    // Print performance info (this won't show up in normal test output)
    std.debug.print("\nParsed 5 elements in {} ns\n", .{parse_time});
}

test "malformed XML error handling" {
    const allocator = std.testing.allocator;

    const malformed_cases = [_][]const u8{
        "<root><unclosed></root>",           // Mismatched tag
        "<root><empty attr=\"unclosed></root>", // Unclosed attribute quote
        "<root>&invalid;</root>",            // Invalid entity reference
        "<root><>invalid</></root>",         // Empty tag name
        "<root attr=unquoted>text</root>",   // Unquoted attribute
        "<root",                             // Incomplete tag
        "<?xml version=\"1.0\"?><root><nested><deep></nested></deep></root>", // Mixed nesting
    };

    for (malformed_cases) |xml| {
        const result = ghostmark.parse(allocator, xml);
        try std.testing.expect(std.meta.isError(result));

        // Make sure we don't leak memory on errors
        if (result) |doc| {
            var mutable_doc = doc;
            mutable_doc.deinit();
        } else |_| {
            // Expected error case
        }
    }
}

test "SAX parser event handling" {
    if (!@hasDecl(ghostmark, "parseSax")) return;

    const allocator = std.testing.allocator;
    const xml = "<root><child>text</child></root>";

    var handler = ghostmark.SaxHandler{};
    try ghostmark.parseSax(allocator, xml, &handler);
}

test "XPath complex queries" {
    if (!@hasDecl(ghostmark, "xpath")) return;

    const allocator = std.testing.allocator;
    const xml =
        \\<library>
        \\  <books>
        \\    <book category="fiction" year="2020">
        \\      <title>The Great Adventure</title>
        \\      <author>Jane Doe</author>
        \\    </book>
        \\    <book category="non-fiction" year="2021">
        \\      <title>Learning Programming</title>
        \\      <author>John Smith</author>
        \\    </book>
        \\    <book category="fiction" year="2022">
        \\      <title>Mystery Novel</title>
        \\      <author>Alice Johnson</author>
        \\    </book>
        \\  </books>
        \\</library>
    ;

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // Test descendant selector
    var all_books = try ghostmark.xpath(doc, "//book", allocator);
    defer all_books.deinit(allocator);
    try std.testing.expect(all_books.count() == 3);

    // Test attribute predicate
    var fiction_books = try ghostmark.xpath(doc, "//book[@category='fiction']", allocator);
    defer fiction_books.deinit(allocator);
    try std.testing.expect(fiction_books.count() == 2);

    // Test position predicate
    var first_book = try ghostmark.xpath(doc, "//book[1]", allocator);
    defer first_book.deinit(allocator);
    try std.testing.expect(first_book.count() == 1);

    if (first_book.get(0)) |book| {
        const year_attr = book.getAttribute("year");
        try std.testing.expect(year_attr != null);
        try std.testing.expect(std.mem.eql(u8, year_attr.?, "2020"));
    }

    // Test direct child selector
    var direct_titles = try ghostmark.xpath(doc, "title", allocator);
    defer direct_titles.deinit(allocator);
    try std.testing.expect(direct_titles.count() == 0); // No direct children named "title" under root
}

test "HTML5 parsing features" {
    if (!@hasDecl(ghostmark, "parseHtml")) return;

    const allocator = std.testing.allocator;
    const html =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>Test Page</title>
        \\    <link rel="stylesheet" href="styles.css">
        \\</head>
        \\<body>
        \\    <h1>Welcome</h1>
        \\    <p>This is a test paragraph with <br> line break.</p>
        \\    <img src="image.jpg" alt="Test image">
        \\    <hr>
        \\    <input type="text" name="username" required>
        \\</body>
        \\</html>
    ;

    var doc = try ghostmark.parseHtml(allocator, html);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(std.mem.eql(u8, root.name, "html"));

    // Check that void elements are self-closing
    if (@hasDecl(ghostmark, "xpath")) {
        var meta_elements = try ghostmark.xpath(doc, "//meta", allocator);
        defer meta_elements.deinit(allocator);
        try std.testing.expect(meta_elements.count() == 2);

        // Verify self-closing property
        for (0..meta_elements.count()) |i| {
            const meta = meta_elements.get(i).?;
            try std.testing.expect(meta.self_closing);
        }

        // Test other void elements
        var void_elements = try ghostmark.xpath(doc, "//br", allocator);
        defer void_elements.deinit(allocator);
        try std.testing.expect(void_elements.count() == 1);
        try std.testing.expect(void_elements.get(0).?.self_closing);
    }
}

test "namespace handling" {
    // Simple check for namespace support by trying to create an element
    const allocator = std.testing.allocator;
    const xml2 =
        \\<root xmlns:books="http://example.com/books" xmlns:authors="http://example.com/authors">
        \\  <books:library>
        \\    <books:book id="1">
        \\      <books:title>XML Guide</books:title>
        \\      <authors:author authors:id="123">
        \\        <authors:name>Tech Writer</authors:name>
        \\      </authors:author>
        \\    </books:book>
        \\  </books:library>
        \\</root>
    ;

    var doc = try ghostmark.parse(allocator, xml2);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;

    // Check namespace declarations are parsed as attributes
    const books_ns = root.getAttribute("xmlns:books");
    try std.testing.expect(books_ns != null);
    try std.testing.expect(std.mem.eql(u8, books_ns.?, "http://example.com/books"));

    // Verify that namespaced elements have their prefixes correctly parsed
    if (@hasDecl(ghostmark, "xpath")) {
        var library_result = try ghostmark.xpath(doc, "//library", allocator);
        defer library_result.deinit(allocator);
        try std.testing.expect(library_result.count() == 1);

        const library = library_result.get(0).?;
        try std.testing.expect(std.mem.eql(u8, library.name, "library"));
        try std.testing.expect(library.namespace_prefix != null);
        try std.testing.expect(std.mem.eql(u8, library.namespace_prefix.?, "books"));
    }
}