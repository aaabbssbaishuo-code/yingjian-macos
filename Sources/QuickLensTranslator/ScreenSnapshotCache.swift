import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenSnapshotCache {
    private struct Frame {
        let capturedAt: Date
        let snapshots: [CGDirectDisplayID: ScreenSnapshot]
    }

    private let screenCaptureService = ScreenCaptureService()
    private var refreshTask: Task<Void, Never>?
    private var frames: [Frame] = []

    func start() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                do {
                    let snapshots = try await self.screenCaptureService.captureDisplaySnapshots()
                    self.appendFrame(Frame(capturedAt: Date(), snapshots: snapshots))
                    try? await Task.sleep(for: .milliseconds(350))
                } catch ScreenCaptureError.permissionDenied {
                    try? await Task.sleep(for: .seconds(2))
                } catch {
                    try? await Task.sleep(for: .milliseconds(900))
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        frames.removeAll()
    }

    func snapshots(maxAge: TimeInterval = 2.4, preferredMinimumAge: TimeInterval = 0.18) -> [CGDirectDisplayID: ScreenSnapshot] {
        let now = Date()
        let usableFrames = frames.filter {
            now.timeIntervalSince($0.capturedAt) <= maxAge
        }

        guard !usableFrames.isEmpty else {
            return [:]
        }

        let frameBeforeShortcut = usableFrames
            .filter { now.timeIntervalSince($0.capturedAt) >= preferredMinimumAge }
            .last

        return (frameBeforeShortcut ?? usableFrames.last)?.snapshots ?? [:]
    }

    private func appendFrame(_ frame: Frame) {
        frames.append(frame)
        if frames.count > 8 {
            frames.removeFirst(frames.count - 8)
        }
    }
}
