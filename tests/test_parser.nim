import unittest
import parser

suite "clippy markdown parser":
  test "header":
    let p = newParser()
    check p.parse("# Hello") == "<h1 id='hello'>Hello</h1>"

  test "paragraph":
    let p = newParser()
    check p.parse("Hello world") == "<p>Hello world</p>"

  test "bold and italic":
    let p = newParser()
    check p.parse("This is **bold** and *italic*") == "<p>This is <strong>bold</strong> and <em>italic</em></p>"

  test "inline code escapes html":
    let p = newParser()
    check p.parse("`<b>`") == "<p><code style='background: #f4f4f4; padding: 2px 4px; border-radius: 3px;'>&lt;b&gt;</code></p>"

  test "fenced code block":
    let p = newParser()
    let html = p.parse("```\n<b>\n```")
    check html.contains("<pre><code")
    check html.contains("&lt;b&gt;")

  test "table rows are not wrapped in paragraphs":
    let p = newParser()
    let md = "| a | b |\n| --- | :---: |\n| 1 | 2 |"
    let html = p.parse(md)
    check html.contains("<table")
    check html.contains("text-align: center;")
    check not html.contains("<p>  <tr")

  test "internal link":
    let p = newParser()
    check p.parse("[x](#sec)") == "<p><a href='#sec'>x</a></p>"

  test "escaped characters":
    let p = newParser()
    check p.parse("\\*star\\*") == "<p>*star*</p>"

  test "escaped dollar does not become math":
    let p = newParser()
    check p.parse("\\$5") == "<p>$5</p>"

  test "plugin":
    var p = newParser()
    p.addPlugin(proc(s: string): string = s.replace("TODO:", "DONE:"))
    check p.parse("TODO:") == "<p>DONE:</p>"

  test "separate lists are not merged":
    let p = newParser()
    let html = p.parse("* a\n\n* b")
    check html.contains("<ul\n<li>a</li>\n</ul>")
    check html.contains("<ul\n<li>b</li></ul>")

  test "shorthand reference link":
    let p = newParser()
    let html = p.parse("[x][]\n\n[x]: /url")
    check html.contains("<a href='/url'>x</a>")

  test "html comments are removed":
    let p = newParser()
    check p.parse("Hello <!-- comment --> world") == "<p>Hello  world</p>"
