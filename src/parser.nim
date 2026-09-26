import strutils, re

type
  MarkdownParser = object
    plugins: seq[proc(s: string): string]

proc newParser(): MarkdownParser =
  return MarkdownParser(plugins: @[])

proc addPlugin(p: var MarkdownParser, plugin: proc(s: string): string) =
  p.plugins.add(plugin)

proc escapeHtml(s: string): string =
  result = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")

proc parse(p: MarkdownParser, text: string): string =
  var result = text
  
  # Handle Escaped Characters
  # Temporary replacement to preserve escaped characters during parsing
  # We replace \* with a unique placeholder
  let escMap = {
    "\\*": "__ESC_AST__",
    "\\_": "__ESC_UND__",
    "\\#": "__ESC_HASH__",
    "\\`": "__ESC_TICK__",
    "\\~": "__ESC_TILD__",
    "\\[": "__ESC_LBRK__",
    "\\]": "__ESC_RBRK__",
    "\\(": "__ESC_LPAR__",
    "\\)": "__ESC_RPAR__",
    "\\\": "__ESC_BSLASH__"
  }
  
  for esc, placeholder in escMap.pairs:
    result = result.replace(esc, placeholder)

  # Fenced Code Blocks
  # This handles ```code``` patterns
  result = result.replaceRe(re"```(.*?)```", "<pre><code>$1</code></pre>", reDotAll)

  # Indented Code Blocks
  # Matches lines starting with 4 spaces or 1 tab
  result = result.replaceRe(re"((?:^\s{4}.*\n?)+)", proc(m: Match): string = 
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
    return "<pre><code>" & processedLines.join("\n") & "</code></pre>"
  , reMultiline)

  # Basic block parsing
  # Horizontal Rules
  result = result.replaceRe(re"^---$", "<hr />", reMultiline)

  # Tables
  # This is a simplified regex-based table parser
  # Matches lines with | and attempts to wrap them in table tags
  # Note: This requires a header row and a separator row
  let tablePattern = re"((?:^\s*\|[^\n]*\|\s*\n(?:^\s*\|[- :|]*\|\s*\n)(?:^\s*\|[^\n]*\|\s*\n)*))"
  result = result.replaceRe(tablePattern, proc(m: Match): string = 
    var tableContent = m[0]
    var lines = tableContent.splitLines()
    var htmlTable = "<table>\n"
    
    for i, line in lines:
      if line.strip() == "": continue
      if i == 1 && line.contains("---"): continue # Skip separator row
      
      let tag = if i == 0: "th" else: "td"
      let cells = line.split('|')
      var rowHtml = "  <tr>"
      for cell in cells:
        let trimmed = cell.strip()
        if trimmed != "":
          rowHtml &= "<" & tag & ">" & escapeHtml(trimmed) & "</" & tag & ">"
      rowHtml &= "</tr>\n"
      htmlTable &= rowHtml
    
    htmlTable &= "</table>"
    return htmlTable
  , reMultiline)

  # Headers
  result = result.replaceRe(re"^# (.*)$", "<h1>$1</h1>", reMultiline)
  result = result.replaceRe(re"^## (.*)$", "<h2>$1</h2>", reMultiline)
  result = result.replaceRe(re"^### (.*)$", "<h3>$1</h3>", reMultiline)
  
  # Blockquotes
  # Matches contiguous lines starting with '>' and wraps them
  result = result.replaceRe(re"((?:^>\s*.*\n?)+)", proc(m: Match): string = 
    var content = m[0]
    var lines = content.splitLines()
    var processedLines: seq[string] = @[]
    for line in lines:
      if line.startsWith(">"):
        # Trim the leading '>' and one optional space
        var stripped = line[1..^1]
        if stripped.startsWith(" "):
          stripped = stripped[1..^1]
        processedLines.add(stripped)
      else:
        processedLines.add(line)
    # Join and wrap. We don't wrap in <p> here yet, the final pass handles that
    return "<blockquote class='md-blockquote'>" & processedLines.join("\n") & "</blockquote>"
  , reMultiline)

  # Task lists (convert [ ] and [x] to checkboxes before list processing)
  result = result.replaceRe(re"^\s*([\*\-]|\d+\.\s+)\s*\[\s\]\s+(.*)$", "$1 <input type='checkbox' disabled /> $2", reMultiline)
  result = result.replaceRe(re"^\s*([\*\-]|\d+\.\s+)\s*\[x\]\s+(.*)$", "$1 <input type='checkbox' checked disabled /> $2", reMultiline)

  # Unordered Lists
  result = result.replaceRe(re"^\s*[\*\-] (.*)$", "<li class='ul'>$1</li>", reMultiline)

  # Ordered Lists
  result = result.replaceRe(re"^\s*\d+\.\s+(.*)$", "<li class='ol'>$1</li>", reMultiline)
  
  # Wrap lists in containers
  # Handle unordered lists: groups of <li> with ul class
  result = result.replaceRe(re"((?:<li class='ul'>.*?</li>\s*)+)", "<ul\n$1</ul>", reMultiline)
  # Handle ordered lists: groups of <li> with ol class
  result = result.replaceRe(re"((?:<li class='ol'>.*?</li>\s*)+)", "<ol\n$1</ol>", reMultiline)
  
  # Clean up internal classes
  result = result.replace("<li class='ul'>", "<li>").replace("<li class='ol'>", "<li>")

  # Inline formatting
  # Images: ![alt](url)
  result = result.replaceRe(re"!\[(.*?)\]\((.*?)\)", "<img src='$2' alt='$1' />")
  # Inline Code
  result = result.replaceRe(re"`(.*?)`", "<code>$1</code>")
  # Links: [text](url)
  result = result.replaceRe(re"\[(.*?)\]\((.*?)\)", "<a href='$2'>$1</a>")
  # Bold
  result = result.replaceRe(re"\*\*(.*?)\*\*", "<strong>$1</strong>")
  result = result.replaceRe(re"__(.*?)__", "<strong>$1</strong>")
  # Italic
  result = result.replaceRe(re"\*(.*?)\*", "<em>$1</em>")
  result = result.replaceRe(re"_(.*?)_", "<em>$1</em>")
  # Strikethrough
  result = result.replaceRe(re"~~(.*?)~~", "<del>$1</del>")
  
  # Math blocks
  # Display math: $$...$$
  result = result.replaceRe(re"\$\$(.*?)\$\$", "<div class='math-display'>$1</div>", reDotAll)
  # Inline math: $...$
  result = result.replaceRe(re"\$([^$]+?)\$", "<span class='math-inline'>$1</span>")
  
  # Paragraphs
  var lines = result.splitLines()
  var processedLines: seq[string] = @[]
  let blockTags = {"<h1", "<h2", "<h3", "<blockquote", "<ul", "<ol", "<table", "<pre", "<hr", "<div", "<p"}
  
  for line in lines:
    let trimmed = line.strip()
    if trimmed == "":
      processedLines.add("")
    elif trimmed.startsWith("<") && any(trimmed.startsWith(tag) for tag in blockTags):
      # If the line starts with a known block-level tag, don't wrap in <p>
      processedLines.add(line)
    else:
      processedLines.add("<p>" & line & "</p>")
  
  result = processedLines.join("\n")

  # Restore Escaped Characters
  for esc, placeholder in escMap.pairs:
    let char = esc[1..^1] # Remove the backslash
    result = result.replace(placeholder, char)

  # Run custom plugins
  for plugin in p.plugins:
    result = plugin(result)
    
  return result