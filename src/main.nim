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

  let html = parser.parse(content)
  echo html

when isMainModule:
  run()