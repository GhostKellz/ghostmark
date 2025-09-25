// Basic XML parsing example for GhostMark
const std = @import("std");
const ghostmark = @import("ghostmark");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Sample XML with various features
    const xml =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<library name="Tech Books" established="2020">
        \\    <!-- This is a comment -->
        \\    <book id="1" category="programming">
        \\        <title>The Zig Programming Language</title>
        \\        <author>Andrew Kelley</author>
        \\        <isbn>978-0123456789</isbn>
        \\        <price currency="USD">29.99</price>
        \\        <description><![CDATA[Learn systems programming with <Zig>]]></description>
        \\    </book>
        \\    <book id="2" category="systems">
        \\        <title>Understanding Compilers</title>
        \\        <author>Jane Smith</author>
        \\        <isbn>978-0987654321</isbn>
        \\        <price currency="USD">39.99</price>
        \\        <topics>
        \\            <topic>Lexical Analysis</topic>
        \\            <topic>Parsing</topic>
        \\            <topic>Code Generation</topic>
        \\        </topics>
        \\    </book>
        \\    <?processing-instruction target="data"?>
        \\</library>
    ;

    std.debug.print("=== Basic XML Parsing Example ===\n\n");

    // Parse the XML document
    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    std.debug.print("✅ XML parsed successfully!\n\n");

    // Access XML declaration
    if (doc.xml_declaration) |decl| {
        std.debug.print("📋 XML Declaration: <?{s} {s}?>\n", .{ decl.target, decl.data });
    }

    // Access root element
    if (doc.root) |root| {
        std.debug.print("📚 Root element: <{s}>\n", .{root.name});

        // Show root attributes
        std.debug.print("📋 Root attributes:\n");
        for (root.attributes.items) |attr| {
            std.debug.print("   {s} = \"{s}\"\n", .{ attr.name, attr.value });
        }

        std.debug.print("\n📖 Books in library:\n");

        // Process each child
        var book_count: u32 = 0;
        for (root.children.items) |child| {
            switch (child) {
                .element => |book| {
                    if (std.mem.eql(u8, book.name, "book")) {
                        book_count += 1;
                        std.debug.print("\n📗 Book #{d}:\n", .{book_count});

                        // Show book attributes
                        for (book.attributes.items) |attr| {
                            std.debug.print("   {s}: {s}\n", .{ attr.name, attr.value });
                        }

                        // Show book details
                        for (book.children.items) |book_child| {
                            switch (book_child) {
                                .element => |detail| {
                                    if (std.mem.eql(u8, detail.name, "topics")) {
                                        std.debug.print("   topics:\n");
                                        for (detail.children.items) |topic_child| {
                                            if (topic_child == .element) {
                                                const topic = topic_child.element;
                                                if (topic.children.items.len > 0 and topic.children.items[0] == .text) {
                                                    std.debug.print("     - {s}\n", .{topic.children.items[0].text});
                                                }
                                            }
                                        }
                                    } else {
                                        // Regular text content
                                        for (detail.children.items) |text_child| {
                                            if (text_child == .text) {
                                                std.debug.print("   {s}: {s}\n", .{ detail.name, text_child.text });
                                            }
                                        }
                                    }
                                },
                                .cdata => |cdata| {
                                    std.debug.print("   CDATA content: {s}\n", .{cdata});
                                },
                                else => {},
                            }
                        }
                    }
                },
                .comment => |comment| {
                    std.debug.print("💭 Comment: {s}\n", .{comment});
                },
                .processing_instruction => |pi| {
                    std.debug.print("⚙️  Processing Instruction: <?{s} {s}?>\n", .{ pi.target, pi.data });
                },
                else => {},
            }
        }

        std.debug.print("\n📊 Total books found: {d}\n", .{book_count});
    }

    std.debug.print("\n=== Pretty Printed Output ===\n");
    try ghostmark.printWithOptions(doc, std.io.getStdOut().writer(), .{
        .indent = true,
        .indent_size = 2,
        .xml_declaration = true,
    });

    std.debug.print("\n\n✨ Example completed successfully!\n");
}