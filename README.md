# Clippy Markdown

A lightweight, extensible Markdown to HTML converter written in Nim.

## Installation

Require [Nim](https://nim-lang.org/) installed on your system.

```bash
nim c -r src/main.nim input.md
```

## Features
- Header support (#, ##, ###)
- Basic formatting (**bold**, *italic*)
- Extensible via plugin system