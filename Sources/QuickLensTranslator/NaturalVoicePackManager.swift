import Combine
import CryptoKit
import Foundation

struct NaturalVoiceModelFiles: Hashable, Sendable {
    let model: URL
    let voices: URL
    let tokens: URL
    let dataDirectory: URL
    let dictionaryDirectory: URL?
    let lexicon: URL
}

@MainActor
final class NaturalVoicePackManager: ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case downloading(Double)
        case verifying
        case installing
        case installed
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .verifying, .installing:
                return true
            default:
                return false
            }
        }
    }

    static let standard = NaturalVoicePackManager()
    static let archiveSize: Int64 = 131_839_838
    static let archiveSizeText = "约 132 MB"

    @Published private(set) var status: Status

    private static let archiveURL = URL(
        string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2"
    )!
    nonisolated private static let expectedSHA256 = "75654a84864be26f345f020f4070c2c019e96dd1b7f9bf6e2ffd59efac6aa5a3"
    nonisolated private static let packFolderName = "kokoro-int8-multi-lang-v1_0"

    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: NaturalVoicePackDownloadDelegate?
    private var downloadSession: URLSession?
    private var installTask: Task<Void, Never>?

    private init() {
        status = Self.findModelFiles(in: Self.installDirectory) == nil
            ? .notInstalled
            : .installed
    }

    var modelFiles: NaturalVoiceModelFiles? {
        Self.findModelFiles(in: Self.installDirectory)
    }

    func install() {
        guard !status.isBusy else { return }

        do {
            try FileManager.default.createDirectory(
                at: Self.downloadDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            status = .failed("无法创建语音包目录。")
            return
        }

        let archive = Self.downloadDirectory.appendingPathComponent(
            "\(Self.packFolderName).tar.bz2"
        )
        let delegate = NaturalVoicePackDownloadDelegate(destinationURL: archive)
        delegate.onProgress = { [weak self] progress in
            Task { @MainActor in
                self?.status = .downloading(progress)
            }
        }
        delegate.onCompletion = { [weak self] result in
            Task { @MainActor in
                self?.downloadDidFinish(result)
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )

        downloadDelegate = delegate
        downloadSession = session
        status = .downloading(0)
        let task = session.downloadTask(with: Self.archiveURL)
        downloadTask = task
        task.resume()
    }

    func cancelInstall() {
        downloadTask?.cancel()
        installTask?.cancel()
        finishDownloadSession()
        status = modelFiles == nil ? .notInstalled : .installed
    }

    func removePack() {
        cancelInstall()
        do {
            if FileManager.default.fileExists(atPath: Self.installDirectory.path) {
                try FileManager.default.removeItem(at: Self.installDirectory)
            }
            status = .notInstalled
        } catch {
            status = .failed("无法删除自然语音包。")
        }
    }

    func refreshStatus() {
        guard !status.isBusy else { return }
        status = modelFiles == nil ? .notInstalled : .installed
    }

    private func downloadDidFinish(_ result: Result<URL, Error>) {
        downloadTask = nil
        finishDownloadSession()

        switch result {
        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                status = modelFiles == nil ? .notInstalled : .installed
            } else {
                status = .failed("自然语音包下载失败，请检查网络后重试。")
            }
        case .success(let archive):
            status = .verifying
            installTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Self.verifyAndInstall(archive: archive) { progress in
                        await MainActor.run {
                            self.status = progress
                        }
                    }
                    guard !Task.isCancelled else { return }
                    self.status = .installed
                } catch is CancellationError {
                    self.status = self.modelFiles == nil ? .notInstalled : .installed
                } catch {
                    self.status = .failed(error.localizedDescription)
                }
                self.installTask = nil
            }
        }
    }

    private func finishDownloadSession() {
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        downloadDelegate = nil
    }

    nonisolated private static func verifyAndInstall(
        archive: URL,
        onProgress: @escaping @Sendable (Status) async -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: archive, options: .mappedIfSafe)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expectedSHA256 else {
                throw NaturalVoicePackError.checksumMismatch
            }

            try Task.checkCancellation()
            await onProgress(.installing)

            let staging = voicePackRoot.appendingPathComponent(
                "installing-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: staging,
                withIntermediateDirectories: true
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xjf", archive.path, "-C", staging.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NaturalVoicePackError.extractionFailed
            }
            try Task.checkCancellation()

            guard findModelFiles(in: staging) != nil else {
                throw NaturalVoicePackError.invalidContents
            }
            if FileManager.default.fileExists(atPath: installDirectory.path) {
                try FileManager.default.removeItem(at: installDirectory)
            }
            try FileManager.default.moveItem(at: staging, to: installDirectory)
            if FileManager.default.fileExists(atPath: archive.path) {
                try FileManager.default.removeItem(at: archive)
            }
        }.value
    }

    nonisolated private static var voicePackRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yingjian", isDirectory: true)
            .appendingPathComponent("VoicePacks", isDirectory: true)
    }

    nonisolated private static var downloadDirectory: URL {
        voicePackRoot.appendingPathComponent("Downloads", isDirectory: true)
    }

    nonisolated private static var installDirectory: URL {
        voicePackRoot.appendingPathComponent(packFolderName, isDirectory: true)
    }

    nonisolated private static func findModelFiles(in root: URL) -> NaturalVoiceModelFiles? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var model: URL?
        var voices: URL?
        var tokens: URL?
        var dataDirectory: URL?
        var dictionaryDirectory: URL?
        var lexicon: URL?

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if url.pathExtension == "onnx",
               name.localizedCaseInsensitiveContains("model") {
                if model == nil || name.localizedCaseInsensitiveContains("int8") {
                    model = url
                }
            } else if name == "voices.bin" {
                voices = url
            } else if name == "tokens.txt" {
                tokens = url
            } else if name == "espeak-ng-data" {
                dataDirectory = url
            } else if name == "dict" {
                dictionaryDirectory = url
            } else if name == "lexicon-us-en.txt" {
                lexicon = url
            }
        }

        guard let model, let voices, let tokens, let dataDirectory, let lexicon else {
            return nil
        }
        return NaturalVoiceModelFiles(
            model: model,
            voices: voices,
            tokens: tokens,
            dataDirectory: dataDirectory,
            dictionaryDirectory: dictionaryDirectory,
            lexicon: lexicon
        )
    }
}

private enum NaturalVoicePackError: LocalizedError {
    case checksumMismatch
    case extractionFailed
    case invalidContents

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "自然语音包校验失败，请重新下载。"
        case .extractionFailed:
            return "自然语音包解压失败。"
        case .invalidContents:
            return "自然语音包内容不完整。"
        }
    }
}

private final class NaturalVoicePackDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destinationURL: URL
    var onProgress: ((Double) -> Void)?
    var onCompletion: ((Result<URL, Error>) -> Void)?
    private var completed = false

    init(destinationURL: URL) {
        self.destinationURL = destinationURL
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            completed = true
            onCompletion?(.success(destinationURL))
        } catch {
            completed = true
            onCompletion?(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !completed, let error else { return }
        completed = true
        onCompletion?(.failure(error))
    }
}
