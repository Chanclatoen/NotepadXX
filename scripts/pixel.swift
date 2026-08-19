// Development helper: print the colour of given pixels in a screenshot, so
// design-token claims can be checked against what actually rendered.
// Usage: swift scripts/pixel.swift shot.png x,y [x,y ...]
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
// Read the file's bitmap directly: going through NSImage/tiffRepresentation
// drops the embedded profile, which silently desaturates wide-gamut captures.
guard let path = arguments.first,
      let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let bitmap = NSBitmapImageRep(data: data) else {
    FileHandle.standardError.write(Data("usage: pixel.swift <png> <x,y>...\n".utf8))
    exit(1)
}
print("size \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
for argument in arguments.dropFirst() {
    let parts = argument.split(separator: ",").compactMap { Int($0) }
    guard parts.count == 2, let colour = bitmap.colorAt(x: parts[0], y: parts[1]) else { continue }
    // Use the components as stored. `colorAt` hands back a colour tagged with a
    // generic profile, so converting it "to sRGB" transforms values that are
    // already sRGB and silently lightens everything.
    let hex = String(format: "#%02X%02X%02X",
                     Int((colour.redComponent * 255).rounded()),
                     Int((colour.greenComponent * 255).rounded()),
                     Int((colour.blueComponent * 255).rounded()))
    print("\(parts[0]),\(parts[1]) \(hex)")
}
