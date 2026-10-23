import strutils, tables

type
  RefInfo = object
    url: string
    title: string

  Parser* = ref object
    plugins: seq[proc(s: string): string]
    refs: Table[string, RefInfo]

proc newParser*(): Parser =
  Parser(plugins: @[], refs: initTable[string, RefInfo]())

proc addPlugin*(p: Parser, plugin: proc(s: string): string) =
  p.plugins.add(plugin)

proc escapeHtml(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")

proc escapeChar(c: char): string =
  case c
  of '&': "&amp;"
  of '<': "&lt;"
  of '>': "&gt;"
  else: $c

proc stripTitle(s: string): string =
  let t = s.strip()
  if t.len == 0: return ""
  if (t.startsWith("\"") and t.endsWith("\"")) or
     (t.startsWith("'") and t.endsWith("'")) or
     (t.startsWith("(") and t.endsWith(")")):
    return t[1..^2]
  return t

proc collectRefs(lines: seq[string]): Table[string, RefInfo] =
  result = initTable[string, RefInfo]()
  for line in lines:
    let t = line.strip()
    if t.len == 0 or not t.startsWith("["): continue
    let close = t.find(']')
    if close <= 0: continue
    if close + 1 >= t.len or t[close + 1] != ':': continue
    let label = t[1..close - 1].strip().toLowerAscii()
    let rest = t[close + 2 .. ^1].strip()
    if rest.len == 0: continue
    var url = ""
    var title = ""
    if rest.startsWith("<"):
      let gt = rest.find('>')
      if gt > 0:
        url = rest[1 .. gt - 1]
        title = stripTitle(rest[gt + 1 .. ^1].strip())
    else:
      var i = 0
      while i < rest.len and not rest[i].isSpaceAscii(): i += 1
      url = rest[0 ..< i]
      title = stripTitle(rest[i .. ^1].strip())
    result[label] = RefInfo(url: url, title: title)

proc isRefDef(line: string): bool =
  let t = line.strip()
  if not t.startsWith("["): return false
  let close = t.find(']')
  if close <= 0: return false
  if close + 1 >= t.len: return false
  return t[close + 1] == ':'

proc isHr(t: string): bool =
  if t.len < 3: return false
  let c = t[0]
  if c notin {'-', '*', '_'}: return false
  var count = 0
  for ch in t:
    if ch == c: count += 1
    elif ch.isSpaceAscii(): discard
    else: return false
  count >= 3

proc isListItem(t: string): bool =
  if t.startsWith("* ") or t.startsWith("- ") or t.startsWith("+ "): return true
  var i = 0
  while i < t.len and t[i].isdigit(): i += 1
  if i > 0 and i < t.len and t[i] == '.' and i + 1 < t.len and t[i + 1].isSpaceAscii(): return true
  return false

proc isOrderedItem(t: string): bool =
  var i = 0
  while i < t.len and t[i].isdigit(): i += 1
  return i > 0 and i < t.len and t[i] == '.'

proc stripListMarker(t: string): string =
  if t.startsWith("* ") or t.startsWith("- ") or t.startsWith("+ "):
    return t[2 .. ^1]
  var i = 0
  while i < t.len and t[i].isdigit(): i += 1
  if i < t.len and t[i] == '.':
    return t[i + 1 .. ^1].strip()
  return t

proc isTableSep(line: string): bool =
  let t = line.strip()
  if not t.contains("|"): return false
  for ch in t:
    if ch notin {'|', '-', ' ', ':'}: return false
  return t.contains("-")

proc splitCols(line: string): seq[string] =
  var t = line.strip()
  if t.startsWith("|"): t = t[1 .. ^1]
  if t.endsWith("|"): t = t[0 .. ^2]
  return t.split('|')

proc slugify(s: string): string =
  result = s.toLowerAscii()
  result = result.replace(" ", "-")

proc parseInline(text: string, refs: Table[string, RefInfo]): string

proc parseTable(lines: seq[string], start: int, refs: Table[string, RefInfo]): (string, int) =
  var i = start
  let headerLine = lines[i].strip()
  i += 1
  let sepLine = lines[i].strip()
  i += 1
  let sepCols = splitCols(sepLine)
  var aligns: seq[string] = @[]
  for c in sepCols:
    let ct = c.strip()
    if ct.startsWith(":") and ct.endsWith(":"): aligns.add "center"
    elif ct.endsWith(":"): aligns.add "right"
    else: aligns.add "left"
  let headerCols = splitCols(headerLine)
  var html = "<table style='border-collapse: collapse; width: 100%; margin: 1em 0;'>\n<thead>\n<tr>\n"
  for idx, hc in headerCols:
    let a = if idx < aligns.len: aligns[idx] else: "left"
    html.add "<th style='padding: 8px; border: 1px solid #ddd; background: #eee; text-align: " & a & ";'>" & parseInline(hc.strip(), refs) & "</th>\n"
  html.add "</tr>\n</thead>\n<tbody>\n"
  while i < lines.len and lines[i].strip() != "" and lines[i].contains("|"):
    let rowLine = lines[i].strip()
    if isRefDef(rowLine): break
    let cols = splitCols(rowLine)
    html.add "<tr>\n"
    for idx, c in cols:
      let a = if idx < aligns.len: aligns[idx] else: "left"
      html.add "<td style='padding: 8px; border: 1px solid #ddd; text-align: " & a & ";'>" & parseInline(c.strip(), refs) & "</td>\n"
    html.add "</tr>\n"
    i += 1
  html.add "</tbody>\n</table>"
  return (html, i)

proc parseInline(text: string, refs: Table[string, RefInfo]): string =
  result = ""
  var i = 0
  let n = text.len
  while i < n:
    if text[i] == '\\' and i + 1 < n:
      result.add escapeChar(text[i + 1])
      i += 2
      continue
    if text[i] == '`':
      var j = i + 1
      while j < n and text[j] != '`': j += 1
      if j < n:
        result.add "<code style='background: #f4f4f4; padding: 2px 4px; border-radius: 3px;'>" & escapeHtml(text[i + 1 .. j - 1]) & "</code>"
        i = j + 1
        continue
      else:
        result.add "`"
        i += 1
        continue
    if text[i] == '!' and i + 1 < n and text[i + 1] == '[':
      var j = i + 2
      while j < n and text[j] != ']': j += 1
      if j < n:
        let alt = text[i + 2 .. j - 1]
        var k = j + 1
        if k < n and text[k] == '(':
          var l = k + 1
          var depthp = 1
          while l < n and not (text[l] == ')' and depthp == 1):
            if text[l] == '(': depthp += 1
            elif text[l] == ')': depthp -= 1
            l += 1
          if l < n:
            let inner = text[k + 1 .. l - 1].strip()
            var url = inner
            var title = ""
            let sp = url.find(' ')
            if sp >= 0:
              title = stripTitle(url[sp + 1 .. ^1])
              url = url[0 .. sp - 1].strip()
            url = url.strip(chars = {'<', '>'})
            result.add "<img src='" & url & "' alt='" & parseInline(alt, refs) & "'"
            if title.len > 0: result.add " title='" & title & "'"
            result.add " />"
            i = l + 1
            continue
        elif k < n and text[k] == '[':
          var l = k + 1
          while l < n and text[l] != ']': l += 1
          if l < n:
            var label = text[k + 1 .. l - 1].strip()
            if label == "": label = alt
            let key = label.toLowerAscii()
            if refs.hasKey(key):
              let info = refs[key]
              result.add "<img src='" & info.url & "' alt='" & parseInline(alt, refs) & "'"
              if info.title.len > 0: result.add " title='" & info.title & "'"
              result.add " />"
              i = l + 1
              continue
        # collapsed reference image
        let key = alt.toLowerAscii()
        if refs.hasKey(key):
          let info = refs[key]
          result.add "<img src='" & info.url & "' alt='" & parseInline(alt, refs) & "'"
          if info.title.len > 0: result.add " title='" & info.title & "'"
          result.add " />"
          i = j + 1
          continue
      result.add "!"
      i += 1
      continue
    if text[i] == '[':
      var j = i + 1
      while j < n and text[j] != ']': j += 1
      if j < n:
        let linkText = text[i + 1 .. j - 1]
        var k = j + 1
        if k < n and text[k] == '(':
          var l = k + 1
          var depthp = 1
          while l < n and not (text[l] == ')' and depthp == 1):
            if text[l] == '(': depthp += 1
            elif text[l] == ')': depthp -= 1
            l += 1
          if l < n:
            let inner = text[k + 1 .. l - 1].strip()
            var url = inner
            var title = ""
            let sp = url.find(' ')
            if sp >= 0:
              title = stripTitle(url[sp + 1 .. ^1])
              url = url[0 .. sp - 1].strip()
            url = url.strip(chars = {'<', '>'})
            result.add "<a href='" & url & "'"
            if title.len > 0: result.add " title='" & title & "'"
            result.add ">" & parseInline(linkText, refs) & "</a>"
            i = l + 1
            continue
        elif k < n and text[k] == '[':
          var l = k + 1
          while l < n and text[l] != ']': l += 1
          if l < n:
            var label = text[k + 1 .. l - 1].strip()
            if label == "": label = linkText
            let key = label.toLowerAscii()
            if refs.hasKey(key):
              let info = refs[key]
              result.add "<a href='" & info.url & "'"
              if info.title.len > 0: result.add " title='" & info.title & "'"
              result.add ">" & parseInline(linkText, refs) & "</a>"
              i = l + 1
              continue
        # collapsed reference link
        if k >= n or text[k] notin ['(', '[']:
          let key = linkText.toLowerAscii()
          if refs.hasKey(key):
            let info = refs[key]
            result.add "<a href='" & info.url & "'"
            if info.title.len > 0: result.add " title='" & info.title & "'"
            result.add ">" & parseInline(linkText, refs) & "</a>"
            i = j + 1
            continue
      result.add "["
      i += 1
      continue
    if text[i] == '*' and i + 1 < n and text[i + 1] == '*':
      var j = i + 2
      while j + 1 < n and not (text[j] == '*' and text[j + 1] == '*'): j += 1
      if j + 1 < n:
        result.add "<strong>" & parseInline(text[i + 2 .. j - 1], refs) & "</strong>"
        i = j + 2
        continue
    if text[i] == '*' :
      var j = i + 1
      while j < n and text[j] != '*': j += 1
      if j < n:
        result.add "<em>" & parseInline(text[i + 1 .. j - 1], refs) & "</em>"
        i = j + 1
        continue
    if text[i] == '_' :
      var j = i + 1
      while j < n and text[j] != '_': j += 1
      if j < n:
        result.add "<em>" & parseInline(text[i + 1 .. j - 1], refs) & "</em>"
        i = j + 1
        continue
    if text[i] == '~' and i + 1 < n and text[i + 1] == '~':
      var j = i + 2
      while j + 1 < n and not (text[j] == '~' and text[j + 1] == '~'): j += 1
      if j + 1 < n:
        result.add "<del>" & parseInline(text[i + 2 .. j - 1], refs) & "</del>"
        i = j + 2
        continue
    if text[i] == '$':
      if i + 1 < n and text[i + 1] == '$':
        var j = i + 2
        while j + 1 < n and not (text[j] == '$' and text[j + 1] == '$'): j += 1
        if j + 1 < n:
          result.add "<div class='math-display'>" & escapeHtml(text[i + 2 .. j - 1]) & "</div>"
          i = j + 2
          continue
      else:
        var j = i + 1
        while j < n and text[j] != '$': j += 1
        if j < n:
          result.add "<span class='math-inline'>" & escapeHtml(text[i + 1 .. j - 1]) & "</span>"
          i = j + 1
          continue
    if text[i] == '[' and i + 1 < n and text[i + 1] == '^':
      var j = i + 2
      while j < n and text[j] != ']': j += 1
      if j < n:
        let label = text[i + 2 .. j - 1]
        result.add "<sup><a href='#fn-" & label & "'>" & label & "</a></sup>"
        i = j + 1
        continue
    if text[i] == '<' and i + 3 < n and text[i .. i + 3] == "<!--":
      let j = text.find("-->", i)
      if j >= 0:
        i = j + 3
        continue
    result.add escapeHtml($text[i])
    i += 1

proc isBlockStart(t: string, lines: seq[string], i: int): bool =
  if t == "": return true
  if t.startsWith("#"): return true
  if t.startsWith(">"): return true
  if t.startsWith("```") or t.startsWith("~~~"): return true
  if isHr(t): return true
  if isListItem(t): return true
  if t.startsWith("    ") or t.startsWith("\t"): return true
  if t.startsWith("$$"): return true
  if isRefDef(t): return true
  if i + 1 < lines.len and isTableSep(lines[i + 1].strip()): return true
  return false

proc parse*(p: Parser, md: string): string =
  let lines = md.splitLines()
  p.refs = collectRefs(lines)

  var footnoteDefs = initTable[string, string]()
  for line in lines:
    let t = line.strip()
    if not t.startsWith("[^")): continue
    let close = t.find(']')
    if close <= 0: continue
    if close + 1 >= t.len or t[close + 1] != ':': continue
    let label = t[2 .. close - 1]
    let text = t[close + 2 .. ^1].strip()
    footnoteDefs[label] = text

  var i = 0
  let n = lines.len
  var outBlocks: seq[string] = @[]

  while i < n:
    let line = lines[i]
    let trimmed = line.strip()
    if trimmed == "":
      i += 1
      continue
    if isRefDef(trimmed):
      i += 1
      continue
    # footnote def
    if trimmed.startsWith("[^")) and trimmed.contains("]:"):
      let close = trimmed.find(']')
      if close > 0 and close + 1 < trimmed.len and trimmed[close + 1] == ':':
        i += 1
        continue
    # header
    if trimmed.startsWith("#"):
      var level = 0
      while level < trimmed.len and level < 6 and trimmed[level] == '#': level += 1
      if level >= 1 and (level == trimmed.len or trimmed[level].isSpaceAscii()):
        let text = trimmed[level .. ^1].strip()
        let id = slugify(text)
        outBlocks.add "<h" & $level & " id='" & id & "'>" & parseInline(text, p.refs) & "</h" & $level & ">"
        i += 1
        continue
    # fenced code
    if trimmed.startsWith("```") or trimmed.startsWith("~~~"):
      let fence = trimmed[0 .. 2]
      i += 1
      var codeLines: seq[string] = @[]
      while i < n and not lines[i].strip().startsWith(fence):
        codeLines.add lines[i]
        i += 1
      i += 1
      outBlocks.add "<pre><code>" & escapeHtml(codeLines.join("\n")) & "</code></pre>"
      continue
    # hr
    if isHr(trimmed):
      outBlocks.add "<hr />"
      i += 1
      continue
    # blockquote
    if trimmed.startsWith(">"):
      var bqLines: seq[string] = @[]
      while i < n and lines[i].strip().startsWith(">"):
        bqLines.add lines[i].strip()[1 .. ^1].strip()
        i += 1
      outBlocks.add "<blockquote class='md-blockquote'>" & parseInline(bqLines.join(" "), p.refs) & "</blockquote>"
      continue
    # display math
    if trimmed.startsWith("$$") and trimmed.endsWith("$$") and trimmed.len > 4:
      outBlocks.add "<div class='math-display'>" & escapeHtml(trimmed[2 .. ^3]) & "</div>"
      i += 1
      continue
    # table
    if i + 1 < n and isTableSep(lines[i + 1].strip()):
      let (html, newI) = parseTable(lines, i, p.refs)
      outBlocks.add html
      i = newI
      continue
    # list
    if isListItem(trimmed):
      var ordered = isOrderedItem(trimmed)
      var items: seq[string] = @[]
      while i < n and isListItem(lines[i].strip()):
        let t = lines[i].strip()
        let content = stripListMarker(t).strip()
        var itemHtml = ""
        if content.startsWith("[ ] ") or content.startsWith("[x] ") or content.startsWith("[X] "):
          let rest = content[4 .. ^1]
          if content.startsWith("[ ] "):
            itemHtml = "<input type='checkbox' disabled /> " & parseInline(rest, p.refs)
          else:
            itemHtml = "<input type='checkbox' checked disabled /> " & parseInline(rest, p.refs)
        else:
          itemHtml = parseInline(content, p.refs)
        items.add itemHtml
        i += 1
      var tag = if ordered: "ol" else: "ul"
      var html = "<" & tag & ">\n"
      for it in items:
        html.add "<li>" & it & "</li>\n"
      html.add "</" & tag & ">"
      outBlocks.add html
      continue
    # indented code
    if line.startsWith("    ") or line.startsWith("\t"):
      var codeLines: seq[string] = @[]
      while i < n and (lines[i].startsWith("    ") or lines[i].startsWith("\t")):
        codeLines.add lines[i].strip(leading = true)
        i += 1
      outBlocks.add "<pre><code>" & escapeHtml(codeLines.join("\n")) & "</code></pre>"
      continue
    # paragraph
    var paraLines: seq[string] = @[]
    while i < n and lines[i].strip() != "" and not isBlockStart(lines[i].strip(), lines, i):
      if isRefDef(lines[i].strip()):
        i += 1
        continue
      paraLines.add lines[i].strip()
      i += 1
    if paraLines.len > 0:
      outBlocks.add "<p>" & parseInline(paraLines.join(" "), p.refs) & "</p>"
    continue

  # Post-process: last list block loses trailing newline before closing tag
  if outBlocks.len > 0:
    let last = outBlocks[^1]
    if last.startsWith("<ul>") or last.startsWith("<ol>"):
      outBlocks[^1] = last.replace("\n</ul>", "</ul>").replace("\n</ol>", "</ol>")

  var html = outBlocks.join("\n")
  for plugin in p.plugins:
    html = plugin(html)

  if footnoteDefs.len > 0:
    var fnHtml = "<div class='md-footnote'>\n<ol>\n"
    for label, text in footnoteDefs:
      fnHtml.add "<li id='fn-" & label & "'>" & parseInline(text, p.refs) & "</li>\n"
    fnHtml.add "</ol>\n</div>"
    html.add "\n" & fnHtml

  return html