import strutils, re

type
  MarkdownParser = object
    plugins: seq[proc(s: string): string]

proc newParser(): MarkdownParser =
  return MarkdownParser(plugins: @[])

proc addPlugin(p: var MarkdownParser, plugin: proc(s: string): string) =
  p.plugins.add(plugin)

proc parse(p: MarkdownParser, text: string): string =
  var result = text
  
  # Fenced Code Blocks
  # This handles ```code``` patterns
  result = result.replaceRe(re"```(.*?)```", "<pre><code>$1</code></pre>", reDotAll)

  # Basic block parsing
  # Horizontal Rules
  result = result.replaceRe(re"^---$", "<hr />", reMultiline)

  # Headers
  result = result.replaceRe(re"^# (.*)$", "<h1>$1</h1>", reMultiline)
  result = result.replaceRe(re"^## (.*)$", "<h2>$1</h2>", reMultiline)
  result = result.replaceRe(re"^### (.*)$", "<h3>$1</h3>", reMultiline)
  
  # Blockquotes
  result = result.replaceRe(re"^> (.*)$", "<blockquote>$1</blockquote>", reMultiline)

  # Unordered Lists
  result = result.replaceRe(re"^\* (.*)$", "<li>$1</li>", reMultiline)
  result = result.replaceRe(re"^- (.*)$", "<li>$1</li>", reMultiline)

  # Ordered Lists
  result = result.replaceRe(re"^\d+\.\s+(.*)$", "<li>$1</li>", reMultiline)
  
  # Wrap lists in containers
  # This is a simple approach: find sequences of <li> and wrap them
  result = result.replaceRe(re"((?:<li>.*?</li>\s*)+)", "<ul>\n$1</ul>", reMultiline)
  # Note: This basic implementation treats all lists as <ul> for simplicity, 
  # a more advanced parser would distinguish between ol and ul.

  # Inline formatting
  # Images: ![alt](url)
  result = result.replaceRe(re"!\[(.*?)\]\((.*?)\)", "<img src='$2' alt='$1' />")
  # Inline Code
  result = result.replaceRe(re"`(.*?)`", "<code>$1</code>")
  # Links: [text](url)
  result = result.replaceRe(re"\[(.*?)\]\((.*?)\)", "<a href='$2'>$1</a>")
  # Bold and Italic
  result = result.replaceRe(re"\*\*(.*?)\*\*", "<strong>$1</strong>")
  result = result.replaceRe(re"\*(.*?)\*", "<em>$1</em>")
  
  # Paragraphs
  var lines = result.splitLines()
  var processedLines: seq[string] = @[]
  for line in lines:
    let trimmed = line.strip()
    if trimmed == "":
      processedLines.add("")
    elif trimmed.startsWith("<") && 
          (trimmed.startsWith("<h") or 
           trimmed.startsWith("<blockquote") or 
           trimmed.startsWith("<ul") or 
           trimmed.startsWith("<ol") or 
           trimmed.startsWith("<li") or 
           trimmed.startsWith("<pre") or 
           trimmed.startsWith("<hr")):
      processedLines.add(line)
    else:
      processedLines.add("<p>" & line & "</p>")
  
  result = processedLines.join("\n")

  # Run custom plugins
  for plugin in p.plugins:
    result = plugin(result)
    
  return result