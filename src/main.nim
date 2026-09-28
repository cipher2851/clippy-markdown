import os, strutils
import parser

const DEFAULT_STYLE = "body { font-family: sans-serif; line-height: 1.6; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #333; } pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; border: 1px solid #ddd; } table { border-collapse: collapse; width: 100%; margin: 1em 0; } th, td { border: 1px solid #ddd; padding: 8px; } th { background: #eee; } .md-blockquote { border-left: 4px solid #ccc; padding-left: 16px; color: #666; font-style: italic; margin: 1em 0; } .math-display { text-align: center; margin: 1em 0; font-family: serif; } .math-inline { font-family: serif; } .md-footnote { margin-top: 2em; border-top: 1px solid #eee; padding-top: 1em; }";

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
    s.replace("TODO:", "<span style='color: red; font-weight: bold;'>TODO:</span>")
  )

  let body = parser.parse(content)
  
  # Wrap in basic HTML5 structure
  let html = "<!DOCTYPE html>\n<html lang='en'>\n<head>\n  <meta charset='UTF-8'>\n  <title>Converted Markdown</title>\n  <style>" & DEFAULT_STYLE & "</style>\n</head>\n<body>\n" & body & "\n</body>\n</html>"
  
  echo html

when isMainModule:
  run()