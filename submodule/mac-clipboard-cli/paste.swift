
import Cocoa
import Foundation

func copy() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    
    let input = FileHandle.standardInput
    let data = input.readDataToEndOfFile()
    
    if !data.isEmpty {
        pasteboard.setData(data, forType: .tiff)
    } else {
        FileHandle.standardError.write("Error: No input received for copying.\n".data(using: .utf8)!)
        exit(1)
    }
}

func paste() {
    let pasteboard = NSPasteboard.general
    if let types = pasteboard.types {
        if let data = types.compactMap({ pasteboard.data(forType: $0) }).first {
            FileHandle.standardOutput.write(data)
        } else {
            FileHandle.standardError.write("Error: Clipboard is empty or contains unsupported content.\n".data(using: .utf8)!)
            exit(1)
        }
    } else {
        FileHandle.standardError.write("Error: Unable to access clipboard types.\n".data(using: .utf8)!)
        exit(1)
    }
}

let args = CommandLine.arguments

if args.count != 2 {
    FileHandle.standardError.write("Usage: \(args[0]) [-c|-p]\n".data(using: .utf8)!)
    FileHandle.standardError.write("  -c: Copy input from stdin to clipboard\n".data(using: .utf8)!)
    FileHandle.standardError.write("  -p: Paste clipboard content to stdout\n".data(using: .utf8)!)
    exit(1)
}

switch args[1] {
case "-c":
    copy()
case "-p":
    paste()
default:
    FileHandle.standardError.write("Error: Invalid argument. Use -c for copy or -p for paste.\n".data(using: .utf8)!)
    exit(1)
}

