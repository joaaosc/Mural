import Foundation

extension BoardWorkspaceState {
    /// Valida o estado sem permitir que uma navegação de outro mural seja mantida.
    public func canonicalized(for board: Board) -> WorkspaceValidationResult {
        var canonical = self
        var issues: [WorkspaceValidationIssue] = []

        if !canonical.canvas.confirmedZoom.isFinite {
            canonical.canvas.confirmedZoom = CanvasWorkspaceState.defaultZoom
            issues.append(.nonFiniteZoom)
        } else {
            let clamped = min(
                max(canonical.canvas.confirmedZoom, CanvasWorkspaceState.zoomRange.lowerBound), CanvasWorkspaceState.zoomRange.upperBound)
            if clamped != canonical.canvas.confirmedZoom {
                canonical.canvas.confirmedZoom = clamped
                issues.append(.zoomClamped)
            }
        }

        if case .logicalCenter(let point) = canonical.canvas.anchor,
            !point.x.isFinite || !point.y.isFinite
        {
            canonical.canvas.anchor = .origin
            issues.append(.nonFiniteCanvasCenter)
        }

        var validPath: [WorkspaceDestination] = []
        var seen = Set<UUID>()
        for (index, destination) in canonical.path.enumerated() {
            guard index < 2 else {
                issues.append(.pathTruncated(index: index))
                break
            }
            let id: UUID
            switch destination {
            case .collection(let collectionID): id = collectionID
            case .item(let itemID): id = itemID
            }
            guard seen.insert(id).inserted else {
                issues.append(.repeatedPathID(id))
                issues.append(.pathTruncated(index: index))
                break
            }
            guard isValid(destination: destination, at: index, path: validPath, board: board) else {
                issues.append(.invalidPath(index: index))
                issues.append(.pathTruncated(index: index))
                break
            }
            validPath.append(destination)
        }
        canonical.path = validPath

        if let filter = canonical.filter {
            let filterIsValid: Bool
            switch canonical.path.count {
            case 0: filterIsValid = true
            case 1: filterIsValid = filter != .folders
            default: filterIsValid = false
            }
            if !filterIsValid {
                canonical.filter = nil
                issues.append(.invalidFilter)
            }
        }

        var validPositions: [UUID: ReadingPosition] = [:]
        for (key, position) in canonical.readingPositions {
            guard key == position.targetItemID,
                isValid(position: position, board: board)
            else {
                issues.append(.removedReadingPosition(key))
                continue
            }
            validPositions[key] = position
        }
        canonical.readingPositions = validPositions
        return WorkspaceValidationResult(state: canonical, issues: issues)
    }

    public func validated(for board: Board) -> BoardWorkspaceState {
        canonicalized(for: board).state
    }

    private func isValid(
        destination: WorkspaceDestination,
        at index: Int,
        path: [WorkspaceDestination],
        board: Board
    ) -> Bool {
        guard let id = destination.id, let item = board.item(id: id) else { return false }
        switch (index, destination) {
        case (0, .collection(_)):
            return item.kind == .folder && item.parentID == nil
        case (0, .item(_)):
            return item.kind != .folder && item.parentID == nil
        case (1, .item(_)):
            guard case .collection(let parentID) = path[0] else { return false }
            return item.kind != .folder && item.parentID == parentID
        default:
            return false
        }
    }

    private func isValid(position: ReadingPosition, board: Board) -> Bool {
        switch position {
        case .collection(let folderID, let firstVisibleItemID, let relativeOffset, let fallbackContentY):
            guard let folder = board.item(id: folderID), folder.kind == .folder, folder.parentID == nil,
                relativeOffset.isFinite, relativeOffset >= 0,
                fallbackContentY.isFinite, fallbackContentY >= 0
            else { return false }
            if let firstVisibleItemID {
                guard let item = board.item(id: firstVisibleItemID), item.kind != .folder,
                    item.parentID == folderID
                else { return false }
            }
        case .item(let itemID, let visibleContentY):
            guard let item = board.item(id: itemID), item.kind != .folder,
                visibleContentY.isFinite, visibleContentY >= 0
            else { return false }
        case .pdf(let itemID, let pageIndex, let scale, let pointInPage):
            guard let item = board.item(id: itemID), item.kind == .pdf,
                pageIndex >= 0, scale.isFinite, scale > 0,
                pointInPage.x.isFinite, pointInPage.y.isFinite,
                pointInPage.x >= 0, pointInPage.y >= 0
            else { return false }
        }
        return true
    }
}

extension WorkspaceDestination {
    fileprivate var id: UUID? {
        switch self {
        case .collection(let id), .item(let id): id
        }
    }
}
