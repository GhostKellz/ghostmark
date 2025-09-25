// XPath queries example for GhostMark
const std = @import("std");
const ghostmark = @import("ghostmark");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Sample e-commerce XML data
    const xml =
        \\<catalog>
        \\    <category name="Electronics">
        \\        <product id="1" price="299.99" rating="4.5">
        \\            <name>Wireless Headphones</name>
        \\            <brand>TechCorp</brand>
        \\            <features>
        \\                <feature>Noise Cancellation</feature>
        \\                <feature>Bluetooth 5.0</feature>
        \\                <feature>30h Battery</feature>
        \\            </features>
        \\        </product>
        \\        <product id="2" price="149.99" rating="4.2">
        \\            <name>Smart Watch</name>
        \\            <brand>TechCorp</brand>
        \\            <features>
        \\                <feature>Heart Rate Monitor</feature>
        \\                <feature>GPS</feature>
        \\            </features>
        \\        </product>
        \\        <product id="3" price="89.99" rating="3.8">
        \\            <name>Bluetooth Speaker</name>
        \\            <brand>AudioMax</brand>
        \\        </product>
        \\    </category>
        \\    <category name="Books">
        \\        <product id="4" price="24.99" rating="4.7">
        \\            <name>Zig Programming Guide</name>
        \\            <brand>TechBooks</brand>
        \\        </product>
        \\        <product id="5" price="19.99" rating="4.3">
        \\            <name>Systems Programming</name>
        \\            <brand>TechBooks</brand>
        \\        </product>
        \\    </category>
        \\</catalog>
    ;

    std.debug.print("=== XPath Queries Example ===\n\n");

    var doc = try ghostmark.parse(allocator, xml);
    defer doc.deinit();

    // 1. Find all products (descendant selector)
    std.debug.print("🔍 1. All products (//product):\n");
    var all_products = try ghostmark.xpath(doc, "//product", allocator);
    defer all_products.deinit(allocator);

    std.debug.print("   Found {d} products total\n", .{all_products.count()});
    for (0..all_products.count()) |i| {
        if (all_products.get(i)) |product| {
            const name = getTextContent(product, "name") orelse "Unknown";
            const id = product.getAttribute("id") orelse "?";
            std.debug.print("   - Product #{s}: {s}\n", .{ id, name });
        }
    }

    // 2. Find products by attribute (specific brand)
    std.debug.print("\n🔍 2. TechCorp products (//product[brand='TechCorp']):\n");
    var techcorp_products = try ghostmark.xpath(doc, "//product", allocator);
    defer techcorp_products.deinit(allocator);

    var techcorp_count: u32 = 0;
    for (0..techcorp_products.count()) |i| {
        if (techcorp_products.get(i)) |product| {
            const brand = getTextContent(product, "brand") orelse "";
            if (std.mem.eql(u8, brand, "TechCorp")) {
                techcorp_count += 1;
                const name = getTextContent(product, "name") orelse "Unknown";
                std.debug.print("   - {s} by {s}\n", .{ name, brand });
            }
        }
    }
    std.debug.print("   Total TechCorp products: {d}\n", .{techcorp_count});

    // 3. Find products by price range (attribute predicate simulation)
    std.debug.print("\n🔍 3. Premium products (price > $200):\n");
    var premium_products = try ghostmark.xpath(doc, "//product", allocator);
    defer premium_products.deinit(allocator);

    for (0..premium_products.count()) |i| {
        if (premium_products.get(i)) |product| {
            if (product.getAttribute("price")) |price_str| {
                const price = std.fmt.parseFloat(f32, price_str) catch continue;
                if (price > 200.0) {
                    const name = getTextContent(product, "name") orelse "Unknown";
                    std.debug.print("   - {s}: ${s}\n", .{ name, price_str });
                }
            }
        }
    }

    // 4. Find first product in each category (position predicate)
    std.debug.print("\n🔍 4. First product in Electronics (//category[@name='Electronics']/product[1]):\n");
    var categories = try ghostmark.xpath(doc, "//category", allocator);
    defer categories.deinit(allocator);

    for (0..categories.count()) |i| {
        if (categories.get(i)) |category| {
            if (category.getAttribute("name")) |cat_name| {
                var first_product: ?*ghostmark.Element = null;
                for (category.children.items) |child| {
                    if (child == .element and std.mem.eql(u8, child.element.name, "product")) {
                        first_product = child.element;
                        break;
                    }
                }

                if (first_product) |product| {
                    const name = getTextContent(product, "name") orelse "Unknown";
                    const id = product.getAttribute("id") orelse "?";
                    std.debug.print("   - {s} category, first product: {s} (ID: {s})\n", .{ cat_name, name, id });
                }
            }
        }
    }

    // 5. Find all product names (nested element text content)
    std.debug.print("\n🔍 5. All product names (//product/name):\n");
    var product_names = try ghostmark.xpath(doc, "//name", allocator);
    defer product_names.deinit(allocator);

    for (0..product_names.count()) |i| {
        if (product_names.get(i)) |name_elem| {
            for (name_elem.children.items) |child| {
                if (child == .text) {
                    std.debug.print("   - \"{s}\"\n", .{child.text});
                }
            }
        }
    }

    // 6. Find products with features
    std.debug.print("\n🔍 6. Products with features (//product[features]):\n");
    var products_with_features = try ghostmark.xpath(doc, "//product", allocator);
    defer products_with_features.deinit(allocator);

    for (0..products_with_features.count()) |i| {
        if (products_with_features.get(i)) |product| {
            // Check if product has features
            var has_features = false;
            for (product.children.items) |child| {
                if (child == .element and std.mem.eql(u8, child.element.name, "features")) {
                    has_features = true;
                    break;
                }
            }

            if (has_features) {
                const name = getTextContent(product, "name") orelse "Unknown";
                std.debug.print("   - {s} has features:\n", .{name});

                // List features
                for (product.children.items) |child| {
                    if (child == .element and std.mem.eql(u8, child.element.name, "features")) {
                        for (child.element.children.items) |feature_child| {
                            if (feature_child == .element) {
                                const feature_text = getTextContent(feature_child.element, null) orelse "Unknown feature";
                                std.debug.print("     * {s}\n", .{feature_text});
                            }
                        }
                    }
                }
            }
        }
    }

    // 7. Advanced query: High-rated TechCorp products
    std.debug.print("\n🔍 7. High-rated TechCorp products (rating >= 4.0):\n");
    var rated_products = try ghostmark.xpath(doc, "//product", allocator);
    defer rated_products.deinit(allocator);

    for (0..rated_products.count()) |i| {
        if (rated_products.get(i)) |product| {
            const brand = getTextContent(product, "brand") orelse "";
            if (std.mem.eql(u8, brand, "TechCorp")) {
                if (product.getAttribute("rating")) |rating_str| {
                    const rating = std.fmt.parseFloat(f32, rating_str) catch continue;
                    if (rating >= 4.0) {
                        const name = getTextContent(product, "name") orelse "Unknown";
                        const price = product.getAttribute("price") orelse "N/A";
                        std.debug.print("   - {s}: {s}⭐ (${s})\n", .{ name, rating_str, price });
                    }
                }
            }
        }
    }

    std.debug.print("\n✨ XPath queries example completed!\n");
}

// Helper function to get text content from a child element
fn getTextContent(element: *const ghostmark.Element, child_name: ?[]const u8) ?[]const u8 {
    if (child_name == null) {
        // Get direct text content
        for (element.children.items) |child| {
            if (child == .text) return child.text;
        }
        return null;
    }

    // Find named child element and get its text content
    for (element.children.items) |child| {
        if (child == .element and std.mem.eql(u8, child.element.name, child_name.?)) {
            for (child.element.children.items) |text_child| {
                if (text_child == .text) return text_child.text;
            }
        }
    }
    return null;
}