import os, strutils
import parser

proc run()
  if paramCount() < 1:
    echo "Usage: clippy-markdown <filename>"
    return

  let filename = paramStr(1)
  if not fileExists(filename):
    echo "Error: File not found: ", filename
    return

  let content = readFile(filename)
  var parser = newParser()

  # Example plugin: Replace custom TODO markers
  parser.addPlugin(proc(s: string): string = 
    s.replace("TODO:", "<span style='color: red;'>TODO:</span>")
  )

  let body = parser.parse(content)
  
  # Wrap in basic HTML5 structure
  let html = "<!DOCTYPE html>\n<html>\n<head>\n  <meta charset='UTF-8'>\n  <title>Converted Markdown</title>\n  <style>body { font-family: sans-serif; line-height: 1.6; max-width: 800px; margin: 40px auto; padding: 0 20px; } pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; } table { border-collapse: collapse; width: 100%; } th, td { border: 1px solid #ddd; padding: 8px; } th { background: #eee; } .md-blockquote { border-left: 4px solid #ccc; padding-left: 16px; color: #666; font-style: italic; } .math-display { text-align: center; margin: 1em 0; font-family: serif; }</style>\n</head>\n<body>\n" & body & "\n</body>\n</html>"
  
  echo html

when isMainModule:
  run()