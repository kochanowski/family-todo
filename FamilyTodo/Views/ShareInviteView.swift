import CloudKit
import SwiftUI
import UIKit

struct ShareInviteView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_: UICloudSharingController, context _: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: ShareInviteView

        init(parent: ShareInviteView) {
            self.parent = parent
        }

        func cloudSharingController(_: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error)")
            _Concurrency.Task { @MainActor in
                CloudKitDiagnosticsState.shared.record(
                    error: error,
                    operation: "UICloudSharingController.failedToSaveShare"
                )
            }
        }

        func itemTitle(for _: UICloudSharingController) -> String? {
            CloudKitManager.sanitizeShareTitle(
                parent.share[CKShare.SystemFieldKey.title] as? String
            )
        }

        // Optional: specific thumbnail
        // func itemThumbnailData(for csc: UICloudSharingController) -> Data? { ... }
    }
}
