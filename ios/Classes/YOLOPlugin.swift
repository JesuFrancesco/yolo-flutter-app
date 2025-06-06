// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import Flutter
import UIKit

/// Class that manages YOLO models as a singleton instance
@MainActor
class SingleImageYOLO {
  static let shared = SingleImageYOLO()
  private var yolo: YOLO?
  private var isLoadingModel = false
  private var loadCompletionHandlers: [(Result<YOLO, Error>) -> Void] = []

  private init() {}

  func loadModel(
    modelName: String, task: YOLOTask, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    if yolo != nil {
      completion(.success(()))
      return
    }

    if isLoadingModel {
      loadCompletionHandlers.append({ result in
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      })
      return
    }

    isLoadingModel = true

    let resolvedModelPath = resolveModelPath(modelName)

    YOLO(resolvedModelPath, task: task) { [weak self] result in
      guard let self = self else { return }

      self.isLoadingModel = false

      switch result {
      case .success(let loadedYolo):
        self.yolo = loadedYolo
        completion(.success(()))

        for handler in self.loadCompletionHandlers {
          handler(.success(loadedYolo))
        }

      case .failure(let error):
        completion(.failure(error))

        for handler in self.loadCompletionHandlers {
          handler(.failure(error))
        }
      }

      self.loadCompletionHandlers.removeAll()
    }
  }

  private func resolveModelPath(_ modelPath: String) -> String {
    print("YOLOPlugin Debug: Resolving model path: \(modelPath)")

    if modelPath.hasPrefix("/") {
      print("YOLOPlugin Debug: Using absolute path: \(modelPath)")
      return modelPath
    }

    let fileManager = FileManager.default

    if modelPath.contains("/") {
      let components = modelPath.components(separatedBy: "/")
      let fileName = components.last ?? ""
      let fileNameWithoutExt = fileName.components(separatedBy: ".").first ?? fileName
      let directory = components.dropLast().joined(separator: "/")

      let searchPaths = [
        "flutter_assets/\(modelPath)",
        "flutter_assets/\(directory)",
        "flutter_assets",
        "",
      ]

      for searchPath in searchPaths {
        print("YOLOPlugin Debug: Searching in path: \(searchPath)")

        if !searchPath.isEmpty,
          let assetPath = Bundle.main.path(
            forResource: fileName, ofType: nil, inDirectory: searchPath)
        {
          print("YOLOPlugin Debug: Found at: \(assetPath)")
          return assetPath
        }

        if fileName.contains(".") {
          let fileComponents = fileName.components(separatedBy: ".")
          let name = fileComponents.dropLast().joined(separator: ".")
          let ext = fileComponents.last ?? ""

          if !searchPath.isEmpty,
            let assetPath = Bundle.main.path(
              forResource: name, ofType: ext, inDirectory: searchPath)
          {
            print("YOLOPlugin Debug: Found with ext at: \(assetPath)")
            return assetPath
          }
        }

        if !searchPath.isEmpty,
          let assetPath = Bundle.main.path(
            forResource: fileNameWithoutExt, ofType: nil, inDirectory: searchPath)
        {
          print("YOLOPlugin Debug: Found by filename only at: \(assetPath)")
          return assetPath
        }
      }

      for bundle in Bundle.allBundles {
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        print("YOLOPlugin Debug: Searching in bundle: \(bundleID)")

        if let assetPath = bundle.path(forResource: fileName, ofType: nil) {
          print("YOLOPlugin Debug: Found in bundle \(bundleID) at: \(assetPath)")
          return assetPath
        }

        if fileName.contains(".") {
          let fileComponents = fileName.components(separatedBy: ".")
          let name = fileComponents.dropLast().joined(separator: ".")
          let ext = fileComponents.last ?? ""

          if let assetPath = bundle.path(forResource: name, ofType: ext) {
            print("YOLOPlugin Debug: Found with ext in bundle \(bundleID) at: \(assetPath)")
            return assetPath
          }
        }

        if let assetPath = bundle.path(forResource: fileNameWithoutExt, ofType: nil) {
          print("YOLOPlugin Debug: Found by filename only in bundle \(bundleID) at: \(assetPath)")
          return assetPath
        }
      }

      let possiblePaths = [
        Bundle.main.bundlePath + "/flutter_assets/\(modelPath)",
        Bundle.main.bundlePath + "/flutter_assets/\(fileName)",
      ]

      for path in possiblePaths {
        if fileManager.fileExists(atPath: path) {
          print("YOLOPlugin Debug: Found in file system at: \(path)")
          return path
        }
      }
    } else {
      for bundle in Bundle.allBundles {
        let bundleID = bundle.bundleIdentifier ?? "unknown"

        if let path = bundle.path(forResource: modelPath, ofType: nil) {
          print("YOLOPlugin Debug: Found filename in bundle \(bundleID) at: \(path)")
          return path
        }

        if modelPath.contains(".") {
          let fileComponents = modelPath.components(separatedBy: ".")
          let name = fileComponents.dropLast().joined(separator: ".")
          let ext = fileComponents.last ?? ""

          if let path = bundle.path(forResource: name, ofType: ext) {
            print("YOLOPlugin Debug: Found with ext in bundle \(bundleID) at: \(path)")
            return path
          }
        }
      }

      if let path = Bundle.main.path(
        forResource: modelPath, ofType: nil, inDirectory: "flutter_assets")
      {
        print("YOLOPlugin Debug: Found in flutter_assets at: \(path)")
        return path
      }
    }

    print("YOLOPlugin Debug: Using original path: \(modelPath)")
    return modelPath
  }

  func predict(imageData: Data) -> [String: Any]? {
    guard let yolo = self.yolo, let uiImage = UIImage(data: imageData) else {
      return nil
    }

    let result = yolo(uiImage)

    return convertToFlutterFormat(result: result)
  }

  private func convertToFlutterFormat(result: YOLOResult) -> [String: Any] {
    var flutterResults: [[String: Any]] = []

    for box in result.boxes {
      var boxDict: [String: Any] = [
        "cls": box.cls,
        "confidence": box.conf,
        "index": box.index,
      ]

      boxDict["x"] = box.xywhn.minX
      boxDict["y"] = box.xywhn.minY
      boxDict["width"] = box.xywhn.width
      boxDict["height"] = box.xywhn.height

      boxDict["xImg"] = box.xywh.minX
      boxDict["yImg"] = box.xywh.minY
      boxDict["widthImg"] = box.xywh.width
      boxDict["heightImg"] = box.xywh.height

      boxDict["bbox"] = [box.xywh.minX, box.xywh.minY, box.xywh.width, box.xywh.height]

      flutterResults.append(boxDict)
    }

    var resultDict: [String: Any] = [
      "boxes": flutterResults
    ]

    if let annotatedImage = result.annotatedImage {
      if let imageData = annotatedImage.pngData() {
        resultDict["annotatedImage"] = FlutterStandardTypedData(bytes: imageData)
      }
    }

    return resultDict
  }
}

@MainActor
public class YOLOPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // 1) Register the platform view
    let factory = SwiftYOLOPlatformViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "com.ultralytics.yolo/YOLOPlatformView")

    // 2) Register the method channel for single-image inference
    let channel = FlutterMethodChannel(
      name: "yolo_single_image_channel",
      binaryMessenger: registrar.messenger()
    )
    let instance = YOLOPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private func checkModelExists(modelPath: String) -> [String: Any] {
    let fileManager = FileManager.default
    var resultMap: [String: Any] = [
      "exists": false,
      "path": modelPath,
      "location": "unknown",
    ]

    let lowercasedPath = modelPath.lowercased()

    if modelPath.hasPrefix("/") {
      if fileManager.fileExists(atPath: modelPath) {
        resultMap["exists"] = true
        resultMap["location"] = "file_system"
        resultMap["absolutePath"] = modelPath
        return resultMap
      }
    }

    if modelPath.contains("/") {
      let components = modelPath.components(separatedBy: "/")
      let fileName = components.last ?? ""
      let directory = components.dropLast().joined(separator: "/")

      let assetPath = "flutter_assets/\(directory)"
      if let fullPath = Bundle.main.path(forResource: fileName, ofType: nil, inDirectory: assetPath)
      {
        resultMap["exists"] = true
        resultMap["location"] = "flutter_assets_directory"
        resultMap["absolutePath"] = fullPath
        return resultMap
      }

      let fileComponents = fileName.components(separatedBy: ".")
      if fileComponents.count > 1 {
        let name = fileComponents.dropLast().joined(separator: ".")
        let ext = fileComponents.last ?? ""

        if let fullPath = Bundle.main.path(forResource: name, ofType: ext, inDirectory: assetPath) {
          resultMap["exists"] = true
          resultMap["location"] = "flutter_assets_directory_with_ext"
          resultMap["absolutePath"] = fullPath
          return resultMap
        }
      }
    }

    let fileName = modelPath.components(separatedBy: "/").last ?? modelPath
    if let fullPath = Bundle.main.path(
      forResource: fileName, ofType: nil, inDirectory: "flutter_assets")
    {
      resultMap["exists"] = true
      resultMap["location"] = "flutter_assets_root"
      resultMap["absolutePath"] = fullPath
      return resultMap
    }

    let fileComponents = fileName.components(separatedBy: ".")
    if fileComponents.count > 1 {
      let name = fileComponents.dropLast().joined(separator: ".")
      let ext = fileComponents.last ?? ""

      if let fullPath = Bundle.main.path(forResource: name, ofType: ext) {
        resultMap["exists"] = true
        resultMap["location"] = "bundle_resource"
        resultMap["absolutePath"] = fullPath
        return resultMap
      }
    }

    if let compiledURL = Bundle.main.url(forResource: fileName, withExtension: "mlmodelc") {
      resultMap["exists"] = true
      resultMap["location"] = "bundle_compiled"
      resultMap["absolutePath"] = compiledURL.path
      return resultMap
    }

    if let packageURL = Bundle.main.url(forResource: fileName, withExtension: "mlpackage") {
      resultMap["exists"] = true
      resultMap["location"] = "bundle_package"
      resultMap["absolutePath"] = packageURL.path
      return resultMap
    }

    return resultMap
  }

  private func getStoragePaths() -> [String: String?] {
    let fileManager = FileManager.default
    let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    let applicationSupportDirectory = fileManager.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first

    return [
      "internal": applicationSupportDirectory?.path,
      "cache": cachesDirectory?.path,
      "documents": documentsDirectory?.path,
    ]
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { @MainActor in
      switch call.method {
      case "loadModel":
        guard let args = call.arguments as? [String: Any],
          let modelPath = args["modelPath"] as? String,
          let taskString = args["task"] as? String
        else {
          result(
            FlutterError(code: "bad_args", message: "Invalid arguments for loadModel", details: nil)
          )
          return
        }

        let task = YOLOTask.fromString(taskString)

        do {
          try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            SingleImageYOLO.shared.loadModel(modelName: modelPath, task: task) { modelResult in
              switch modelResult {
              case .success:
                continuation.resume()
              case .failure(let error):
                continuation.resume(throwing: error)
              }
            }
          }
          result(nil)
        } catch {
          result(
            FlutterError(
              code: "model_load_error", message: error.localizedDescription, details: nil))
        }

      case "predictSingleImage":
        guard let args = call.arguments as? [String: Any],
          let data = args["image"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: "bad_args", message: "Invalid arguments for predictSingleImage", details: nil))
          return
        }

        if let resultDict = SingleImageYOLO.shared.predict(imageData: data.data) {
          result(resultDict)
        } else {
          result(
            FlutterError(code: "inference_error", message: "Failed to run inference", details: nil))
        }

      case "checkModelExists":
        guard let args = call.arguments as? [String: Any],
          let modelPath = args["modelPath"] as? String
        else {
          result(
            FlutterError(
              code: "bad_args", message: "Invalid arguments for checkModelExists", details: nil))
          return
        }

        let checkResult = checkModelExists(modelPath: modelPath)
        result(checkResult)

      case "getStoragePaths":
        let paths = getStoragePaths()
        result(paths)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
