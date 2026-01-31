import CloudKit
import SwiftUI
import UIKit

struct ShareInviteView: UIViewControllerRepresentable {
    @EnvironmentObject private var householdStore: HouseholdStore
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UICloudSharingController {
        // We assume householdStore has a prepared share or we create one
        // For simplicity, we trigger share creation if needed in coordination
        // But UICloudSharingController needs a share or a record to share.
        
        // Strategy:
        // 1. If share exists, use it.
        // 2. If not, we need a record to share.
        
        // This view should probably be presented AFTER we have the share/record ready
        // But let's try to handle it.
        
        if let share = householdStore.share {
            let controller = UICloudSharingController(share: share, container: CKContainer.default())
            controller.delegate = context.coordinator
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            return controller
        } else {
            // Sharing a new record (the household)
            // We need the household record. HouseholdStore should provide it.
            // But UICloudSharingController(preparationHandler:) is async...
            
            let controller = UICloudSharingController { controller, completion in
                Task {
                    do {
                        let (share, container) = try await householdStore.createShare()
                        completion(share, container, nil)
                    } catch {
                        completion(nil, nil, error)
                    }
                }
            }
            controller.delegate = context.coordinator
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            return controller
        }
    }
    
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
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
        
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error)")
        }
        
        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.householdStore.currentHousehold?.name ?? "Household"
        }
        
        // Optional: specific thumbnail
        // func itemThumbnailData(for csc: UICloudSharingController) -> Data? { ... }
    }
}
