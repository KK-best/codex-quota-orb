import Foundation

/// Reads JSONL records from the end of a file without repeatedly copying a
/// record that spans several read chunks.
public struct ReverseJSONLLineReader {
    public struct Metrics: Equatable {
        public let fileBytesRead: UInt64
        public let lineAssemblyBytes: UInt64
    }

    /// Calls `handleLine` once per nonempty line in reverse file order.
    /// Returning `true` stops scanning immediately.
    @discardableResult
    public static func readLines(
        at url: URL,
        chunkSize: Int = 256 * 1_024,
        handleLine: (Data) throws -> Bool
    ) throws -> Metrics {
        precondition(chunkSize > 0)

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var offset = try handle.seekToEnd()
        var boundarySegments: [Data] = []
        var fileBytesRead: UInt64 = 0
        var lineAssemblyBytes: UInt64 = 0

        while offset > 0 {
            let length = min(UInt64(chunkSize), offset)
            offset -= length
            try handle.seek(toOffset: offset)
            let chunk = try handle.read(upToCount: Int(length)) ?? Data()
            fileBytesRead += UInt64(chunk.count)

            var lineEnd = chunk.endIndex
            var foundNewline = false
            while lineEnd > chunk.startIndex,
                  let newline = chunk[..<lineEnd].lastIndex(of: 0x0A) {
                foundNewline = true
                let lineStart = chunk.index(after: newline)
                let line = try assembleLine(
                    firstSegment: chunk[lineStart..<lineEnd],
                    remainingSegments: boundarySegments,
                    lineAssemblyBytes: &lineAssemblyBytes
                )
                boundarySegments.removeAll(keepingCapacity: true)
                if let line, try handleLine(line) {
                    return Metrics(
                        fileBytesRead: fileBytesRead,
                        lineAssemblyBytes: lineAssemblyBytes
                    )
                }
                lineEnd = newline
            }

            let prefix = chunk[..<lineEnd]
            if foundNewline {
                boundarySegments.removeAll(keepingCapacity: true)
                if !prefix.isEmpty {
                    boundarySegments.append(prefix)
                }
            } else if !prefix.isEmpty {
                // Segments arrive from the end of the file. Appending keeps
                // this operation O(1); assembly restores file order once.
                boundarySegments.append(prefix)
            }
        }

        if let line = try assembleLine(
            firstSegment: Data(),
            remainingSegments: boundarySegments,
            lineAssemblyBytes: &lineAssemblyBytes
        ) {
            _ = try handleLine(line)
        }
        return Metrics(
            fileBytesRead: fileBytesRead,
            lineAssemblyBytes: lineAssemblyBytes
        )
    }

    private static func assembleLine(
        firstSegment: Data,
        remainingSegments: [Data],
        lineAssemblyBytes: inout UInt64
    ) throws -> Data? {
        let count = firstSegment.count + remainingSegments.reduce(0) { $0 + $1.count }
        guard count > 0 else { return nil }

        var line = Data()
        line.reserveCapacity(count)
        line.append(firstSegment)
        for segment in remainingSegments.reversed() {
            line.append(segment)
        }
        lineAssemblyBytes += UInt64(count)
        return line
    }
}
