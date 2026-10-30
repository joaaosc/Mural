import Foundation

extension BoardWorkspaceState {
    /// Valida o estado sem permitir que uma navegação de outro mural seja mantida.
    public func canonicalized(for board: Board) -> WorkspaceValidationResult {
        var canonical = self
        // Uma busca por id em tempo constante; a busca linear de `board.item(id:)` repetida por entrada pesa em murais grandes.
        // Com ids repetidos vale o primeiro cartão, como em `board.item(id:)`.
        let itemsByID = Dictionary(board.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

        // O caminho vai de pasta em pasta (até `maximumFolderDepth` níveis) e pode terminar numa página de cartão.
        var validPath: [WorkspaceDestination] = []
        var seen = Set<UUID>()
        for (index, destination) in canonical.path.enumerated() {
            guard index <= Board.maximumFolderDepth else {
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
            guard isValid(destination: destination, after: validPath, items: itemsByID) else {
                issues.append(.invalidPath(index: index))
                issues.append(.pathTruncated(index: index))
                break
            }
            validPath.append(destination)
        }
        canonical.path = validPath

        // O filtro vale na lista de um nível (mural ou pasta), nunca na página de um cartão.
        if canonical.filter != nil {
            let filterIsValid =
                switch canonical.path.last {
                case nil, .collection: true
                case .item: false
                }
            if !filterIsValid {
                canonical.filter = nil
                issues.append(.invalidFilter)
            }
        }

        var validPositions: [UUID: ReadingPosition] = [:]
        for (key, position) in canonical.readingPositions {
            guard key == position.targetItemID,
                isValid(position: position, items: itemsByID)
            else {
                issues.append(.removedReadingPosition(key))
                continue
            }
            validPositions[key] = position
        }
        canonical.readingPositions = validPositions

        // Memória de parágrafos abertos só vale para nota com o mesmo texto.
        for (itemID, memory) in canonical.openStretches.sorted(by: { $0.key.uuidString < $1.key.uuidString })
        where !isValid(memory: memory, itemID: itemID, items: itemsByID) {
            canonical.openStretches.removeValue(forKey: itemID)
            issues.append(.removedOpenStretches(itemID))
        }
        return WorkspaceValidationResult(state: canonical, issues: issues)
    }

    public func validated(for board: Board) -> BoardWorkspaceState {
        canonicalized(for: board).state
    }

    /// Um destino vale se o cartão existe, é do tipo certo (pasta para `.collection`, outro cartão para `.item`) e está
    /// dentro do destino anterior, ou solto no mural se for o primeiro. Nada vem depois de um `.item`.
    private func isValid(destination: WorkspaceDestination, after path: [WorkspaceDestination], items: [UUID: BoardItem]) -> Bool {
        guard let id = destination.id, let item = items[id] else { return false }
        let expectedParentID: UUID?
        switch path.last {
        case nil: expectedParentID = nil
        case .collection(let folderID): expectedParentID = folderID
        case .item: return false
        }
        guard item.parentID == expectedParentID else { return false }
        switch destination {
        case .collection: return item.kind == .folder
        case .item: return item.kind != .folder
        }
    }

    private func isValid(memory: OpenStretchMemory, itemID: UUID, items: [UUID: BoardItem]) -> Bool {
        guard !memory.openIDs.isEmpty, let item = items[itemID], let source = NoteFolding.source(of: item) else {
            return false
        }
        return memory.matches(source)
    }

    private func isValid(position: ReadingPosition, items: [UUID: BoardItem]) -> Bool {
        switch position {
        case .collection(let folderID, let firstVisibleItemID, let relativeOffset, let fallbackContentY):
            // A pasta pode estar em qualquer nível; o primeiro cartão visível pode ser outra pasta.
            guard let folder = items[folderID], folder.kind == .folder,
                relativeOffset.isFinite, relativeOffset >= 0,
                fallbackContentY.isFinite, fallbackContentY >= 0
            else { return false }
            if let firstVisibleItemID {
                guard let item = items[firstVisibleItemID], item.parentID == folderID else { return false }
            }
        case .item(let itemID, let visibleContentY):
            guard let item = items[itemID], item.kind != .folder,
                visibleContentY.isFinite, visibleContentY >= 0
            else { return false }
        case .pdf(let itemID, let pageIndex, let scale, let pointInPage):
            guard let item = items[itemID], item.kind == .pdf,
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
