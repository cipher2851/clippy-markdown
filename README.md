# Clippy Markdown

A lightweight, extensible Markdown to HTML converter written in Nim.

## Installation

Require [Nim](https://nim-lang.org/) installed on your system.

```bash
nim c -r src/main.nim input.md
```

## Usage

Pass a Markdown file as the first argument. The generated HTML document is written to standard output.

```bash
nim c -r src/main.nim input.md > output.html
```

You can also read Markdown from standard input and write HTML to a file:

```bash
nim c -r src/main.nim --output output.html < input.md
nim c -r src/main.nim - < input.md
```

Use `--help` for the full command-line options.

## Features

- Header support (`#` to `######`) with generated IDs
- Basic formatting (`**bold**`, `*italic*`, `~~strikethrough~~`)
- Inline code, fenced code blocks, and indented code blocks
- Links, images, and reference-style links (including titles)
- Tables with alignment markers
- Ordered and unordered lists
- Blockquotes, horizontal rules, footnotes, and task lists
- Inline and display math
- Escaped characters and HTML comments
- Extensible via a simple plugin system

## Plugins

Plugins are procedures that receive the rendered HTML string and return a modified string. See `src/main.nim` for an example that highlights `TODO:` markers.

## Development

Run the parser tests with:

```bash
nim c -r --path:src tests/test_parser.nim
```
