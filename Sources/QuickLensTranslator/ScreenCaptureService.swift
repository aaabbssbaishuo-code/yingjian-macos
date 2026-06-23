import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: Error {
    case permissionDenied
    case displayNotFound
    case invalidImage
}

struct ScreenCaptureService {
    func captureDisplaySnapshots() async throws -> [CGDirectDisplayID: ScreenSnapshot] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ScreenCaptureError.permissionDenied
        }

        var snapshots: [CGDirectDisplayID: ScreenSnapshot] = [:]
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                continue
            }

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(
                x: 0,
                y: 0,
                width: display.width,
                height: display.height
            )
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            snapshots[displayID] = ScreenSnapshot(screen: screen, image: image)
        }

        return snapshots
    }

    func capture(rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ScreenCaptureError.permissionDenied
        }

        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }

        let scale = CGFloat(display.width) / screen.frame.width
        let localRect = CGRect(
            x: (rect.minX - screen.frame.minX) * scale,
            y: (screen.frame.maxY - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = max(1, Int(localRect.width))
        configuration.height = max(1, Int(localRect.height))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}
