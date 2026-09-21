import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// Picks one image from the photo library.
///
/// Uses `PHPickerViewController`, which runs out of process and needs no library
/// permission at all — the traveller chooses a picture and only that picture is
/// handed over.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
  var onPicked: (Data) -> Void
  var onFailed: (String) -> Void

  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 1

    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    private let parent: PhotoLibraryPicker

    init(_ parent: PhotoLibraryPicker) {
      self.parent = parent
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      parent.dismiss()
      guard let provider = results.first?.itemProvider else { return }

      provider.loadObject(ofClass: UIImage.self) { object, _ in
        DispatchQueue.main.async {
          guard
            let image = object as? UIImage,
            let data = image.jpegData(compressionQuality: 0.9)
          else {
            self.parent.onFailed("That photo could not be read. Your words are still here.")
            return
          }
          self.parent.onPicked(data)
        }
      }
    }
  }
}

/// Takes a photo with the camera.
struct CameraPicker: UIViewControllerRepresentable {
  var onPicked: (Data) -> Void

  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate
  {
    private let parent: CameraPicker

    init(_ parent: CameraPicker) {
      self.parent = parent
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage,
        let data = image.jpegData(compressionQuality: 0.9)
      {
        parent.onPicked(data)
      }
      parent.dismiss()
    }
  }
}

/// Asks for camera access, once, at the moment the traveller taps the camera.
enum CameraAccess {
  enum Outcome {
    case granted
    case denied
    case unavailable
  }

  /// Main-actor bound because asking UIKit whether a camera exists is a UI query.
  @MainActor
  static func request() async -> Outcome {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return .granted
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
    case .denied, .restricted:
      return .denied
    @unknown default:
      return .denied
    }
  }
}

/// The system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Something to share, wrapped so it can drive a `sheet(item:)`.
struct SharePayload: Identifiable {
  let id = UUID()
  let items: [Any]
}
