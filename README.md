# ghostmark

<p align="center">
  <img src="assets/icons/ghostmark.png" width="175" alt="Ghostmark Logo">
</p>

[![Built with Zig](https://img.shields.io/badge/built%20with-Zig-yellow?style=flat&logo=zig)](https://ziglang.org/)
[![Zig](https://img.shields.io/badge/zig-0.16.0--dev-orange?style=flat&logo=zig)](https://ziglang.org/)
[![XML](https://img.shields.io/badge/XML-Parser-blue?style=flat&logo=xml)](https://en.wikipedia.org/wiki/XML)
[![HTML](https://img.shields.io/badge/HTML-Processing-green?style=flat&logo=html5)](https://en.wikipedia.org/wiki/HTML)

## DISCLAIMER

⚠️ **EXPERIMENTAL LIBRARY - FOR LAB/PERSONAL USE** ⚠️

This is an experimental library under active development. It is
intended for research, learning, and personal projects. The API is subject
to change!

A high-performance, standards-compliant XML/HTML processing library written in Zig. Replaces C libraries like libxml2, pugixml, and expat.

## Features

- **DOM Parsing**: Build and manipulate XML/HTML document object models
- **SAX Parsing**: Event-driven parsing for large documents
- **XPath Support**: Query and navigate XML structures
- **Validation**: Schema validation capabilities
- **Pretty Printing**: Format XML/HTML output with proper indentation
- **Standards Compliant**: Full support for XML and HTML specifications

## Installation
Add to your zig project with:
```bash
zig fetch --save https://github.com/ghostkellz/ghostmark/archive/main.tar.gz
```

## Usage

```zig
const ghostmark = @import("ghostmark");

const allocator = std.heap.page_allocator;
const xml = "<book><title>Zig Programming</title></book>";

var doc = try ghostmark.parse(allocator, xml);
defer doc.deinit();

// Print to stdout
try ghostmark.print(doc, std.io.getStdOut().writer());
```

## Building

```bash
zig build
```

## Testing

```bash
zig build test
```

## License

See LICENSE file.
