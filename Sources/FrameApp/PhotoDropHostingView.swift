import AppKit
import SwiftUI

/// A native drop destination is needed for NSFilePromiseReceiver (Photos/Mail).
/// SwiftUI's file-URL-only onDrop cannot receive these asynchronous transfers.
@MainActor
final class PhotoDropHostingView<Content: View>: NSHostingView<Content> {
    private let model: StudioModel

    init(rootView: Content, model: StudioModel) {
        self.model = model
        super.init(rootView: rootView)
        registerForDraggedTypes(PhotoDropImporter.draggedTypes)
    }

    @available(*, unavailable)
    required init(rootView: Content) { fatalError() }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { model.dropTargeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { model.dropTargeted = false }

    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = model.canReceiveDrop(sender.draggingPasteboard)
        if model.dropTargeted != accepts { model.dropTargeted = accepts }
        return accepts ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.canReceiveDrop(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.dropTargeted = false
        return model.receiveDrop(sender.draggingPasteboard)
    }
}
