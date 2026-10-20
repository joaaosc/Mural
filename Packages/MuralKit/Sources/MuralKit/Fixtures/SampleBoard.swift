import Foundation

/// Mural inicial, usado na primeira abertura e nos previews.
public enum SampleBoard {
    public static let thingsINeed = ChecklistDocument(
        title: "Things I need",
        intro: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
        sections: [
            ChecklistSection(title: "Living Room", entries: [
                "Sofa / sectional", "Accent chairs", "Coffee table", "Side tables", "Media console / TV stand",
                "Area rug", "Floor lamp(s)", "Table lamps", "Shelving units / built-ins", "Wall art / framed prints",
                "Decorative pillows & throws", "Curtains / blinds", "Plant stands / indoor plants", "Storage baskets",
            ].map { ChecklistEntry(text: $0) }),
            ChecklistSection(title: "Dining Room", entries: [
                "Dining table", "Dining chairs / bench seating", "Sideboard / buffet", "Pendant or chandelier lighting",
                "Table linens (tablecloth, placemats, napkins)", "Centerpiece décor (vase, bowl, candles)", "Rug (if appropriate)",
            ].map { ChecklistEntry(text: $0) }),
            ChecklistSection(title: "Kitchen", entries: [
                "Bar stools (for island/peninsula)", "New cabinet hardware (pulls, knobs)", "Pendant lights",
                "Open shelving or display racks", "Countertop accessories (cutting boards, canisters, spice rack)",
                "Stylish dishware + glassware", "Cookware upgrades (matching set, quality pots & pans)",
            ].map { ChecklistEntry(text: $0) }),
        ]
    )

    public static func make(now: Date = .now) -> Board {
        let cottage = BoardItem(kind: .folder, title: "The Cottage", createdAt: now, position: BoardPoint(x: 420, y: 80), tag: "CLIENT 001")
        let street = BoardItem(kind: .folder, title: "44th Street", createdAt: now, position: BoardPoint(x: 420, y: 270), tag: "CLIENT 002")
        let acme = BoardItem(kind: .folder, title: "ACME Premises", createdAt: now, position: BoardPoint(x: 420, y: 460), tag: "CLIENT 003")

        var items: [BoardItem] = [
            BoardItem(kind: .text, title: "Design Philosophy", createdAt: now, position: BoardPoint(x: 160, y: 80),
                      text: "A design philosophy is a set of values that guides choices. Clarity before ornament. Light before furniture. Every object earns its place."),
            BoardItem(kind: .text, title: "Alpha", createdAt: now, position: BoardPoint(x: 300, y: 80),
                      text: "Site visit on Monday. Measure the north wall. Check the sun path at 16h. Bring the fabric samples and the paint fan."),
            BoardItem(kind: .text, title: "Today", createdAt: now, position: BoardPoint(x: 160, y: 250),
                      text: "Call the carpenter. Order the pendant lights. Review the floor plan with the client. Reply to the tile supplier."),
            BoardItem(kind: .text, title: "Running list of stuff", createdAt: now, position: BoardPoint(x: 300, y: 250),
                      text: "Running list of stuff that needs doing: fix the latch, repaint the hallway, replace the door handle, find a rug."),
            BoardItem(kind: .checklist, title: thingsINeed.title, createdAt: now, position: BoardPoint(x: 160, y: 420), checklist: thingsINeed),
            cottage, street, acme,
            // Post-its por último: ficam por cima das folhas e pastas, como no conceito.
            BoardItem(kind: .sticky, title: "The idea is this", createdAt: now, position: BoardPoint(x: 80, y: 110),
                      text: "The idea is this: make every room feel like the garden is inside it.", stickyColor: .pink),
            BoardItem(kind: .sticky, title: "Don't forget", createdAt: now, position: BoardPoint(x: 400, y: 560),
                      text: "Don't forget: the client prefers warm light, nothing above 3000K.", stickyColor: .orange),
        ]

        // Conteúdo da pasta "The Cottage", para a coleção já ter cartões.
        items += [
            BoardItem(kind: .text, title: "The Cottage", createdAt: now, parentID: cottage.id,
                      text: "A small house by the water. Keep the timber visible, soften the floors, open the kitchen to the garden."),
            BoardItem(kind: .text, title: "Meeting Notes – Andrea and Jasmine", createdAt: now.addingTimeInterval(1), parentID: cottage.id,
                      text: "Budget approved. They want a reading nook and a bigger dining table. Deliver the mood board by Friday."),
            BoardItem(kind: .text, title: "Thoughts", createdAt: now.addingTimeInterval(2), parentID: cottage.id,
                      text: "Terracotta and oak. One strong colour per room. Keep the ceilings white."),
            BoardItem(kind: .text, title: "Chairs and their Surroundings", createdAt: now.addingTimeInterval(3), parentID: cottage.id,
                      text: "A chair is never alone: it needs a lamp, a table, and something to look at."),
            BoardItem(kind: .sticky, title: "Things I still need to decide on", createdAt: now.addingTimeInterval(4), parentID: cottage.id,
                      text: "Things I still need to decide on: style of chairs, bathroom tiles, lamps for the living room.", stickyColor: .yellow),
            BoardItem(kind: .sticky, title: "This week", createdAt: now.addingTimeInterval(5), parentID: cottage.id,
                      text: "This week: finish bathroom detailing, find chairs for the living room.", stickyColor: .blue),
            BoardItem(kind: .checklist, title: thingsINeed.title, createdAt: now.addingTimeInterval(6), parentID: cottage.id, checklist: thingsINeed),
        ]
        return Board(items: items)
    }
}
