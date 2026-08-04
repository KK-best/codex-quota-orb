import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift make_icns.swift ICONSET_DIR OUTPUT.icns\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let chunks: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func appendASCII(_ string: String, to data: inout Data) {
    data.append(contentsOf: string.utf8)
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) {
        data.append(contentsOf: $0)
    }
}

var payload = Data()
for (type, filename) in chunks {
    let imageData = try Data(
        contentsOf: iconsetURL.appendingPathComponent(filename)
    )
    appendASCII(type, to: &payload)
    appendBigEndian(UInt32(imageData.count + 8), to: &payload)
    payload.append(imageData)
}

var container = Data()
appendASCII("icns", to: &container)
appendBigEndian(UInt32(payload.count + 8), to: &container)
container.append(payload)
try container.write(to: outputURL)
