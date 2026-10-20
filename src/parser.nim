import strutils, re, tables

type
  MarkdownParser* = object
    plugins: seq[proc(s: string): string]

proc newParser*(): MarkdownParser =
  return MarkdownParser(plugins: @[])

proc addPlugin*(p: var MarkdownParser, plugin: proc(s: string): string) =
  p.plugins.add(plugin)

proc escapeHtml*(s: string): string =
  result = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")

proc slugify(s: string): string =
  # Basic slugification for header IDs
  result = s.toLowerAscii()
  result = result.replaceRe(re"[^a-z0-9\s-]", "")
  result = result.replaceRe(re"\s+", "-")
  result = result.strip(chars = {'-': true})

proc isBlockTag(trimmed: string): bool =
  if not trimmed.startsWith("<"):
    return false

  var i = 1
  if trimmed.len > 2 and trimmed[1] == '/':
    i = 2

  var j = i
  while j < trimmed.len and (trimmed[j] in {'a'..'z', 'A'..'Z', '0'..'9'}):
    inc j

  if j == i:
    return false

  let name = toLowerAscii(trimmed[i..<j])
  case name
  of "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol", "table", "thead", "tbody", "tfoot", "tr", "th", "td", "pre", "hr", "div", "p", "section", "article", "header", "footer", "li", "canvas", "svg", "iframe":
    return true
  else:
    return false

proc parseImpl(p: MarkdownParser, text: string): string =
  var result = text

  # HTML Comments (input has already been HTML-escaped)
  result = result.replaceRe(re"&lt;!--.*?--&gt;", "", reDotAll)

  # Fenced Code Blocks (with an optional info string)
  result = result.replaceRe(re"```[^\n]*\n(.*?)```", proc(m: RegexMatch): string =
    return "<pre><code style='white-space: pre-wrap;'>" & m[1] & "</code></pre>"
  , reDotAll)
  result = result.replaceRe(re"```(.*?)```", proc(m: RegexMatch): string =
    return "<pre><code style='white-space: pre-wrap;'>" & m[1] & "</code></pre>"
  , reDotAll)

  # Indented Code Blocks
  result = result.replaceRe(re"((?:^\s{4}.*\n?)+)", proc(m: RegexMatch): string =
    var content = m[0]
    var lines = content.splitLines()
    var processedLines: seq[string] = @[]
    for line in lines:
      if line.startsWith("    "):
        processedLines.add(line[4..^1])
      elif line.startsWith("\t"):
        processedLines.add(line[1..^1])
      else:
        processedLines.add(line)
    return "<pre><code style='white-space: pre-wrap;'>" & processedLines.join("\n") & "</code></pre>"
  , reMultiline)

  # Basic block parsing
  # Horizontal Rules (Thematic Breaks) - Support spaces between markers
  result = result.replaceRe(re"^\s*([-*_])(\s*\1){2,}\s*$", "<hr />", reMultiline)

  # Tables
  let tablePattern = re"((?:^\s*\|[^\n]*\|\s*\n(?:^\s*\|[- :|]*\s*\|\s*\n)(?:^\s*\|[^\n]*\|\s*\n)*))"
  result = result.replaceRe(tablePattern, proc(m: RegexMatch): string =
    var tableContent = m[0]
    var lines = tableContent.splitLines()
    var htmlTable = "<table style='border-collapse: collapse; width: 100%; margin: 1em 0;'>\n"

    var alignments: seq[string] = @[]

    for i, line in lines:
      if line.strip() == "": continue

      # Handle separator line to determine alignment
      if i == 1 and line.contains("---"):
        var cells = line.split('|')
        if cells.len > 0 and cells[0] == "": cells.delete(0)
        if cells.len > 0 and cells[^1] == "": cells.delete(cells.len - 1)

        for cell in cells:
          let trimmed = cell.strip()
          if trimmed.startsWith(":") and trimmed.endsWith(":"):
            alignments.add("center")
          elif trimmed.endsWith(":"):
            alignments.add("right")
          else:
            alignments.add("left")
        continue

      let tag = if i == 0: "th" else: "td"
      var cells = line.split('|')
      if cells.len > 0 and cells[0] == "": cells.delete(0)
      if cells.len > 0 and cells[^1] == "": cells.delete(cells.len - 1)

      var rowHtml = "  <tr style='border-bottom: 1px solid #ddd;'>"
      for idx, cell in cells:
        let trimmed = cell.strip()
        var style = "padding: 8px; border: 1px solid #ddd;"
        if idx < alignments.len:
          style &= " text-align: " & alignments[idx] & ";"

        rowHtml &= "<" & tag & " style='" & style & "'>" & trimmed & "</" & tag & ">"
      rowHtml &= "</tr>\n"
      htmlTable &= rowHtml

    htmlTable &= "</table>"
    return htmlTable
  , reMultiline)

  # Headers with IDs
  result = result.replaceRe(re"^# (.*)$", proc(m: RegexMatch): string =
    return "<h1 id='" & slugify(m[1]) & "'>" & m[1] & "</h1>"
  , reMultiline)
  result = result.replaceRe(re"^## (.*)$", proc(m: RegexMatch): string =
    return "<h2 id='" & slugify(m[1]) & "'>" & m[1] & "</h2>"
  , reMultiline)
  result = result.replaceRe(re"^### (.*)$", proc(m: RegexMatch): string =
    return "<h3 id='" & slugify(m[1]) & "'>" & m[1] & "</h3>"
  , reMultiline)

  # Blockquotes
  result = result.replaceRe(re"((?:^>\s*.*\n?)+)", proc(m: RegexMatch): string =
    var content = m[0]
    var lines = content.splitLines()
    var processedLines: seq[string] = @[]
    for line in lines:
      if line.startsWith(">"):
        var stripped = line[1..^1]
        if stripped.startsWith(" "):
          stripped = stripped[1..^1]
        processedLines.add(stripped)
      else:
        processedLines.add(line)
    let inner = processedLines.join("\n")
    return "<blockquote class='md-blockquote'>" & p.parseImpl(inner) & "</blockquote>"
  , reMultiline)

  # Reference Link Definitions
  var refLinks = initOrderedTable[string, string]()
  result = result.replaceRe(re"^\s*\[([^\]]+)\]: (.*)$", proc(m: RegexMatch): string =
    let id = m[1].strip()
    let url = m[2].strip()
    refLinks[id] = url
    return ""
  , reMultiline)

  # Footnote Definitions
  result = result.replaceRe(re"^\s*\[\^([^\]]+)\]: (.*)$", proc(m: RegexMatch): string =
    return "<div class='md-footnote' id='fn-" & m[1] & "'> <small>" & m[1] & ": " & m[2] & "</small> </div>"
  , reMultiline)

  # Task lists
  result = result.replaceRe(re"^\s*([\*\-]|\d+\.\s+)\s*\[\s\]\s+(.*)$", proc(m: RegexMatch): string =
    let prefix = m[1]
    let content = m[2]
    let cls = if prefix.contains(".") then "ol" else "ul"
    return "<li class='" & cls & "'> <input type='checkbox' disabled /> " & content & "</li>"
  , reMultiline)
  result = result.replaceRe(re"^\s*([\*\-]|\d+\.\s+)\s*\[x\]\s+(.*)$", proc(m: RegexMatch): string =
    let prefix = m[1]
    let content = m[2]
    let cls = if prefix.contains(".") then "ol" else "ul"
    return "<li class='" & cls & "'> <input type='checkbox' checked disabled /> " & content & "</li>"
  , reMultiline)

  # Unordered Lists
  result = result.replaceRe(re"^\s*[\*\-] (.*)$", proc(m: RegexMatch): string =
    return "<li class='ul'>" & m[1] & "</li>"
  , reMultiline)

  # Ordered Lists
  result = result.replaceRe(re"^\s*\d+\.\s+(.*)$", proc(m: RegexMatch): string =
    return "<li class='ol'>" & m[1] & "</li>"
  , reMultiline)

  # Wrap lists - process groups of items without merging across blank lines
  result = result.replaceRe(re"((?:<li class='ul'>.*?</li>(?:[ \t]*\n)?)+)", "<ul\n$1</ul>", reMultiline)
  result = result.replaceRe(re"((?:<li class='ol'>.*?</li>(?:[ \t]*\n)?)+)", "<ol\n$1</ol>", reMultiline)

  result = result.replace("<li class='ul'>", "<li>").replace("<li class='ol'>", "<li>")

  # Inline formatting - Applied multiple times to allow nesting (e.g. bold inside italic)
  var changed = true
  var iterations = 0
  while changed and iterations < 3:
    let prev = result
    # Handle Images: ![alt](url "title") or ![alt](url)
    result = result.replaceRe(re"!\[([^\]]*)\]\(([^\s\)]+)(?:\s+[\"'](.*?)[\"'])?\)", proc(m: RegexMatch): string =
      var img = "<img src='" & m[2] & "' alt='" & m[1] & "'"
      if m.len > 3 and m[3] != "":
        img &= " title='" & m[3] & "'"
      img &= " />"
      return img
    )
    result = result.replaceRe(re"`(.*?)`", proc(m: RegexMatch): string =
      return "<code style='background: #f4f4f4; padding: 2px 4px; border-radius: 3px;'>" & m[1] & "</code>"
    )

    # Handle Links: [text](url "title") or [text](url)
    # Includes support for internal links (URLs starting with #)
    result = result.replaceRe(re"\[([^\]]*)\]\(([^\s\)]+)(?:\s+[\"'](.*?)[\"'])?\)", proc(m: RegexMatch): string =
      var url = m[2]

      var link = "<a href='" & url & "'>" & m[1] & "</a>"
      if m.len > 3 and m[3] != "":
        link = "<a href='" & url & "' title='" & m[3] & "'>" & m[1] & "</a>"
      return link
    )

    # Handle Reference Links: [text][id]
    result = result.replaceRe(re"\[([^\]]*)\]\[([^\]]*)\]", proc(m: RegexMatch): string =
      let text = m[1]
      var id = m[2].strip()
      if id == "":
        id = text.strip()
      if refLinks.contains(id):
        return "<a href='" & refLinks[id] & "'>" & text & "</a>"
      else:
        return "[" & text & "][" & id & "]"
    )
    result = result.replaceRe(re"\[\^([^\]]+)\]", "<sup><a href='#fn-\$1'>[\$1]</a></sup>")

    # Bold formatting (Strong)
    result = result.replaceRe(re"\*\*(.*?)\*\*", "<strong>$1</strong>")
    result = result.replaceRe(re"__(.*?)__", "<strong>$1</strong>")

    # Italic formatting (Emphasis)
    result = result.replaceRe(re"\*(.*?)\*", "<em>$1</em>")
    result = result.replaceRe(re"(?<!\w)_(.*?)(?!\w)_", "<em>$1</em>")

    # Strikethrough
    result = result.replaceRe(re"~~(.*?)~~", "<del>$1</del>")

    changed = prev != result
    iterations.inc()

  # Math blocks
  result = result.replaceRe(re"\$\$(.*?)\$\$", proc(m: RegexMatch): string =
    return "<div class='math-display'>" & m[1] & "</div>"
  , reDotAll)
  result = result.replaceRe(re"\$([^$]+?)\$", proc(m: RegexMatch): string =
    return "<span class='math-inline'>" & m[1] & "</span>"
  )

  # Paragraphs
  var lines = result.splitLines()
  var processedLines: seq[string] = @[]
  let blockTags = {"<h1", "<h2", "<h3", "<blockquote", "<ul", "<ol", "<table", "<pre", "<hr", "<div", "<p", "<section", "<article", "<header", "<footer", "<li", "<canvas", "<svg", "<iframe"}

  var currentParagraph = ""
  var inPre = false

  proc flushParagraph() =
    let trimmed = currentParagraph.strip()
    if trimmed != "":
      processedLines.add("<p>" & trimmed & "</p>")
    currentParagraph = ""

  for line in lines:
    let trimmed = line.strip()
    var isBlockTag = isBlockTag(trimmed) or inPre

    if trimmed.contains("<pre"):
      inPre = true
      isBlockTag = true
    if trimmed.contains("</pre>"):
      inPre = false

    if trimmed == "":
      flushParagraph()
      processedLines.add("")
    elif isBlockTag:
      flushParagraph()
      processedLines.add(line)
    else:
      if currentParagraph != "":
        currentParagraph &= " "
      currentParagraph &= line

  flushParagraph()
  result = processedLines.join("\n")

  return result

proc parse*(p: MarkdownParser, text: string): string =
  var result = escapeHtml(text)

  # Handle Escaped Characters
  let escMap = {
    "\\*": "\x1FESC_AST\x1F",
    "\\_": "\x1FESC_UND\x1F",
    "\\#": "\x1FESC_HASH\x1F",
    "\\`": "\x1FESC_TICK\x1F",
    "\\~": "\x1FESC_TILD\x1F",
    "\\[": "\x1FESC_LBRK\x1F",
    "\\]": "\x1FESC_RBRK\x1F",
    "\\(": "\x1FESC_LPAR\x1F",
    "\\)": "\x1FESC_RPAR\x1F",
    "\\$": "\x1FESC_DOL\x1F",
    "\\\\": "\x1FESC_BSLASH\x1F"
  }

  for esc, placeholder in escMap.pairs:
    result = result.replace(esc, placeholder)

  result = p.parseImpl(result)

  # Restore Escaped Characters
  for esc, placeholder in escMap.pairs:
    let char = esc[1..^1]
    result = result.replace(placeholder, char)

  # Run custom plugins
  for plugin in p.plugins:
    result = plugin(result)

  return result
