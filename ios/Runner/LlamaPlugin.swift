import Flutter
import Foundation

// MARK: - LlamaPlugin

/// Flutter plugin host.
///
/// Method channel  : "atlas.llama"
///   loadModel(path: String)           → ["loaded": true, "nCtx": Int]
///   unloadModel()                     → nil
///   generate(prompt, maxTokens, temp) → nil  (tokens arrive via EventChannel)
///   cancel()                          → nil
///   modelExists(path: String)         → Bool
///   downloadProgress(modelId: String) → Double  (0.0–1.0, -1 if not downloading)
///
/// Event channel   : "atlas.llama.stream"
///   Emits String tokens during generation.
///   Emits ["done": true] map when generation completes.
///   Emits ["error": String] map on failure.
final class LlamaPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // ── Channels ─────────────────────────────────────────────────────────────
    static let methodChannelName = "atlas.llama"
    static let eventChannelName  = "atlas.llama.stream"

    private var eventSink: FlutterEventSink?
    private let context = LlamaContext()
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadProgress: [String: Double] = [:]

    // ── FlutterPlugin registration ────────────────────────────────────────────

    static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()

        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: messenger
        )

        let instance = LlamaPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // ── Method calls ──────────────────────────────────────────────────────────

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "loadModel":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "ARGS", message: "Missing 'path'", details: nil))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    let nCtx = try self.context.loadModel(path: path)
                    DispatchQueue.main.async {
                        result(["loaded": true, "nCtx": nCtx])
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LOAD", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "unloadModel":
            context.unloadModel()
            result(nil)

        case "generate":
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                result(FlutterError(code: "ARGS", message: "Missing 'prompt'", details: nil))
                return
            }
            let maxTokens  = args["maxTokens"]   as? Int    ?? 2048
            let temperature = args["temperature"] as? Double ?? 0.2

            context.generate(
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: Float(temperature),
                onToken: { [weak self] token in
                    DispatchQueue.main.async {
                        self?.eventSink?(token)
                    }
                    return true   // continue
                },
                onComplete: { [weak self] error in
                    DispatchQueue.main.async {
                        if let error {
                            self?.eventSink?(["error": error.localizedDescription])
                        } else {
                            self?.eventSink?(["done": true])
                        }
                    }
                }
            )
            result(nil)    // generation is async; tokens come via EventChannel

        case "cancel":
            context.cancel()
            result(nil)

        case "modelExists":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(false); return
            }
            result(FileManager.default.fileExists(atPath: path))

        case "downloadModel":
            guard let args = call.arguments as? [String: Any],
                  let modelId  = args["modelId"]  as? String,
                  let urlStr   = args["url"]       as? String,
                  let destPath = args["destPath"]  as? String,
                  let url = URL(string: urlStr) else {
                result(FlutterError(code: "ARGS", message: "Missing download args", details: nil))
                return
            }
            startDownload(modelId: modelId, url: url, destPath: destPath, result: result)

        case "getDownloadProgress":
            guard let args = call.arguments as? [String: Any],
                  let modelId = args["modelId"] as? String else {
                result(-1.0); return
            }
            result(downloadProgress[modelId] ?? -1.0)

        case "cancelDownload":
            guard let args = call.arguments as? [String: Any],
                  let modelId = args["modelId"] as? String else {
                result(nil); return
            }
            downloadTasks[modelId]?.cancel()
            downloadTasks.removeValue(forKey: modelId)
            downloadProgress.removeValue(forKey: modelId)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Download helper ───────────────────────────────────────────────────────

    private func startDownload(modelId: String, url: URL, destPath: String, result: @escaping FlutterResult) {
        downloadProgress[modelId] = 0.0

        let session = URLSession(
            configuration: .default,
            delegate: DownloadDelegate(
                modelId: modelId,
                destPath: destPath,
                onProgress: { [weak self] progress in
                    self?.downloadProgress[modelId] = progress
                    DispatchQueue.main.async {
                        self?.eventSink?(["downloadProgress": progress, "modelId": modelId])
                    }
                },
                onComplete: { [weak self] error in
                    self?.downloadTasks.removeValue(forKey: modelId)
                    if let error {
                        self?.downloadProgress[modelId] = -1.0
                        DispatchQueue.main.async {
                            self?.eventSink?(["downloadError": error.localizedDescription, "modelId": modelId])
                        }
                    } else {
                        self?.downloadProgress[modelId] = 1.0
                        DispatchQueue.main.async {
                            self?.eventSink?(["downloadComplete": true, "modelId": modelId])
                        }
                    }
                }
            ),
            delegateQueue: nil
        )

        let task = session.downloadTask(with: url)
        downloadTasks[modelId] = task
        task.resume()
        result(nil)
    }

    // ── FlutterStreamHandler ──────────────────────────────────────────────────

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        context.cancel()
        eventSink = nil
        return nil
    }
}

// MARK: - DownloadDelegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let modelId: String
    let destPath: String
    let onProgress: (Double) -> Void
    let onComplete: (Error?) -> Void

    init(modelId: String, destPath: String, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.modelId    = modelId
        self.destPath   = destPath
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let dest = URL(fileURLWithPath: destPath)
        do {
            let dir = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destPath) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            onComplete(nil)
        } catch {
            onComplete(error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onComplete(error) }
    }
}
