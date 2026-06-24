import AppKit
import CoreGraphics

@MainActor
final class CaptureCoordinator {
    private let overlayController = ScreenshotOverlayController()
    private let screenCaptureService = ScreenCaptureService()
    private let ocrService = OCRService()
    private let floatingPanel = FloatingTranslationPanel()

    private(set) var isCapturing = false

    func start() {
        guard !isCapturing else { return }

        isCapturing = true
        floatingPanel.dismiss()

        Task { [weak self] in
            guard let self else { return }

            let snapshots: [CGDirectDisplayID: ScreenSnapshot]
            do {
                snapshots = try await screenCaptureService.captureDisplaySnapshots()
            } catch {
                snapshots = [:]
            }

            self.overlayController.beginSelection(snapshots: snapshots) { [weak self] result in
                guard let self else { return }

                switch result {
                case .cancelled:
                    self.isCapturing = false
                case .tooSmall:
                    self.isCapturing = false
                    ToastPresenter.show(message: "选区过小，请重新选择。")
                case .selected(let rect, let screen, let snapshotImage):
                    Task {
                        await self.processSelection(rect, on: screen, snapshotImage: snapshotImage)
                    }
                }
            }
        }
    }

    private func processSelection(_ rect: CGRect, on screen: NSScreen, snapshotImage: CGImage?) async {
        defer { isCapturing = false }

        do {
            try await Task.sleep(for: .milliseconds(120))
            let image: CGImage
            if let snapshotImage {
                image = snapshotImage
            } else {
                image = try await screenCaptureService.capture(rect: rect, on: screen)
            }
            let result = try await ocrService.recognizeEnglish(in: image)

            guard !result.paragraphs.isEmpty else {
                ToastPresenter.show(message: "未识别到英文内容。")
                return
            }

            floatingPanel.present(
                paragraphs: result.paragraphs,
                near: rect,
                on: screen
            )
        } catch ScreenCaptureError.permissionDenied {
            PermissionManager.requestScreenCapturePermission()
        } catch {
            ToastPresenter.show(message: "截图或文字识别失败，请稍后重试。")
        }
    }
}
