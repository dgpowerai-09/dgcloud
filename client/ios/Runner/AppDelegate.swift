import Flutter
import UIKit
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let mediaChannelName = "com.dgcloud/ios_media"
  private var activePickerCoordinator: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerMediaChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerMediaChannel() {
    let messenger: FlutterBinaryMessenger?
    if let controller = window?.rootViewController as? FlutterViewController {
      messenger = controller.binaryMessenger
    } else if let registrar = self.registrar(forPlugin: "DgCloudIosMedia") {
      messenger = registrar.messenger()
    } else {
      messenger = nil
    }

    guard let binaryMessenger = messenger else { return }
    let channel = FlutterMethodChannel(
      name: Self.mediaChannelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMediaMethodCall(call, result: result)
    }
  }

  private func handleMediaMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickOriginalMedia":
      presentOriginalMediaPicker(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentOriginalMediaPicker(result: @escaping FlutterResult) {
    #if canImport(PhotosUI)
    if #available(iOS 14.0, *) {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else {
          result([])
          return
        }
        guard let presenter = self.topPresentingViewController() else {
          result(
            FlutterError(
              code: "NO_VIEW_CONTROLLER",
              message: "Unable to find active view controller to present media picker.",
              details: nil
            )
          )
          return
        }

        let coordinator = IosRawMediaPickerCoordinator { [weak self] paths in
          self?.activePickerCoordinator = nil
          result(paths)
        }
        self.activePickerCoordinator = coordinator
        coordinator.present(from: presenter)
      }
      return
    }
    #endif

    result(
      FlutterError(
        code: "UNSUPPORTED_IOS_VERSION",
        message: "Original HEIC photo library picker requires iOS 14.0 or newer.",
        details: nil
      )
    )
  }

  private func topPresentingViewController() -> UIViewController? {
    var root: UIViewController? = window?.rootViewController
    if root == nil {
      if #available(iOS 13.0, *) {
        root = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first(where: { $0.isKeyWindow })?.rootViewController
      }
    }
    while let presented = root?.presentedViewController {
      root = presented
    }
    return root
  }
}

#if canImport(PhotosUI)
@available(iOS 14.0, *)
private final class IosRawMediaPickerCoordinator: NSObject,
  PHPickerViewControllerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private static let knownMediaExtensions: Set<String> = [
    "heic", "heif", "hif", "jpg", "jpeg", "png", "gif", "webp",
    "dng", "raw", "arw", "cr2", "cr3", "nef", "orf", "rw2",
    "mov", "mp4", "m4v"
  ]

  private let completion: ([String]) -> Void
  private let stateLock = NSLock()
  private var hasStartedProcessing = false
  private var hasFinished = false

  init(completion: @escaping ([String]) -> Void) {
    self.completion = completion
    super.init()
  }

  func present(from presenter: UIViewController) {
    var config = PHPickerConfiguration()
    config.selectionLimit = 0
    config.filter = .any(of: [.images, .videos])
    // Preserve exact original HEIC/HEIF/ProRAW/MOV bytes instead of JPEG/H.264 transcoding.
    config.preferredAssetRepresentationMode = .current

    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    picker.presentationController?.delegate = self
    presenter.present(picker, animated: true)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    stateLock.lock()
    let shouldCancel = !hasStartedProcessing
    stateLock.unlock()
    if shouldCancel {
      finishOnce(with: [])
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    stateLock.lock()
    hasStartedProcessing = true
    stateLock.unlock()

    picker.dismiss(animated: true)

    if results.isEmpty {
      finishOnce(with: [])
      return
    }

    let baseCacheDir =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let batchDir = baseCacheDir
      .appendingPathComponent("dg_raw_picks", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    do {
      try FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
    } catch {
      finishOnce(with: [])
      return
    }

    let group = DispatchGroup()
    let pathsLock = NSLock()
    var indexedPaths = [Int: String]()

    for (index, result) in results.enumerated() {
      let provider = result.itemProvider
      guard let typeId = Self.resolvePreferredTypeIdentifier(for: provider) else {
        continue
      }

      group.enter()
      provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, error in
        defer { group.leave() }
        guard let sourceURL = url, error == nil else {
          return
        }

        let destinationName = Self.buildOutputFilename(
          sourceURL: sourceURL,
          suggestedName: provider.suggestedName,
          typeIdentifier: typeId,
          fallbackIndex: index + 1
        )
        let itemDir = batchDir.appendingPathComponent(String(index), isDirectory: true)
        let destURL = itemDir.appendingPathComponent(destinationName)

        do {
          try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
          if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
          }
          // Copy synchronously inside closure before iOS deletes the ephemeral URL.
          try FileManager.default.copyItem(at: sourceURL, to: destURL)

          pathsLock.lock()
          indexedPaths[index] = destURL.path
          pathsLock.unlock()
        } catch {
          return
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      pathsLock.lock()
      let orderedPaths = (0..<results.count).compactMap { indexedPaths[$0] }
      pathsLock.unlock()
      self?.finishOnce(with: orderedPaths)
    }
  }

  private func finishOnce(with paths: [String]) {
    stateLock.lock()
    if hasFinished {
      stateLock.unlock()
      return
    }
    hasFinished = true
    stateLock.unlock()

    DispatchQueue.main.async {
      self.completion(paths)
    }
  }

  private static func resolvePreferredTypeIdentifier(for provider: NSItemProvider) -> String? {
    let registered = provider.registeredTypeIdentifiers
    let heicTypes = ["public.heic", "public.heif", "public.heif-standard"]

    #if canImport(UniformTypeIdentifiers)
    if let rawType = registered.first(where: { UTType($0)?.conforms(to: .rawImage) == true }) {
      return rawType
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.rawImage.identifier) {
      return UTType.rawImage.identifier
    }
    #else
    if provider.hasItemConformingToTypeIdentifier("public.camera-raw-image") {
      return "public.camera-raw-image"
    }
    #endif

    for uti in heicTypes {
      if registered.contains(uti) || provider.hasItemConformingToTypeIdentifier(uti) {
        return uti
      }
    }

    #if canImport(UniformTypeIdentifiers)
    if let movieType = registered.first(where: { UTType($0)?.conforms(to: .movie) == true }) {
      return movieType
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
      return UTType.movie.identifier
    }
    if let imageType = registered.first(where: { UTType($0)?.conforms(to: .image) == true }) {
      return imageType
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
      return UTType.image.identifier
    }
    #else
    if provider.hasItemConformingToTypeIdentifier("public.movie") {
      return "public.movie"
    }
    if provider.hasItemConformingToTypeIdentifier("public.image") {
      return "public.image"
    }
    #endif

    return registered.first
  }

  private static func buildOutputFilename(
    sourceURL: URL,
    suggestedName: String?,
    typeIdentifier: String,
    fallbackIndex: Int
  ) -> String {
    let rawExt = sourceURL.pathExtension.isEmpty
      ? fallbackExtension(forTypeIdentifier: typeIdentifier)
      : sourceURL.pathExtension
    let urlBase = (sourceURL.lastPathComponent as NSString).deletingPathExtension
    let trimmedSuggestion = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var baseName = trimmedSuggestion.isEmpty ? urlBase : trimmedSuggestion

    let existingExt = (baseName as NSString).pathExtension.lowercased()
    if !existingExt.isEmpty && knownMediaExtensions.contains(existingExt) {
      baseName = (baseName as NSString).deletingPathExtension
    }

    let safeBase = sanitizeFileComponent(baseName.isEmpty ? "media_\(fallbackIndex)" : baseName)
    return rawExt.isEmpty ? safeBase : "\(safeBase).\(rawExt)"
  }

  private static func sanitizeFileComponent(_ value: String) -> String {
    let cleaned = value
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
      .replacingOccurrences(of: "\\", with: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "media_file" : cleaned
  }

  private static func fallbackExtension(forTypeIdentifier typeIdentifier: String) -> String {
    #if canImport(UniformTypeIdentifiers)
    if let ext = UTType(typeIdentifier)?.preferredFilenameExtension, !ext.isEmpty {
      return ext
    }
    #endif
    switch typeIdentifier {
    case "public.heic":
      return "heic"
    case "public.heif", "public.heif-standard":
      return "heif"
    case "public.jpeg":
      return "jpg"
    case "public.png":
      return "png"
    default:
      return "bin"
    }
  }
}
#endif
