import AppKit
import Foundation
import Testing

@testable import Mural

/// Com duas cópias do Mural abertas (a instalada e uma de desenvolvimento ou de teste, com o mesmo identificador), só uma
/// mostra o ícone da barra de menus, e outra assume quando ela fecha.
@Suite("Dono do ícone da barra de menus")
struct MenuBarIconOwnershipTests {
    private static let installedPath = "/Applications/Mural.app"
    private static let userInstalledPath = "/Users/x/Applications/Mural.app"
    private static let derivedDataPath = "/Users/x/Library/Developer/Xcode/DerivedData/Mural-abc/Build/Products/Debug/Mural.app"

    private func mural(_ processID: pid_t, launched seconds: TimeInterval?, at path: String?) -> RunningMural {
        RunningMural(
            processID: processID,
            launchDate: seconds.map { Date(timeIntervalSince1970: $0) },
            bundleURL: path.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    @Test("Sem nenhum Mural aberto, ninguém é dono")
    func emptyListHasNoOwner() {
        #expect(MenuBarIconOwnership.owner(among: []) == nil)
    }

    @Test("Um Mural só é o dono, esteja onde estiver")
    func singleCopyOwnsTheIcon() {
        #expect(MenuBarIconOwnership.owner(among: [mural(7, launched: 10, at: Self.derivedDataPath)]) == 7)
        #expect(MenuBarIconOwnership.owner(among: [mural(8, launched: nil, at: nil)]) == 8)
    }

    @Test("O instalado ganha de uma cópia do DerivedData, mesmo a cópia sendo mais antiga")
    func installedBeatsOlderDerivedDataCopy() {
        let derivedData = mural(100, launched: 10, at: Self.derivedDataPath)
        let installed = mural(200, launched: 500, at: Self.installedPath)

        #expect(MenuBarIconOwnership.owner(among: [derivedData, installed]) == 200)
        #expect(MenuBarIconOwnership.owner(among: [installed, derivedData]) == 200)
    }

    @Test("Entre dois instalados, o mais antigo; o instalado em ~/Applications conta como instalado")
    func olderInstalledCopyWins() {
        let user = mural(300, launched: 20, at: Self.userInstalledPath)
        let system = mural(400, launched: 60, at: Self.installedPath)

        #expect(MenuBarIconOwnership.owner(among: [system, user]) == 300)
        #expect(MenuBarIconOwnership.owner(among: [user, system]) == 300)
    }

    @Test("Entre cópias de fora de Applications, a mais antiga")
    func olderCopyWinsAmongNonInstalled() {
        let older = mural(500, launched: 5, at: Self.derivedDataPath)
        let newer = mural(100, launched: 50, at: "/Users/x/Desktop/Mural.app")

        #expect(MenuBarIconOwnership.owner(among: [newer, older]) == 500)
    }

    @Test("Sem data de abertura, a cópia vai para o fim; sem endereço, não conta como instalada")
    func missingLaunchDateGoesLast() {
        let withoutDate = mural(1, launched: nil, at: Self.installedPath)
        let withDate = mural(9, launched: 1_000, at: Self.installedPath)
        #expect(MenuBarIconOwnership.owner(among: [withoutDate, withDate]) == 9)
        #expect(MenuBarIconOwnership.owner(among: [withDate, withoutDate]) == 9)

        let withoutLocation = mural(2, launched: 1, at: nil)
        #expect(MenuBarIconOwnership.owner(among: [withoutLocation, withoutDate]) == 1, "o instalado ganha do sem endereço")
    }

    @Test("Empate na data ou sem nenhuma data: o menor processID")
    func tieGoesToTheLowestProcessID() {
        let a = mural(42, launched: 77, at: Self.installedPath)
        let b = mural(7, launched: 77, at: Self.installedPath)
        #expect(MenuBarIconOwnership.owner(among: [a, b]) == 7)

        let c = mural(31, launched: nil, at: Self.derivedDataPath)
        let d = mural(12, launched: nil, at: Self.derivedDataPath)
        #expect(MenuBarIconOwnership.owner(among: [c, d]) == 12)
    }

    @Test("A resposta não depende da ordem da lista: toda cópia chega ao mesmo dono")
    func ownerDoesNotDependOnListOrder() {
        let copies = [
            mural(10, launched: 5, at: Self.derivedDataPath),
            mural(20, launched: nil, at: Self.installedPath),
            mural(30, launched: 90, at: Self.installedPath),
            mural(40, launched: 90, at: Self.userInstalledPath),
        ]
        let expected = MenuBarIconOwnership.owner(among: copies)
        #expect(expected == 30, "dos instalados, o de data conhecida; no empate de data, o menor processID")

        for (first, second) in [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2), (1, 3)] {
            var shuffled = copies
            shuffled.swapAt(first, second)
            #expect(MenuBarIconOwnership.owner(among: shuffled) == expected)
            #expect(MenuBarIconOwnership.owner(among: shuffled.reversed()) == expected)
        }
    }

    @Test("Instalado é o .app dentro de uma pasta chamada Applications")
    func installedMeansInsideAnApplicationsFolder() {
        func isInstalled(_ path: String?) -> Bool {
            MenuBarIconOwnership.isInstalled(path.map { URL(fileURLWithPath: $0, isDirectory: true) })
        }

        #expect(isInstalled("/Applications/Mural.app"))
        #expect(isInstalled("/Users/x/Applications/Mural.app"))
        #expect(!isInstalled(Self.derivedDataPath))
        #expect(!isInstalled("/Applications/Utilities/Mural.app"), "só a pasta-mãe do .app conta")
        #expect(!isInstalled("/Users/x/Applications Old/Mural.app"))
        #expect(!isInstalled(nil))
    }
}

/// O coordenador decide com a lista injetada, sem processos de verdade, e reavalia quando uma cópia abre ou fecha.
@Suite("Coordenador do ícone da barra de menus")
@MainActor
struct MenuBarIconCoordinatorTests {
    private final class Fixture {
        var running: [RunningMural]
        var visibility: [Bool] = []

        init(running: [RunningMural]) {
            self.running = running
        }
    }

    private static let defaultBundleIdentifier = "com.exemplo.Mural"

    private func coordinator(
        _ fixture: Fixture, processID: pid_t, bundleIdentifier: String = MenuBarIconCoordinatorTests.defaultBundleIdentifier,
        center: NotificationCenter = NotificationCenter()
    ) -> MenuBarIconCoordinator {
        MenuBarIconCoordinator(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            notificationCenter: center,
            runningMurals: { fixture.running },
            setIconVisible: { fixture.visibility.append($0) })
    }

    private func installed(_ processID: pid_t, launched seconds: TimeInterval) -> RunningMural {
        RunningMural(
            processID: processID, launchDate: Date(timeIntervalSince1970: seconds),
            bundleURL: URL(fileURLWithPath: "/Applications/Mural.app", isDirectory: true))
    }

    private func copy(_ processID: pid_t, launched seconds: TimeInterval) -> RunningMural {
        RunningMural(
            processID: processID, launchDate: Date(timeIntervalSince1970: seconds),
            bundleURL: URL(fileURLWithPath: "/Users/x/DerivedData/Build/Products/Debug/Mural.app", isDirectory: true))
    }

    private func launchNotification(of application: NSRunningApplication) -> Notification {
        Notification(
            name: NSWorkspace.didLaunchApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: application])
    }

    @Test("A cópia dona do ícone o mostra")
    func ownerShowsTheIcon() {
        let fixture = Fixture(running: [installed(10, launched: 1), copy(20, launched: 2)])

        coordinator(fixture, processID: 10).evaluate()

        #expect(fixture.visibility == [true])
    }

    @Test("A cópia que não é dona esconde o ícone")
    func nonOwnerHidesTheIcon() {
        let fixture = Fixture(running: [installed(10, launched: 1), copy(20, launched: 2)])

        coordinator(fixture, processID: 20).evaluate()

        #expect(fixture.visibility == [false])
    }

    @Test("Quando a dona fecha, a que sobra assume o ícone ao reavaliar")
    func survivorTakesOverWhenTheOwnerQuits() {
        let fixture = Fixture(running: [installed(10, launched: 1), copy(20, launched: 2)])
        let survivor = coordinator(fixture, processID: 20)

        survivor.evaluate()
        fixture.running = [copy(20, launched: 2)]
        survivor.evaluate()

        #expect(fixture.visibility == [false, true])
    }

    @Test("No aviso de término, a cópia que fechou não conta, mesmo que a lista do sistema ainda a traga")
    func endedCopyIsIgnoredEvenIfStillListed() throws {
        // A dona é este processo (instalado e mais antigo); o aviso diz que ele fechou, mas a lista ainda o mostra.
        let current = NSRunningApplication.current
        let bundleIdentifier = try #require(current.bundleIdentifier)
        let fixture = Fixture(running: [installed(current.processIdentifier, launched: 1), copy(20, launched: 2)])
        let survivor = coordinator(fixture, processID: 20, bundleIdentifier: bundleIdentifier)
        let ended = Notification(
            name: NSWorkspace.didTerminateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: current])

        survivor.evaluate()
        survivor.handle(ended)

        #expect(fixture.visibility == [false, true])
    }

    @Test("Uma cópia que abre depois e é mais forte toma o ícone da que estava sozinha")
    func newerButInstalledCopyTakesTheIcon() {
        let fixture = Fixture(running: [copy(20, launched: 2)])
        let development = coordinator(fixture, processID: 20)

        development.evaluate()
        fixture.running.append(installed(30, launched: 9))
        development.evaluate()

        #expect(fixture.visibility == [true, false])
    }

    @Test("Aviso do mesmo identificador reavalia; de outro aplicativo, não")
    func onlyNotificationsOfTheSameBundleReevaluate() throws {
        let current = NSRunningApplication.current
        let bundleIdentifier = try #require(current.bundleIdentifier)
        let fixture = Fixture(running: [copy(20, launched: 2)])

        coordinator(fixture, processID: 20, bundleIdentifier: bundleIdentifier).handle(launchNotification(of: current))
        #expect(fixture.visibility == [true])

        coordinator(fixture, processID: 20, bundleIdentifier: "com.exemplo.Outro").handle(launchNotification(of: current))
        #expect(fixture.visibility == [true], "o aviso de um aplicativo de outro identificador é ignorado")

        let semAplicativo = Notification(name: NSWorkspace.didLaunchApplicationNotification)
        coordinator(fixture, processID: 20, bundleIdentifier: bundleIdentifier).handle(semAplicativo)
        #expect(fixture.visibility == [true], "um aviso sem aplicativo é ignorado")
    }

    @Test("start avalia na hora, reavalia a cada aviso do centro e não observa duas vezes")
    func startEvaluatesNowAndObservesTheWorkspace() async throws {
        let current = NSRunningApplication.current
        let bundleIdentifier = try #require(current.bundleIdentifier)
        let center = NotificationCenter()
        let fixture = Fixture(running: [installed(10, launched: 1), copy(20, launched: 2)])
        let survivor = coordinator(fixture, processID: 20, bundleIdentifier: bundleIdentifier, center: center)

        survivor.start()
        survivor.start()
        #expect(fixture.visibility == [false, false], "cada start avalia")

        fixture.running = [copy(20, launched: 2)]
        center.post(
            name: NSWorkspace.didTerminateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: current])
        await waitUntil("o aviso reavaliar e a cópia assumir o ícone") { fixture.visibility.last == true }
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.visibility == [false, false, true], "um aviso, uma avaliação")
    }

    @Test("A lista do sistema sempre traz esta cópia, uma vez só")
    func systemListAlwaysIncludesThisProcess() throws {
        let alone = MenuBarIconCoordinator.systemMurals(bundleIdentifier: "com.exemplo.SemNinguem")
        #expect(alone.map(\.processID) == [getpid()], "o sistema não lista ninguém: entra só esta cópia")

        let bundleIdentifier = try #require(NSRunningApplication.current.bundleIdentifier)
        let own = MenuBarIconCoordinator.systemMurals(bundleIdentifier: bundleIdentifier)
        #expect(own.filter { $0.processID == getpid() }.count == 1)
    }
}
