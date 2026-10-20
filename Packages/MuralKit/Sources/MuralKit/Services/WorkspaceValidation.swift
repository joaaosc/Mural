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
        var seen = Set<BoardID>()
        for (index, destination) in canonical.path.enumerated() {
            guard index < 2 else {
                issues.append(.pathTruncated(index: index))
                break
            }
            let id: BoardID
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

        var validPositions: [BoardID: ReadingPosition] = [:]
        for (key, position) in canonical.readingPositions {
            guard key == position.targetID,
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
        guard let id = destination.id, let item = board.item(id: id.rawValue) else { return false }
        switch (index, destination) {
        case (0, .collection(_)):
            return item.kind == .folder && item.parentID == nil
        case (0, .item(_)):
            return item.kind != .folder && item.parentID == nil
        case (1, .item(_)):
            guard case .collection(let parentID) = path[0] else { return false }
            return item.kind != .folder && item.parentID == parentID.rawValue
        default:
            return false
        }
    }

    private func isValid(position: ReadingPosition, board: Board) -> Bool {
        guard let item = board.item(id: position.targetID.rawValue) else { return false }
        switch position.kind {
        case .collection:
            guard item.kind == .folder, item.parentID == nil else { return false }
        case .item:
            guard item.kind != .folder, item.kind != .pdf else { return false }
        case .pdf:
            guard item.kind == .pdf, let page = position.page, page > 0 else { return false }
        }
        if let page = position.page, page <= 0 { return false }
        if let progress = position.progress, !(progress.isFinite && (0...1).contains(progress)) { return false }
        return true
    }
}

extension WorkspaceDestination {
    fileprivate var id: BoardID? {
        switch self {
        case .collection(let id), .item(let id): id
        }
    }
}
