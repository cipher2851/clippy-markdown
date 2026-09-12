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
  
  # Basic block parsing
  # Headers
  result = result.replaceRe(re"^# (.*)$", "<h1>$1</h1>", reMultiline)
  result = result.replaceRe(re"^## (.*)$", "<h2>$1</h2>", reMultiline)
  result = result.replaceRe(re"^### (.*)$", "<h3>$1</h3>", reMultiline)
  
  # Bold and Italic
  result = result.replaceRe(re"\*\*(.*?)\*\*", "<strong>$1</strong>")
  result = result.replaceRe(re"\*(.*?)\*", "<em>$1</em>")
  
  # Paragraphs (very basic)
  var lines = result.splitLines()
  var processedLines: seq[string] = @[]
  for line in lines:
    if line.strip() == "":
      processedLines.add("")
    elif line.startsWith("<"):
      processedLines.add(line)
    else:
      processedLines.add("<p>" & line & "</p>")
  
  result = processedLines.join("\n")

  # Run custom plugins
  for plugin in p.plugins:
    result = plugin(result)
    
  return result