
import Cocoa
import Foundation

func isLikelyText(_ data: Data) -> Bool {
    // 检查前1024字节（或整个数据如果小于1024字节）
    let sampleSize = min(1024, data.count)
    let sample = data.prefix(sampleSize)
    
    // 检查是否全是有效的UTF-8字符
    return String(data: sample, encoding: .utf8) != nil
}

func copy() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    
    let input = FileHandle.standardInput
    let data = input.readDataToEndOfFile()
    
    if !data.isEmpty {
        if isLikelyText(data) {
            if let string = String(data: data, encoding: .utf8) {
                pasteboard.setString(string, forType: .string)
            } else {
                pasteboard.setData(data, forType: .tiff)
            }
        } else {
            pasteboard.setData(data, forType: .tiff)
        }
    } else {
        FileHandle.standardError.write("Error: No input received for copying.\n".data(using: .utf8)!)
        exit(1)
    }
}

func paste() {
    let pasteboard = NSPasteboard.general
    if let string = pasteboard.string(forType: .string) {
        FileHandle.standardOutput.write(string.data(using: .utf8)!)
    } else if let data = pasteboard.data(forType: .tiff) {
        FileHandle.standardOutput.write(data)
    } else {
        FileHandle.standardError.write("Error: Clipboard is empty or contains unsupported content.\n".data(using: .utf8)!)
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

