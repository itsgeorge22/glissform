import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: set-file-icon.swift <icon.icns> <file>\n", stderr)
    exit(1)
}

guard let icon = NSImage(contentsOfFile: CommandLine.arguments[1]),
      NSWorkspace.shared.setIcon(icon, forFile: CommandLine.arguments[2], options: []) else {
    fputs("Could not apply the custom Finder icon.\n", stderr)
    exit(1)
}
