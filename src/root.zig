//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

pub const Node = union(enum) {
    element: *Element,
    text: []const u8,
};

pub const Element = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(Node),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Element {
        var elem: Element = undefined;
        elem.allocator = allocator;
        elem.name = try allocator.dupe(u8, name);
        elem.attributes = try std.ArrayList(Attribute).initCapacity(allocator, 0);
        elem.children = try std.ArrayList(Node).initCapacity(allocator, 0);
        return elem;
    }

    pub fn deinit(self: *Element) void {
        self.allocator.free(self.name);
        self.attributes.deinit(self.allocator);
        for (self.children.items) |*child| {
            switch (child.*) {
                .element => |elem| {
                    elem.deinit();
                    self.allocator.destroy(elem);
                },
                .text => |t| self.allocator.free(t),
            }
        }
        self.children.deinit(self.allocator);
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    root: ?*Element,

    pub fn init(allocator: std.mem.Allocator) Document {
        return Document{
            .allocator = allocator,
            .root = null,
        };
    }

    pub fn deinit(self: *Document) void {
        if (self.root) |root| {
            root.deinit();
            self.allocator.destroy(root);
        }
    }
};

pub fn parse(allocator: std.mem.Allocator, xml: []const u8) !Document {
    var doc = Document.init(allocator);
    var pos: usize = 0;
    doc.root = try parseElement(allocator, xml, &pos);
    return doc;
}

fn parseElement(allocator: std.mem.Allocator, input: []const u8, pos: *usize) !*Element {
    // skip whitespace
    while (pos.* < input.len and std.ascii.isWhitespace(input[pos.*])) pos.* += 1;
    if (pos.* >= input.len or input[pos.*] != '<') return error.InvalidXml;
    pos.* += 1;
    // parse tag name
    const start = pos.*;
    while (pos.* < input.len and input[pos.*] != '>' and !std.ascii.isWhitespace(input[pos.*])) pos.* += 1;
    const name = input[start..pos.*];
    var elem = try allocator.create(Element);
    elem.* = try Element.init(allocator, name);
    // assume no attributes, expect >
    if (pos.* >= input.len or input[pos.*] != '>') {
        elem.deinit();
        allocator.destroy(elem);
        return error.InvalidXml;
    }
    pos.* += 1;
    // parse children
    while (true) {
        while (pos.* < input.len and std.ascii.isWhitespace(input[pos.*])) pos.* += 1;
        if (pos.* >= input.len) {
            elem.deinit();
            allocator.destroy(elem);
            return error.InvalidXml;
        }
        if (input[pos.*] == '<') {
            if (pos.* + 1 < input.len and input[pos.* + 1] == '/') {
                // end tag
                pos.* += 2;
                const end_start = pos.*;
                while (pos.* < input.len and input[pos.*] != '>') pos.* += 1;
                const end_name = input[end_start..pos.*];
                if (!std.mem.eql(u8, name, end_name)) {
                    elem.deinit();
                    allocator.destroy(elem);
                    return error.InvalidXml;
                }
                if (pos.* >= input.len or input[pos.*] != '>') {
                    elem.deinit();
                    allocator.destroy(elem);
                    return error.InvalidXml;
                }
                pos.* += 1;
                break;
            } else {
                // child element
                const child = try parseElement(allocator, input, pos);
                try elem.children.append(elem.allocator, .{ .element = child });
            }
        } else {
            // text
            const text_start = pos.*;
            while (pos.* < input.len and input[pos.*] != '<') pos.* += 1;
            const text = input[text_start..pos.*];
            const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
            if (trimmed.len > 0) {
                try elem.children.append(elem.allocator, .{ .text = try elem.allocator.dupe(u8, trimmed) });
            }
        }
    }
    return elem;
}

pub fn print(doc: Document, writer: anytype) !void {
    if (doc.root) |root| {
        try printElement(root, writer);
        try writer.writeAll("\n");
    }
}

fn printElement(elem: *Element, writer: anytype) !void {
    try writer.print("<{s}>", .{elem.name});
    for (elem.children.items) |child| {
        switch (child) {
            .element => |e| try printElement(e, writer),
            .text => |t| try writer.writeAll(t),
        }
    }
    try writer.print("</{s}>", .{elem.name});
}

test "parse simple XML" {
    const allocator = std.testing.allocator;
    const xml = "<root>Hello</root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();
    try std.testing.expect(doc.root != null);
    try std.testing.expect(std.mem.eql(u8, doc.root.?.name, "root"));
    try std.testing.expect(doc.root.?.children.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, doc.root.?.children.items[0].text, "Hello"));
}

test "parse nested XML" {
    const allocator = std.testing.allocator;
    const xml = "<root><child>text</child></root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();
    try std.testing.expect(doc.root != null);
    try std.testing.expect(std.mem.eql(u8, doc.root.?.name, "root"));
    try std.testing.expect(doc.root.?.children.items.len == 1);
    const child = doc.root.?.children.items[0].element;
    try std.testing.expect(std.mem.eql(u8, child.name, "child"));
    try std.testing.expect(child.children.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, child.children.items[0].text, "text"));
}

test "print XML" {
    // TODO: add print test
}
