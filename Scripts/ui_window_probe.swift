import CoreGraphics
import Foundation
import ImageIO
import Vision

enum ProbeError: Error {
    case invalidArguments
    case windowNotFound
    case imageLoadFailed
}

struct WindowMatch {
    let windowID: Int
    let layer: Int
    let bounds: CGRect
    let ownerName: String
    let windowName: String
}

private func loadWindows(for pid: pid_t, preferredTitle: String) throws -> WindowMatch {
    guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        throw ProbeError.windowNotFound
    }

    let matches = rawList.compactMap { entry -> WindowMatch? in
        guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int, ownerPID == Int(pid) else {
            return nil
        }

        let windowID = entry[kCGWindowNumber as String] as? Int ?? 0
        let layer = entry[kCGWindowLayer as String] as? Int ?? 0
        let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
        let windowName = entry[kCGWindowName as String] as? String ?? ""

        guard let rawBounds = entry[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        let boundsDictionary = rawBounds
        guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        return WindowMatch(
            windowID: windowID,
            layer: layer,
            bounds: bounds,
            ownerName: ownerName,
            windowName: windowName
        )
    }

    let ordered = matches.sorted { lhs, rhs in
        let lhsArea = lhs.bounds.width * lhs.bounds.height
        let rhsArea = rhs.bounds.width * rhs.bounds.height
        return lhsArea > rhsArea
    }

    if let exactTitle = ordered.first(where: { $0.windowName == preferredTitle }) {
        return exactTitle
    }

    if let first = ordered.first {
        return first
    }

    throw ProbeError.windowNotFound
}

private func recognizeText(at path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard
        let source = CGImageSourceCreateWithURL(url, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ProbeError.imageLoadFailed
    }

    let width = image.width
    let height = image.height

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "en-US"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    let rows = (request.results ?? []).compactMap { observation -> (Int, Int, Int, Int, String)? in
        guard let top = observation.topCandidates(1).first else {
            return nil
        }

        let box = observation.boundingBox
        let x = Int(box.minX * CGFloat(width))
        let y = Int((1.0 - box.maxY) * CGFloat(height))
        let w = Int(box.width * CGFloat(width))
        let h = Int(box.height * CGFloat(height))
        return (x, y, w, h, top.string)
    }
    .sorted { lhs, rhs in
        if abs(lhs.1 - rhs.1) > 10 {
            return lhs.1 < rhs.1
        }
        return lhs.0 < rhs.0
    }

    print("IMAGE\t\(width)\t\(height)")
    for row in rows {
        print("\(row.0)\t\(row.1)\t\(row.2)\t\(row.3)\t\(row.4)")
    }
}

private func printWindowInfo(for pid: pid_t, preferredTitle: String) throws {
    let match = try loadWindows(for: pid, preferredTitle: preferredTitle)
    let x = Int(match.bounds.origin.x.rounded())
    let y = Int(match.bounds.origin.y.rounded())
    let width = Int(match.bounds.width.rounded())
    let height = Int(match.bounds.height.rounded())
    print("\(match.windowID)\t\(x)\t\(y)\t\(width)\t\(height)\t\(match.layer)\t\(match.ownerName)\t\(match.windowName)")
}

let arguments = CommandLine.arguments

do {
    if arguments.count >= 2, arguments[1] == "ocr" {
        guard arguments.count == 3 else {
            throw ProbeError.invalidArguments
        }
        try recognizeText(at: arguments[2])
    } else {
        guard arguments.count == 3, let pid = Int32(arguments[1]) else {
            throw ProbeError.invalidArguments
        }
        try printWindowInfo(for: pid, preferredTitle: arguments[2])
    }
} catch ProbeError.invalidArguments {
    fputs("usage: ui_window_probe.swift <pid> <preferred-title>\n", stderr)
    fputs("   or: ui_window_probe.swift ocr <image-path>\n", stderr)
    exit(64)
} catch ProbeError.windowNotFound {
    exit(2)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
