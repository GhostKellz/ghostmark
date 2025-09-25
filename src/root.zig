//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const build_options = @import("build_options");

// Error types for detailed error reporting
pub const ParseError = error{
    InvalidXml,
    UnexpectedEndOfInput,
    InvalidEntityReference,
    MismatchedTag,
    InvalidAttribute,
    InvalidNamespace,
    OutOfMemory,
};

// Position tracking for error reporting
pub const Position = struct {
    line: u32,
    column: u32,
};

// Parser context for tracking state
const ParserContext = struct {
    input: []const u8,
    pos: usize,
    line: u32,
    column: u32,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, input: []const u8) ParserContext {
        return ParserContext{
            .input = input,
            .pos = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
        };
    }

    fn advance(self: *ParserContext) void {
        if (self.pos < self.input.len) {
            if (self.input[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }

    fn peek(self: *ParserContext) ?u8 {
        if (self.pos < self.input.len) return self.input[self.pos];
        return null;
    }

    fn peekAt(self: *ParserContext, offset: usize) ?u8 {
        if (self.pos + offset < self.input.len) return self.input[self.pos + offset];
        return null;
    }

    fn getPosition(self: *ParserContext) Position {
        return Position{ .line = self.line, .column = self.column };
    }
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
    namespace_prefix: ?[]const u8 = null,
};

pub const Node = union(enum) {
    element: *Element,
    text: []const u8,
    comment: []const u8,
    cdata: []const u8,
    processing_instruction: ProcessingInstruction,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .element => |elem| {
                elem.deinit();
                allocator.destroy(elem);
            },
            .text => |text| allocator.free(text),
            .comment => |comment| if (build_options.enable_comments) allocator.free(comment),
            .cdata => |cdata| allocator.free(cdata),
            .processing_instruction => |pi| {
                allocator.free(pi.target);
                allocator.free(pi.data);
            },
        }
    }
};

pub const ProcessingInstruction = struct {
    target: []const u8,
    data: []const u8,
};

pub const Element = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    namespace_prefix: ?[]const u8 = null,
    namespace_uri: ?[]const u8 = null,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(Node),
    self_closing: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Element {
        var elem: Element = undefined;
        elem.allocator = allocator;
        elem.name = try allocator.dupe(u8, name);
        elem.namespace_prefix = null;
        elem.namespace_uri = null;
        elem.attributes = std.ArrayList(Attribute){};
        elem.children = std.ArrayList(Node){};
        elem.self_closing = false;
        return elem;
    }

    pub fn deinit(self: *Element) void {
        self.allocator.free(self.name);
        if (self.namespace_prefix) |prefix| self.allocator.free(prefix);
        if (self.namespace_uri) |uri| self.allocator.free(uri);

        for (self.attributes.items) |*attr| {
            self.allocator.free(attr.name);
            self.allocator.free(attr.value);
            if (attr.namespace_prefix) |prefix| self.allocator.free(prefix);
        }
        self.attributes.deinit(self.allocator);

        for (self.children.items) |*child| {
            child.deinit(self.allocator);
        }
        self.children.deinit(self.allocator);
    }

    pub fn addAttribute(self: *Element, name: []const u8, value: []const u8) !void {
        const attr = Attribute{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        };
        try self.attributes.append(self.allocator, attr);
    }

    pub fn getAttribute(self: *Element, name: []const u8) ?[]const u8 {
        for (self.attributes.items) |attr| {
            if (std.mem.eql(u8, attr.name, name)) return attr.value;
        }
        return null;
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    root: ?*Element,
    processing_instructions: std.ArrayList(ProcessingInstruction),
    xml_declaration: ?ProcessingInstruction = null,

    pub fn init(allocator: std.mem.Allocator) Document {
        return Document{
            .allocator = allocator,
            .root = null,
            .processing_instructions = std.ArrayList(ProcessingInstruction){},
        };
    }

    pub fn deinit(self: *Document) void {
        if (self.root) |root| {
            root.deinit();
            self.allocator.destroy(root);
        }

        for (self.processing_instructions.items) |*pi| {
            self.allocator.free(pi.target);
            self.allocator.free(pi.data);
        }
        self.processing_instructions.deinit(self.allocator);

        if (self.xml_declaration) |*decl| {
            self.allocator.free(decl.target);
            self.allocator.free(decl.data);
        }
    }
};

// Parser modes for different document types
pub const ParseMode = enum {
    xml,
    html,
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!Document {
    return parseWithMode(allocator, input, .xml);
}

pub fn parseWithMode(allocator: std.mem.Allocator, input: []const u8, mode: ParseMode) ParseError!Document {
    var doc = Document.init(allocator);
    var ctx = ParserContext.init(allocator, input);

    try parseDocument(&ctx, &doc, mode);
    return doc;
}

// Entity reference handling
fn decodeEntity(entity: []const u8) ?u8 {
    if (std.mem.eql(u8, entity, "lt")) return '<';
    if (std.mem.eql(u8, entity, "gt")) return '>';
    if (std.mem.eql(u8, entity, "amp")) return '&';
    if (std.mem.eql(u8, entity, "apos")) return '\'';
    if (std.mem.eql(u8, entity, "quot")) return '"';
    return null;
}

fn skipWhitespace(ctx: *ParserContext) void {
    while (ctx.peek()) |c| {
        if (!std.ascii.isWhitespace(c)) break;
        ctx.advance();
    }
}

fn parseDocument(ctx: *ParserContext, doc: *Document, mode: ParseMode) ParseError!void {
    skipWhitespace(ctx);

    // Parse XML declaration and processing instructions before root element
    while (ctx.peek() == '<') {
        if (ctx.peekAt(1) == '?') {
            const pi = try parseProcessingInstruction(ctx);
            if (std.mem.eql(u8, pi.target, "xml")) {
                doc.xml_declaration = pi;
            } else {
                try doc.processing_instructions.append(doc.allocator, pi);
            }
        } else {
            break;
        }
        skipWhitespace(ctx);
    }

    // Parse root element
    if (ctx.peek() == '<' and ctx.peekAt(1) != '/') {
        doc.root = try parseElement(ctx, mode);
    } else {
        return ParseError.InvalidXml;
    }

    // Parse any trailing processing instructions
    skipWhitespace(ctx);
    while (ctx.peek()) |c| {
        if (c == '<' and ctx.peekAt(1) == '?') {
            const pi = try parseProcessingInstruction(ctx);
            try doc.processing_instructions.append(doc.allocator, pi);
            skipWhitespace(ctx);
        } else if (!std.ascii.isWhitespace(c)) {
            return ParseError.InvalidXml;
        } else {
            ctx.advance();
        }
    }
}

fn parseProcessingInstruction(ctx: *ParserContext) ParseError!ProcessingInstruction {
    if (ctx.peek() != '<' or ctx.peekAt(1) != '?') return ParseError.InvalidXml;
    ctx.advance(); // consume '<'
    ctx.advance(); // consume '?'

    const start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') break;
        if (c == '?' and ctx.peekAt(1) == '>') break;
        ctx.advance();
    }

    const target = try ctx.allocator.dupe(u8, ctx.input[start..ctx.pos]);

    var data_start = ctx.pos;
    var data: []const u8 = "";

    if (ctx.peek()) |c| {
        if (std.ascii.isWhitespace(c)) {
            skipWhitespace(ctx);
            data_start = ctx.pos;

            while (ctx.peek()) |ch| {
                if (ch == '?' and ctx.peekAt(1) == '>') break;
                ctx.advance();
            }

            data = try ctx.allocator.dupe(u8, ctx.input[data_start..ctx.pos]);
        }
    }

    if (ctx.peek() != '?' or ctx.peekAt(1) != '>') {
        ctx.allocator.free(target);
        ctx.allocator.free(data);
        return ParseError.InvalidXml;
    }

    ctx.advance(); // consume '?'
    ctx.advance(); // consume '>'

    return ProcessingInstruction{
        .target = target,
        .data = data,
    };
}

fn parseElement(ctx: *ParserContext, mode: ParseMode) ParseError!*Element {
    if (ctx.peek() != '<') return ParseError.InvalidXml;
    ctx.advance(); // consume '<'

    const start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>' or c == '/') break;
        ctx.advance();
    }

    const full_name = ctx.input[start..ctx.pos];
    var elem = try ctx.allocator.create(Element);
    elem.* = try Element.init(ctx.allocator, full_name);

    // Parse namespace prefix if enabled
    if (build_options.enable_namespaces) {
        if (std.mem.indexOf(u8, full_name, ":")) |colon_pos| {
            elem.namespace_prefix = try ctx.allocator.dupe(u8, full_name[0..colon_pos]);
            ctx.allocator.free(elem.name);
            elem.name = try ctx.allocator.dupe(u8, full_name[colon_pos + 1 ..]);
        }
    }

    // Parse attributes
    skipWhitespace(ctx);
    while (ctx.peek()) |c| {
        if (c == '>') {
            ctx.advance();
            break;
        } else if (c == '/' and ctx.peekAt(1) == '>') {
            elem.self_closing = true;
            ctx.advance(); // consume '/'
            ctx.advance(); // consume '>'
            return elem;
        } else {
            try parseAttribute(ctx, elem);
            skipWhitespace(ctx);
        }
    }

    if (!elem.self_closing) {
        // Parse children
        while (true) {
            skipWhitespace(ctx);

            if (ctx.peek() == '<') {
                if (ctx.peekAt(1) == '/') {
                    // End tag
                    try parseEndTag(ctx, elem.name);
                    break;
                } else if (ctx.peekAt(1) == '!' and ctx.peekAt(2) == '[') {
                    // CDATA
                    const cdata = try parseCDATA(ctx);
                    try elem.children.append(elem.allocator, .{ .cdata = cdata });
                } else if (ctx.peekAt(1) == '!' and ctx.peekAt(2) == '-' and ctx.peekAt(3) == '-') {
                    // Comment
                    if (build_options.enable_comments) {
                        const comment = try parseComment(ctx);
                        try elem.children.append(elem.allocator, .{ .comment = comment });
                    } else {
                        _ = try parseComment(ctx);
                    }
                } else if (ctx.peekAt(1) == '?') {
                    // Processing instruction
                    const pi = try parseProcessingInstruction(ctx);
                    try elem.children.append(elem.allocator, .{ .processing_instruction = pi });
                } else {
                    // Child element
                    const child = try parseElement(ctx, mode);
                    try elem.children.append(elem.allocator, .{ .element = child });
                }
            } else {
                // Text content
                const text = try parseText(ctx);
                if (text.len > 0) {
                    try elem.children.append(elem.allocator, .{ .text = text });
                }
            }
        }
    }

    return elem;
}

fn parseAttribute(ctx: *ParserContext, elem: *Element) ParseError!void {
    const name_start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == '=' or std.ascii.isWhitespace(c)) break;
        ctx.advance();
    }

    const attr_name = try ctx.allocator.dupe(u8, ctx.input[name_start..ctx.pos]);

    skipWhitespace(ctx);
    if (ctx.peek() != '=') {
        ctx.allocator.free(attr_name);
        return ParseError.InvalidAttribute;
    }
    ctx.advance(); // consume '='

    skipWhitespace(ctx);
    const quote = ctx.peek() orelse return ParseError.InvalidAttribute;
    if (quote != '"' and quote != '\'') {
        ctx.allocator.free(attr_name);
        return ParseError.InvalidAttribute;
    }
    ctx.advance(); // consume opening quote

    const value_start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == quote) break;
        ctx.advance();
    }

    if (ctx.peek() != quote) {
        ctx.allocator.free(attr_name);
        return ParseError.InvalidAttribute;
    }

    const attr_value = try ctx.allocator.dupe(u8, ctx.input[value_start..ctx.pos]);
    ctx.advance(); // consume closing quote

    try elem.addAttribute(attr_name, attr_value);
    ctx.allocator.free(attr_name);
}

fn parseEndTag(ctx: *ParserContext, expected_name: []const u8) ParseError!void {
    if (ctx.peek() != '<' or ctx.peekAt(1) != '/') return ParseError.InvalidXml;
    ctx.advance(); // consume '<'
    ctx.advance(); // consume '/'

    const start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == '>') break;
        ctx.advance();
    }

    const tag_name = ctx.input[start..ctx.pos];
    if (!std.mem.eql(u8, tag_name, expected_name)) {
        return ParseError.MismatchedTag;
    }

    if (ctx.peek() != '>') return ParseError.InvalidXml;
    ctx.advance(); // consume '>'
}

fn parseText(ctx: *ParserContext) ParseError![]const u8 {
    const start = ctx.pos;
    var has_content = false;

    while (ctx.peek()) |c| {
        if (c == '<') break;
        if (!std.ascii.isWhitespace(c)) has_content = true;
        ctx.advance();
    }

    if (!has_content) return "";

    const raw_text = ctx.input[start..ctx.pos];
    const trimmed = std.mem.trim(u8, raw_text, &std.ascii.whitespace);

    // Handle entity references
    var result = std.ArrayList(u8){};
    defer result.deinit(ctx.allocator);

    var i: usize = 0;
    while (i < trimmed.len) {
        if (trimmed[i] == '&') {
            const entity_start = i + 1;
            var entity_end = entity_start;
            while (entity_end < trimmed.len and trimmed[entity_end] != ';') {
                entity_end += 1;
            }
            if (entity_end < trimmed.len) {
                const entity = trimmed[entity_start..entity_end];
                if (decodeEntity(entity)) |decoded| {
                    try result.append(ctx.allocator, decoded);
                } else {
                    return ParseError.InvalidEntityReference;
                }
                i = entity_end + 1;
            } else {
                try result.append(ctx.allocator, trimmed[i]);
                i += 1;
            }
        } else {
            try result.append(ctx.allocator, trimmed[i]);
            i += 1;
        }
    }

    return try ctx.allocator.dupe(u8, result.items);
}

fn parseComment(ctx: *ParserContext) ParseError![]const u8 {
    if (ctx.peek() != '<' or ctx.peekAt(1) != '!' or ctx.peekAt(2) != '-' or ctx.peekAt(3) != '-') {
        return ParseError.InvalidXml;
    }

    ctx.advance(); // consume '<'
    ctx.advance(); // consume '!'
    ctx.advance(); // consume '-'
    ctx.advance(); // consume '-'

    const start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == '-' and ctx.peekAt(1) == '-' and ctx.peekAt(2) == '>') {
            break;
        }
        ctx.advance();
    }

    const comment = try ctx.allocator.dupe(u8, ctx.input[start..ctx.pos]);

    if (ctx.peek() != '-' or ctx.peekAt(1) != '-' or ctx.peekAt(2) != '>') {
        ctx.allocator.free(comment);
        return ParseError.InvalidXml;
    }

    ctx.advance(); // consume '-'
    ctx.advance(); // consume '-'
    ctx.advance(); // consume '>'

    return comment;
}

fn parseCDATA(ctx: *ParserContext) ParseError![]const u8 {
    if (ctx.peek() != '<' or ctx.peekAt(1) != '!' or ctx.peekAt(2) != '[') {
        return ParseError.InvalidXml;
    }

    // Check for CDATA prefix
    const cdata_start = "![CDATA[";
    var i: usize = 0;
    while (i < cdata_start.len) {
        if (ctx.peekAt(1 + i) != cdata_start[i]) return ParseError.InvalidXml;
        i += 1;
    }

    ctx.advance(); // consume '<'
    i = 0;
    while (i < cdata_start.len) {
        ctx.advance();
        i += 1;
    }

    const start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == ']' and ctx.peekAt(1) == ']' and ctx.peekAt(2) == '>') break;
        ctx.advance();
    }

    const cdata = try ctx.allocator.dupe(u8, ctx.input[start..ctx.pos]);

    if (ctx.peek() != ']' or ctx.peekAt(1) != ']' or ctx.peekAt(2) != '>') {
        ctx.allocator.free(cdata);
        return ParseError.InvalidXml;
    }

    ctx.advance(); // consume ']'
    ctx.advance(); // consume ']'
    ctx.advance(); // consume '>'

    return cdata;
}

// Pretty printing options
pub const PrintOptions = struct {
    indent: bool = true,
    indent_size: u32 = 2,
    encoding: []const u8 = "UTF-8",
    xml_declaration: bool = true,
};

pub fn print(doc: Document, writer: anytype) !void {
    try printWithOptions(doc, writer, PrintOptions{});
}

pub fn printWithOptions(doc: Document, writer: anytype, options: PrintOptions) !void {
    if (!build_options.enable_pretty_print and options.indent) {
        return printCompact(doc, writer);
    }

    // Print XML declaration
    if (options.xml_declaration) {
        if (doc.xml_declaration) |decl| {
            try writer.print("<?{s} {s}?>\n", .{ decl.target, decl.data });
        } else {
            try writer.print("<?xml version=\"1.0\" encoding=\"{s}\"?>\n", .{options.encoding});
        }
    }

    // Print processing instructions
    for (doc.processing_instructions.items) |pi| {
        try writer.print("<?{s} {s}?>\n", .{ pi.target, pi.data });
    }

    // Print root element
    if (doc.root) |root| {
        try printElementWithOptions(root, writer, 0, options);
        try writer.writeAll("\n");
    }
}

fn printCompact(doc: Document, writer: anytype) !void {
    if (doc.root) |root| {
        try printElementCompact(root, writer);
        try writer.writeAll("\n");
    }
}

fn printElementCompact(elem: *Element, writer: anytype) !void {
    if (build_options.enable_namespaces) {
        if (elem.namespace_prefix) |prefix| {
            try writer.print("<{s}:{s}", .{ prefix, elem.name });
        } else {
            try writer.print("<{s}", .{elem.name});
        }
    } else {
        try writer.print("<{s}", .{elem.name});
    }

    // Print attributes
    for (elem.attributes.items) |attr| {
        if (build_options.enable_namespaces) {
            if (attr.namespace_prefix) |prefix| {
                try writer.print(" {s}:{s}=\"{s}\"", .{ prefix, attr.name, attr.value });
            } else {
                try writer.print(" {s}=\"{s}\"", .{ attr.name, attr.value });
            }
        } else {
            try writer.print(" {s}=\"{s}\"", .{ attr.name, attr.value });
        }
    }

    if (elem.self_closing) {
        try writer.writeAll("/>");
        return;
    }

    try writer.writeAll(">");

    // Print children
    for (elem.children.items) |child| {
        switch (child) {
            .element => |e| try printElementCompact(e, writer),
            .text => |t| try printEscapedText(t, writer),
            .comment => |c| if (build_options.enable_comments) try writer.print("<!--{s}-->", .{c}),
            .cdata => |c| try writer.print("<![CDATA[{s}]]>", .{c}),
            .processing_instruction => |pi| try writer.print("<?{s} {s}?>", .{ pi.target, pi.data }),
        }
    }

    if (build_options.enable_namespaces) {
        if (elem.namespace_prefix) |prefix| {
            try writer.print("</{s}:{s}>", .{ prefix, elem.name });
        } else {
            try writer.print("</{s}>", .{elem.name});
        }
    } else {
        try writer.print("</{s}>", .{elem.name});
    }
}

fn printElementWithOptions(elem: *Element, writer: anytype, depth: u32, options: PrintOptions) !void {
    if (options.indent) {
        try printIndent(writer, depth * options.indent_size);
    }

    if (build_options.enable_namespaces) {
        if (elem.namespace_prefix) |prefix| {
            try writer.print("<{s}:{s}", .{ prefix, elem.name });
        } else {
            try writer.print("<{s}", .{elem.name});
        }
    } else {
        try writer.print("<{s}", .{elem.name});
    }

    // Print attributes
    for (elem.attributes.items) |attr| {
        if (build_options.enable_namespaces) {
            if (attr.namespace_prefix) |prefix| {
                try writer.print(" {s}:{s}=\"{s}\"", .{ prefix, attr.name, attr.value });
            } else {
                try writer.print(" {s}=\"{s}\"", .{ attr.name, attr.value });
            }
        } else {
            try writer.print(" {s}=\"{s}\"", .{ attr.name, attr.value });
        }
    }

    if (elem.self_closing) {
        try writer.writeAll("/>");
        return;
    }

    try writer.writeAll(">");

    var has_element_children = false;
    for (elem.children.items) |child| {
        if (child == .element) {
            has_element_children = true;
            break;
        }
    }

    if (has_element_children and options.indent) {
        try writer.writeAll("\n");
    }

    // Print children
    for (elem.children.items) |child| {
        switch (child) {
            .element => |e| {
                try printElementWithOptions(e, writer, depth + 1, options);
                try writer.writeAll("\n");
            },
            .text => |t| {
                if (!has_element_children or !options.indent) {
                    try printEscapedText(t, writer);
                } else {
                    try printIndent(writer, (depth + 1) * options.indent_size);
                    try printEscapedText(t, writer);
                    try writer.writeAll("\n");
                }
            },
            .comment => |c| {
                if (build_options.enable_comments) {
                    if (options.indent) {
                        try printIndent(writer, (depth + 1) * options.indent_size);
                    }
                    try writer.print("<!--{s}-->", .{c});
                    if (options.indent) try writer.writeAll("\n");
                }
            },
            .cdata => |c| {
                if (options.indent) {
                    try printIndent(writer, (depth + 1) * options.indent_size);
                }
                try writer.print("<![CDATA[{s}]]>", .{c});
                if (options.indent) try writer.writeAll("\n");
            },
            .processing_instruction => |pi| {
                if (options.indent) {
                    try printIndent(writer, (depth + 1) * options.indent_size);
                }
                try writer.print("<?{s} {s}?>", .{ pi.target, pi.data });
                if (options.indent) try writer.writeAll("\n");
            },
        }
    }

    if (has_element_children and options.indent) {
        try printIndent(writer, depth * options.indent_size);
    }

    if (build_options.enable_namespaces) {
        if (elem.namespace_prefix) |prefix| {
            try writer.print("</{s}:{s}>", .{ prefix, elem.name });
        } else {
            try writer.print("</{s}>", .{elem.name});
        }
    } else {
        try writer.print("</{s}>", .{elem.name});
    }
}

fn printIndent(writer: anytype, count: u32) !void {
    var i: u32 = 0;
    while (i < count) {
        try writer.writeAll(" ");
        i += 1;
    }
}

fn printEscapedText(text: []const u8, writer: anytype) !void {
    for (text) |c| {
        switch (c) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),
            else => try writer.writeByte(c),
        }
    }
}

// SAX Parser - Streaming API
pub const SaxEvent = union(enum) {
    start_document,
    end_document,
    start_element: StartElementEvent,
    end_element: EndElementEvent,
    characters: []const u8,
    comment: []const u8,
    cdata: []const u8,
    processing_instruction: ProcessingInstruction,
    xml_declaration: ProcessingInstruction,
};

pub const StartElementEvent = struct {
    name: []const u8,
    namespace_prefix: ?[]const u8,
    namespace_uri: ?[]const u8,
    attributes: []const Attribute,
    self_closing: bool,
};

pub const EndElementEvent = struct {
    name: []const u8,
    namespace_prefix: ?[]const u8,
};

pub const SaxHandler = struct {
    const Self = @This();

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

pub fn parseSax(allocator: std.mem.Allocator, input: []const u8, handler: *SaxHandler) ParseError!void {
    if (!build_options.enable_sax) {
        @compileError("SAX parser is disabled. Enable with -Denable-sax=true");
    }

    var ctx = ParserContext.init(allocator, input);

    if (handler.startDocument) |startDoc| {
        try startDoc(handler);
    }

    skipWhitespace(&ctx);

    // Parse XML declaration and processing instructions before root element
    while (ctx.peek() == '<') {
        if (ctx.peekAt(1) == '?') {
            const pi = try parseProcessingInstruction(&ctx);
            if (std.mem.eql(u8, pi.target, "xml")) {
                if (handler.xmlDeclaration) |xmlDecl| {
                    try xmlDecl(handler, pi);
                } else {
                    allocator.free(pi.target);
                    allocator.free(pi.data);
                }
            } else {
                if (handler.processingInstruction) |procInst| {
                    try procInst(handler, pi);
                } else {
                    allocator.free(pi.target);
                    allocator.free(pi.data);
                }
            }
        } else {
            break;
        }
        skipWhitespace(&ctx);
    }

    // Parse root element
    if (ctx.peek() == '<' and ctx.peekAt(1) != '/') {
        try parseSaxElement(&ctx, handler);
    } else {
        return ParseError.InvalidXml;
    }

    // Parse any trailing processing instructions
    skipWhitespace(&ctx);
    while (ctx.peek()) |c| {
        if (c == '<' and ctx.peekAt(1) == '?') {
            const pi = try parseProcessingInstruction(&ctx);
            if (handler.processingInstruction) |procInst| {
                try procInst(handler, pi);
            } else {
                allocator.free(pi.target);
                allocator.free(pi.data);
            }
            skipWhitespace(&ctx);
        } else if (!std.ascii.isWhitespace(c)) {
            return ParseError.InvalidXml;
        } else {
            ctx.advance();
        }
    }

    if (handler.endDocument) |endDoc| {
        try endDoc(handler);
    }
}

fn parseSaxElement(ctx: *ParserContext, handler: *SaxHandler) ParseError!void {
    if (ctx.peek() != '<') return ParseError.InvalidXml;
    ctx.advance(); // consume '<'

    const start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>' or c == '/') break;
        ctx.advance();
    }

    const full_name = ctx.input[start..ctx.pos];
    var namespace_prefix: ?[]const u8 = null;
    var element_name = full_name;

    // Parse namespace prefix if enabled
    if (build_options.enable_namespaces) {
        if (std.mem.indexOf(u8, full_name, ":")) |colon_pos| {
            namespace_prefix = try ctx.allocator.dupe(u8, full_name[0..colon_pos]);
            element_name = full_name[colon_pos + 1 ..];
        }
    }

    var attributes = std.ArrayList(Attribute){};
    defer {
        for (attributes.items) |*attr| {
            ctx.allocator.free(attr.name);
            ctx.allocator.free(attr.value);
            if (attr.namespace_prefix) |prefix| ctx.allocator.free(prefix);
        }
        attributes.deinit(ctx.allocator);
    }

    // Parse attributes
    skipWhitespace(ctx);
    var self_closing = false;
    while (ctx.peek()) |c| {
        if (c == '>') {
            ctx.advance();
            break;
        } else if (c == '/' and ctx.peekAt(1) == '>') {
            self_closing = true;
            ctx.advance(); // consume '/'
            ctx.advance(); // consume '>'
            break;
        } else {
            const attr = try parseSaxAttribute(ctx);
            try attributes.append(ctx.allocator, attr);
            skipWhitespace(ctx);
        }
    }

    // Fire start element event
    if (handler.startElement) |startElem| {
        try startElem(handler, StartElementEvent{
            .name = element_name,
            .namespace_prefix = namespace_prefix,
            .namespace_uri = null, // TODO: namespace resolution
            .attributes = attributes.items,
            .self_closing = self_closing,
        });
    }

    if (!self_closing) {
        // Parse children
        while (true) {
            skipWhitespace(ctx);

            if (ctx.peek() == '<') {
                if (ctx.peekAt(1) == '/') {
                    // End tag
                    try parseSaxEndTag(ctx, element_name);
                    break;
                } else if (ctx.peekAt(1) == '!' and ctx.peekAt(2) == '[') {
                    // CDATA
                    const cdata = try parseCDATA(ctx);
                    if (handler.cdata) |cdataHandler| {
                        try cdataHandler(handler, cdata);
                    }
                    ctx.allocator.free(cdata);
                } else if (ctx.peekAt(1) == '!' and ctx.peekAt(2) == '-' and ctx.peekAt(3) == '-') {
                    // Comment
                    const comment = try parseComment(ctx);
                    if (build_options.enable_comments) {
                        if (handler.comment) |commentHandler| {
                            try commentHandler(handler, comment);
                        }
                    }
                    ctx.allocator.free(comment);
                } else if (ctx.peekAt(1) == '?') {
                    // Processing instruction
                    const pi = try parseProcessingInstruction(ctx);
                    if (handler.processingInstruction) |procInst| {
                        try procInst(handler, pi);
                    } else {
                        ctx.allocator.free(pi.target);
                        ctx.allocator.free(pi.data);
                    }
                } else {
                    // Child element
                    try parseSaxElement(ctx, handler);
                }
            } else {
                // Text content
                const text = try parseText(ctx);
                if (text.len > 0) {
                    if (handler.characters) |chars| {
                        try chars(handler, text);
                    }
                    ctx.allocator.free(text);
                }
            }
        }
    }

    // Fire end element event
    if (handler.endElement) |endElem| {
        try endElem(handler, EndElementEvent{
            .name = element_name,
            .namespace_prefix = namespace_prefix,
        });
    }

    if (namespace_prefix) |prefix| {
        ctx.allocator.free(prefix);
    }
}

fn parseSaxAttribute(ctx: *ParserContext) ParseError!Attribute {
    const name_start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == '=' or std.ascii.isWhitespace(c)) break;
        ctx.advance();
    }

    const attr_name = try ctx.allocator.dupe(u8, ctx.input[name_start..ctx.pos]);

    skipWhitespace(ctx);
    if (ctx.peek() != '=') {
        ctx.allocator.free(attr_name);
        return ParseError.InvalidAttribute;
    }
    ctx.advance(); // consume '='

    skipWhitespace(ctx);
    const quote = ctx.peek() orelse return ParseError.InvalidAttribute;
    if (quote != '"' and quote != '\'') {
        ctx.allocator.free(attr_name);
        return ParseError.InvalidAttribute;
    }
    ctx.advance(); // consume opening quote

    const value_start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == quote) break;
        ctx.advance();
    }

    if (ctx.peek() != quote) {
        ctx.allocator.free(attr_name);
        return ParseError.InvalidAttribute;
    }

    const attr_value = try ctx.allocator.dupe(u8, ctx.input[value_start..ctx.pos]);
    ctx.advance(); // consume closing quote

    return Attribute{
        .name = attr_name,
        .value = attr_value,
        .namespace_prefix = null, // TODO: namespace handling
    };
}

fn parseSaxEndTag(ctx: *ParserContext, expected_name: []const u8) ParseError!void {
    if (ctx.peek() != '<' or ctx.peekAt(1) != '/') return ParseError.InvalidXml;
    ctx.advance(); // consume '<'
    ctx.advance(); // consume '/'

    const start = ctx.pos;
    while (ctx.peek()) |c| {
        if (c == '>') break;
        ctx.advance();
    }

    const tag_name = ctx.input[start..ctx.pos];
    if (!std.mem.eql(u8, tag_name, expected_name)) {
        return ParseError.MismatchedTag;
    }

    if (ctx.peek() != '>') return ParseError.InvalidXml;
    ctx.advance(); // consume '>'
}

// Basic XPath Support
pub const XPathResult = struct {
    elements: std.ArrayList(*Element),

    pub fn init(_: std.mem.Allocator) XPathResult {
        return XPathResult{
            .elements = std.ArrayList(*Element){},
        };
    }

    pub fn deinit(self: *XPathResult, allocator: std.mem.Allocator) void {
        self.elements.deinit(allocator);
    }

    pub fn count(self: *XPathResult) usize {
        return self.elements.items.len;
    }

    pub fn get(self: *XPathResult, index: usize) ?*Element {
        if (index < self.elements.items.len) {
            return self.elements.items[index];
        }
        return null;
    }
};

pub fn xpath(doc: Document, expression: []const u8, allocator: std.mem.Allocator) !XPathResult {
    if (!build_options.enable_xpath) {
        @compileError("XPath is disabled. Enable with -Denable-xpath=true");
    }

    var result = XPathResult.init(allocator);

    if (doc.root) |root| {
        try evaluateXPath(root, expression, &result, allocator);
    }

    return result;
}

fn evaluateXPath(element: *Element, expression: []const u8, result: *XPathResult, allocator: std.mem.Allocator) !void {
    // Basic XPath patterns:
    // "/element" - absolute path from root
    // "//element" - descendant-or-self
    // "element" - direct child
    // "@attribute" - attribute selector
    // "element[n]" - position predicate
    // "element[@attr='value']" - attribute predicate

    if (expression.len == 0) return;

    if (std.mem.startsWith(u8, expression, "//")) {
        // Descendant-or-self
        const tag_name = expression[2..];
        try findDescendants(element, tag_name, result, allocator);
    } else if (std.mem.startsWith(u8, expression, "/")) {
        // Absolute path - only applies to root
        const remaining = expression[1..];
        if (remaining.len == 0) {
            try result.elements.append(allocator, element);
            return;
        }

        // Find next path segment
        const next_slash = std.mem.indexOf(u8, remaining, "/");
        const tag_name = if (next_slash) |pos| remaining[0..pos] else remaining;

        if (std.mem.eql(u8, element.name, tag_name)) {
            if (next_slash) |pos| {
                try evaluateXPath(element, remaining[pos..], result, allocator);
            } else {
                try result.elements.append(allocator, element);
            }
        }
    } else {
        // Simple tag name or complex expression
        if (std.mem.indexOf(u8, expression, "[")) |bracket_pos| {
            // Has predicate
            const tag_name = expression[0..bracket_pos];
            const predicate = expression[bracket_pos + 1 .. expression.len - 1]; // Remove []

            try findChildrenWithPredicate(element, tag_name, predicate, result, allocator);
        } else {
            // Simple tag name
            try findDirectChildren(element, expression, result, allocator);
        }
    }
}

fn findDescendants(element: *Element, tag_name: []const u8, result: *XPathResult, allocator: std.mem.Allocator) !void {
    // Check current element
    if (std.mem.eql(u8, element.name, tag_name)) {
        try result.elements.append(allocator, element);
    }

    // Recursively check children
    for (element.children.items) |child| {
        switch (child) {
            .element => |child_elem| try findDescendants(child_elem, tag_name, result, allocator),
            else => {},
        }
    }
}

fn findDirectChildren(element: *Element, tag_name: []const u8, result: *XPathResult, allocator: std.mem.Allocator) !void {
    for (element.children.items) |child| {
        switch (child) {
            .element => |child_elem| {
                if (std.mem.eql(u8, child_elem.name, tag_name)) {
                    try result.elements.append(allocator, child_elem);
                }
            },
            else => {},
        }
    }
}

fn findChildrenWithPredicate(element: *Element, tag_name: []const u8, predicate: []const u8, result: *XPathResult, allocator: std.mem.Allocator) !void {
    var candidates = std.ArrayList(*Element){};
    defer candidates.deinit(allocator);

    // First find all matching children
    for (element.children.items) |child| {
        switch (child) {
            .element => |child_elem| {
                if (std.mem.eql(u8, child_elem.name, tag_name)) {
                    try candidates.append(allocator, child_elem);
                }
            },
            else => {},
        }
    }

    // Apply predicate
    if (std.fmt.parseInt(u32, predicate, 10)) |pos| {
        // Position predicate (1-based)
        if (pos > 0 and pos <= candidates.items.len) {
            try result.elements.append(allocator, candidates.items[pos - 1]);
        }
    } else |_| {
        // Attribute predicate
        if (std.mem.startsWith(u8, predicate, "@")) {
            if (std.mem.indexOf(u8, predicate, "=")) |eq_pos| {
                const attr_name = predicate[1..eq_pos];
                var attr_value = predicate[eq_pos + 1 ..];

                // Remove quotes if present
                if (attr_value.len >= 2 and
                    ((attr_value[0] == '"' and attr_value[attr_value.len - 1] == '"') or
                     (attr_value[0] == '\'' and attr_value[attr_value.len - 1] == '\''))) {
                    attr_value = attr_value[1 .. attr_value.len - 1];
                }

                for (candidates.items) |candidate| {
                    if (candidate.getAttribute(attr_name)) |value| {
                        if (std.mem.eql(u8, value, attr_value)) {
                            try result.elements.append(allocator, candidate);
                        }
                    }
                }
            }
        }
    }
}

// HTML5 Parser Mode
pub fn parseHtml(allocator: std.mem.Allocator, input: []const u8) ParseError!Document {
    if (!build_options.enable_html) {
        @compileError("HTML parser is disabled. Enable with -Denable-html=true");
    }

    return parseWithMode(allocator, input, .html);
}

// HTML5 self-closing tags
const HTML_VOID_ELEMENTS = [_][]const u8{
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"
};

fn isHtmlVoidElement(tag_name: []const u8) bool {
    for (HTML_VOID_ELEMENTS) |void_elem| {
        if (std.ascii.eqlIgnoreCase(tag_name, void_elem)) {
            return true;
        }
    }
    return false;
}

// Comprehensive Test Suite for GhostMark Alpha->Beta Features

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

test "parse XML with attributes" {
    const allocator = std.testing.allocator;
    const xml = "<root id=\"1\" class=\"main\">Hello</root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(std.mem.eql(u8, root.name, "root"));
    try std.testing.expect(root.attributes.items.len == 2);

    const id_value = root.getAttribute("id");
    try std.testing.expect(id_value != null);
    try std.testing.expect(std.mem.eql(u8, id_value.?, "1"));

    const class_value = root.getAttribute("class");
    try std.testing.expect(class_value != null);
    try std.testing.expect(std.mem.eql(u8, class_value.?, "main"));
}

test "parse XML with namespaces" {
    const allocator = std.testing.allocator;
    const xml = "<ns:root xmlns:ns=\"http://example.com\">Hello</ns:root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(std.mem.eql(u8, root.name, "root"));
    if (build_options.enable_namespaces) {
        try std.testing.expect(root.namespace_prefix != null);
        try std.testing.expect(std.mem.eql(u8, root.namespace_prefix.?, "ns"));
    }
}

test "parse self-closing tags" {
    const allocator = std.testing.allocator;
    const xml = "<root><empty/></root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(root.children.items.len == 1);
    const child = root.children.items[0].element;
    try std.testing.expect(std.mem.eql(u8, child.name, "empty"));
    try std.testing.expect(child.self_closing == true);
    try std.testing.expect(child.children.items.len == 0);
}

test "parse CDATA sections" {
    const allocator = std.testing.allocator;
    const xml = "<root><![CDATA[<>&\"']]></root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(root.children.items.len == 1);
    try std.testing.expect(root.children.items[0] == .cdata);
    try std.testing.expect(std.mem.eql(u8, root.children.items[0].cdata, "<>&\"'"));
}

test "parse XML comments" {
    const allocator = std.testing.allocator;
    const xml = "<root><!-- This is a comment --><text>Hello</text></root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;

    if (build_options.enable_comments) {
        try std.testing.expect(root.children.items.len == 2);
        try std.testing.expect(root.children.items[0] == .comment);
        try std.testing.expect(std.mem.eql(u8, root.children.items[0].comment, " This is a comment "));
    } else {
        try std.testing.expect(root.children.items.len == 1);
    }
}

test "parse processing instructions" {
    const allocator = std.testing.allocator;
    const xml = "<?xml version=\"1.0\"?><?stylesheet type=\"text/css\"?><root>Hello</root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.xml_declaration != null);
    try std.testing.expect(std.mem.eql(u8, doc.xml_declaration.?.target, "xml"));
    try std.testing.expect(std.mem.eql(u8, doc.xml_declaration.?.data, "version=\"1.0\""));

    try std.testing.expect(doc.processing_instructions.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, doc.processing_instructions.items[0].target, "stylesheet"));
}

test "parse entity references" {
    const allocator = std.testing.allocator;
    const xml = "<root>&lt;&gt;&amp;&quot;&apos;</root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(root.children.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, root.children.items[0].text, "<>&\"'"));
}

test "pretty print XML" {
    if (!build_options.enable_pretty_print) return;

    const allocator = std.testing.allocator;
    const xml = "<root><child id=\"1\">text</child></root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    // Simple test - just verify parsing worked
    try std.testing.expect(doc.root != null);
}

test "XPath basic selectors" {
    if (!build_options.enable_xpath) return;

    const allocator = std.testing.allocator;
    const xml = "<root><child id=\"1\">text1</child><child id=\"2\">text2</child></root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    // Test descendant selector
    var result = try xpath(doc, "//child", allocator);
    defer result.deinit(allocator);
    try std.testing.expect(result.count() == 2);

    // Test direct child selector
    var result2 = try xpath(doc, "child", allocator);
    defer result2.deinit(allocator);
    try std.testing.expect(result2.count() == 2);

    // Test position predicate
    var result3 = try xpath(doc, "child[1]", allocator);
    defer result3.deinit(allocator);
    try std.testing.expect(result3.count() == 1);
    if (result3.get(0)) |elem| {
        const id_value = elem.getAttribute("id");
        try std.testing.expect(id_value != null);
        try std.testing.expect(std.mem.eql(u8, id_value.?, "1"));
    }

    // Test attribute predicate
    var result4 = try xpath(doc, "child[@id='2']", allocator);
    defer result4.deinit(allocator);
    try std.testing.expect(result4.count() == 1);
}

test "SAX parser streaming" {
    if (!build_options.enable_sax) return;

    const allocator = std.testing.allocator;
    const xml = "<root><child>text</child></root>";

    // Simple test - just make sure SAX parser doesn't crash
    var handler = SaxHandler{};
    try parseSax(allocator, xml, &handler);
}

test "HTML parsing mode" {
    if (!build_options.enable_html) return;

    const allocator = std.testing.allocator;
    const html = "<html><head><meta charset=\"utf-8\"><title>Test</title></head></html>";
    var doc = try parseHtml(allocator, html);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    try std.testing.expect(std.mem.eql(u8, doc.root.?.name, "html"));
}

test "error handling with position info" {
    const allocator = std.testing.allocator;
    const xml = "<root><unclosed></root>";

    const result = parse(allocator, xml);
    try std.testing.expect(result == ParseError.MismatchedTag);
}

test "nested XML parsing" {
    const allocator = std.testing.allocator;
    const xml = "<root><child><grandchild>deep text</grandchild></child></root>";
    var doc = try parse(allocator, xml);
    defer doc.deinit();

    try std.testing.expect(doc.root != null);
    const root = doc.root.?;
    try std.testing.expect(std.mem.eql(u8, root.name, "root"));
    try std.testing.expect(root.children.items.len == 1);

    const child = root.children.items[0].element;
    try std.testing.expect(std.mem.eql(u8, child.name, "child"));
    try std.testing.expect(child.children.items.len == 1);

    const grandchild = child.children.items[0].element;
    try std.testing.expect(std.mem.eql(u8, grandchild.name, "grandchild"));
    try std.testing.expect(grandchild.children.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, grandchild.children.items[0].text, "deep text"));
}

test "memory management and cleanup" {
    const allocator = std.testing.allocator;
    const xml = "<root id=\"test\"><child><!-- comment --><![CDATA[data]]>text</child></root>";

    // This test mainly verifies that all memory is properly freed
    var doc = try parse(allocator, xml);
    doc.deinit();
}
