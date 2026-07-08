import Combine
import Defaults
import SwiftUI

public struct ActivityID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }
}

struct ActivityMetadata {
    let name: String
    let systemImage: String
    let tint: Color
    let preferredExpandedHeight: CGFloat?
    let summary: String?

    init(
        name: String,
        systemImage: String,
        tint: Color = .accentColor,
        preferredExpandedHeight: CGFloat? = nil,
        summary: String? = nil
    ) {
        self.name = name
        self.systemImage = systemImage
        self.tint = tint
        self.preferredExpandedHeight = preferredExpandedHeight
        self.summary = summary
    }
}

enum ActivityLivePresentationPriority: Int, Comparable, Sendable {
    case low = 0
    case normal = 100
    case high = 200

    static func < (
        lhs: ActivityLivePresentationPriority,
        rhs: ActivityLivePresentationPriority
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ActivityLivePresentationState: Equatable, Sendable {
    case hidden
    case visible(priority: ActivityLivePresentationPriority)

    var priority: ActivityLivePresentationPriority? {
        guard case .visible(let priority) = self else { return nil }
        return priority
    }
}

enum LiveActivityPresentationWidth: Equatable, Sendable {
    case fixed(CGFloat)
    case accessorySize

    func resolved(accessorySize: CGFloat) -> CGFloat {
        switch self {
        case .fixed(let width):
            return max(0, width)
        case .accessorySize:
            return max(0, accessorySize)
        }
    }
}

struct LiveActivityPresentationSizing: Equatable, Sendable {
    let fullContentWidth: LiveActivityPresentationWidth
    let minimalContentWidth: LiveActivityPresentationWidth

    init(
        fullContentWidth: LiveActivityPresentationWidth = .fixed(64),
        minimalContentWidth: LiveActivityPresentationWidth = .fixed(56)
    ) {
        self.fullContentWidth = fullContentWidth
        self.minimalContentWidth = minimalContentWidth
    }
}

@MainActor
protocol NotchActivity: ObservableObject {
    associatedtype ExpandedContent: View
    associatedtype CompactContent: View = EmptyView
    associatedtype LivePresentationContent: View = EmptyView
    associatedtype MinimalLivePresentationContent: View = LivePresentationContent
    associatedtype ConfigurationContent: View = EmptyView

    var id: ActivityID { get }
    var metadata: ActivityMetadata { get }
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    var supportsCompactPresentation: Bool { get }
    var livePresentationState: ActivityLivePresentationState { get }
    var livePresentationSizing: LiveActivityPresentationSizing { get }
    var supportsConfiguration: Bool { get }

    @ViewBuilder func makeExpandedView() -> ExpandedContent
    @ViewBuilder func makeCompactView() -> CompactContent
    @ViewBuilder func makeLivePresentationView() -> LivePresentationContent
    @ViewBuilder func makeMinimalLivePresentationView() -> MinimalLivePresentationContent
    @ViewBuilder func makeConfigurationView() -> ConfigurationContent

    func activityDidAppear()
    func activityDidDisappear()
}

extension NotchActivity {
    var isAvailable: Bool { true }
    var isActive: Bool { false }
    var supportsCompactPresentation: Bool { false }
    var livePresentationState: ActivityLivePresentationState { .hidden }
    var livePresentationSizing: LiveActivityPresentationSizing {
        LiveActivityPresentationSizing()
    }
    var supportsConfiguration: Bool { false }

    func activityDidAppear() {}
    func activityDidDisappear() {}
}

extension NotchActivity where CompactContent == EmptyView {
    func makeCompactView() -> EmptyView {
        EmptyView()
    }
}

extension NotchActivity where LivePresentationContent == EmptyView {
    func makeLivePresentationView() -> EmptyView {
        EmptyView()
    }
}

extension NotchActivity where MinimalLivePresentationContent == LivePresentationContent {
    func makeMinimalLivePresentationView() -> LivePresentationContent {
        makeLivePresentationView()
    }
}

extension NotchActivity where ConfigurationContent == EmptyView {
    func makeConfigurationView() -> EmptyView {
        EmptyView()
    }
}

@MainActor
final class AnyNotchActivity: @MainActor ObservableObject, Identifiable {
    let objectWillChange = ObservableObjectPublisher()

    let id: ActivityID
    let metadata: ActivityMetadata

    private let availability: () -> Bool
    private let activeState: () -> Bool
    private let compactPresentationSupport: () -> Bool
    private let livePresentation: () -> ActivityLivePresentationState
    private let presentationSizing: () -> LiveActivityPresentationSizing
    private let configurationSupport: () -> Bool
    private let expandedView: () -> AnyView
    private let compactView: () -> AnyView
    private let livePresentationView: () -> AnyView
    private let minimalLivePresentationView: () -> AnyView
    private let configurationView: () -> AnyView
    private let didAppear: () -> Void
    private let didDisappear: () -> Void
    private var activityObservation: AnyCancellable?

    init<Activity: NotchActivity>(_ activity: Activity) {
        id = activity.id
        metadata = activity.metadata
        availability = { activity.isAvailable }
        activeState = { activity.isActive }
        compactPresentationSupport = { activity.supportsCompactPresentation }
        livePresentation = { activity.livePresentationState }
        presentationSizing = { activity.livePresentationSizing }
        configurationSupport = { activity.supportsConfiguration }
        expandedView = { AnyView(activity.makeExpandedView()) }
        compactView = { AnyView(activity.makeCompactView()) }
        livePresentationView = { AnyView(activity.makeLivePresentationView()) }
        minimalLivePresentationView = { AnyView(activity.makeMinimalLivePresentationView()) }
        configurationView = { AnyView(activity.makeConfigurationView()) }
        didAppear = activity.activityDidAppear
        didDisappear = activity.activityDidDisappear

        activityObservation = activity.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isAvailable: Bool { availability() }
    var isActive: Bool { activeState() }
    var supportsCompactPresentation: Bool { compactPresentationSupport() }
    var livePresentationState: ActivityLivePresentationState { livePresentation() }
    var livePresentationSizing: LiveActivityPresentationSizing { presentationSizing() }
    var supportsConfiguration: Bool { configurationSupport() }

    func makeExpandedView() -> AnyView { expandedView() }
    func makeCompactView() -> AnyView { compactView() }
    func makeLivePresentationView() -> AnyView { livePresentationView() }
    func makeMinimalLivePresentationView() -> AnyView { minimalLivePresentationView() }
    func makeConfigurationView() -> AnyView { configurationView() }

    func activityDidAppear() { didAppear() }
    func activityDidDisappear() { didDisappear() }
}

@MainActor
protocol LiveActivityPresentationProvider: ObservableObject {
    associatedtype AccessoryContent: View
    associatedtype FullContent: View
    associatedtype MinimalContent: View

    var id: ActivityID { get }
    var name: String { get }
    var livePresentationState: ActivityLivePresentationState { get }
    var showsAccessoryInMinimalPresentation: Bool { get }
    var livePresentationSizing: LiveActivityPresentationSizing { get }

    @ViewBuilder func makeAccessoryView() -> AccessoryContent
    @ViewBuilder func makeFullView() -> FullContent
    @ViewBuilder func makeMinimalView() -> MinimalContent
}

extension LiveActivityPresentationProvider {
    var showsAccessoryInMinimalPresentation: Bool { true }
    var livePresentationSizing: LiveActivityPresentationSizing {
        LiveActivityPresentationSizing()
    }
}

@MainActor
final class AnyLiveActivityPresentationProvider: ObservableObject, Identifiable {
    let objectWillChange = ObservableObjectPublisher()

    let id: ActivityID
    let name: String

    private let presentationState: () -> ActivityLivePresentationState
    private let minimalPresentationAccessoryVisibility: () -> Bool
    private let presentationSizing: () -> LiveActivityPresentationSizing
    private let accessoryView: () -> AnyView
    private let fullView: () -> AnyView
    private let minimalView: () -> AnyView
    private var providerObservation: AnyCancellable?

    init<Provider: LiveActivityPresentationProvider>(_ provider: Provider) {
        id = provider.id
        name = provider.name
        presentationState = { provider.livePresentationState }
        minimalPresentationAccessoryVisibility = { provider.showsAccessoryInMinimalPresentation }
        presentationSizing = { provider.livePresentationSizing }
        accessoryView = { AnyView(provider.makeAccessoryView()) }
        fullView = { AnyView(provider.makeFullView()) }
        minimalView = { AnyView(provider.makeMinimalView()) }
        providerObservation = provider.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    init(activity: AnyNotchActivity) {
        id = activity.id
        name = activity.metadata.name
        presentationState = {
            activity.isAvailable ? activity.livePresentationState : .hidden
        }
        minimalPresentationAccessoryVisibility = { true }
        presentationSizing = { activity.livePresentationSizing }
        accessoryView = {
            AnyView(
                Image(systemName: activity.metadata.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(activity.metadata.tint)
                    .accessibilityHidden(true)
            )
        }
        fullView = { activity.makeLivePresentationView() }
        minimalView = { activity.makeMinimalLivePresentationView() }
        providerObservation = activity.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    init(activity: AnyNotchActivity, registry: ActivityRegistry) {
        id = activity.id
        name = activity.metadata.name
        presentationState = {
            registry.isActivityAvailable(activity.id) ? activity.livePresentationState : .hidden
        }
        minimalPresentationAccessoryVisibility = { true }
        presentationSizing = { activity.livePresentationSizing }
        accessoryView = {
            AnyView(
                Image(systemName: activity.metadata.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(activity.metadata.tint)
                    .accessibilityHidden(true)
            )
        }
        fullView = { activity.makeLivePresentationView() }
        minimalView = { activity.makeMinimalLivePresentationView() }
        providerObservation = registry.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var livePresentationState: ActivityLivePresentationState { presentationState() }
    var showsAccessoryInMinimalPresentation: Bool { minimalPresentationAccessoryVisibility() }
    var livePresentationSizing: LiveActivityPresentationSizing { presentationSizing() }

    func makeAccessoryView() -> AnyView { accessoryView() }
    func makeFullView() -> AnyView { fullView() }
    func makeMinimalView() -> AnyView { minimalView() }
}

@MainActor
final class LiveActivityPresentationProviderRegistry: ObservableObject {
    static let shared = LiveActivityPresentationProviderRegistry(
        activityRegistry: .shared,
        additionalProviders: [
            AnyLiveActivityPresentationProvider(TimeLiveActivityProvider()),
            AnyLiveActivityPresentationProvider(MediaLiveActivityProvider())
        ]
    )

    private let activityRegistry: ActivityRegistry
    private let registeredActivityProviders: [AnyLiveActivityPresentationProvider]
    private let additionalProviders: [AnyLiveActivityPresentationProvider]

    private var providerObservations: Set<AnyCancellable> = []

    var providers: [AnyLiveActivityPresentationProvider] {
        registeredActivityProviders.filter { activityRegistry.isActivityEnabled($0.id) }
            + additionalProviders
    }

    init(
        activityRegistry: ActivityRegistry,
        additionalProviders: [AnyLiveActivityPresentationProvider] = []
    ) {
        self.activityRegistry = activityRegistry
        registeredActivityProviders = activityRegistry.activities.map {
            AnyLiveActivityPresentationProvider(activity: $0, registry: activityRegistry)
        }
        self.additionalProviders = additionalProviders

        for provider in registeredActivityProviders + additionalProviders {
            provider.objectWillChange
                .sink { [weak self] in
                    self?.objectWillChange.send()
                }
                .store(in: &providerObservations)
        }
    }
}

extension ActivityID {
    static let time = ActivityID("builtin.time")
    static let media = ActivityID("builtin.media")
}

@MainActor
final class TimeLiveActivityProvider: LiveActivityPresentationProvider {
    let id = ActivityID.time
    let name = "Timer"
    let livePresentationSizing = LiveActivityPresentationSizing(
        fullContentWidth: .fixed(closedTimeActivityMinimumTextWidth),
        minimalContentWidth: .fixed(0)
    )

    private let manager: TimeActivityManager
    @Published private var isEnabled: Bool
    private var managerObservation: AnyCancellable?
    private var enabledObservation: AnyCancellable?

    init(manager: TimeActivityManager? = nil, isEnabled: Bool? = nil) {
        self.manager = manager ?? .shared
        self.isEnabled = isEnabled ?? Defaults[.clockShowInClosedNotch]

        managerObservation = self.manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        if isEnabled == nil {
            enabledObservation = Defaults.publisher(.clockShowInClosedNotch)
                .map(\.newValue)
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] isEnabled in
                    self?.isEnabled = isEnabled
                }
        }
    }

    var livePresentationState: ActivityLivePresentationState {
        Self.presentationState(snapshot: manager.snapshot, isEnabled: isEnabled)
    }

    static func presentationState(
        snapshot: TimeActivitySnapshot?,
        isEnabled: Bool
    ) -> ActivityLivePresentationState {
        guard isEnabled, let snapshot else { return .hidden }
        switch snapshot.phase {
        case .running:
            return .visible(priority: .normal)
        case .paused:
            return .visible(priority: .low)
        case .finished:
            return .hidden
        }
    }

    func makeAccessoryView() -> some View {
        TimeLivePresentationAccessoryView(manager: manager)
    }

    func makeFullView() -> some View {
        TimeLivePresentationView(manager: manager)
    }

    func makeMinimalView() -> some View {
        EmptyView()
    }
}

@MainActor
final class MediaLiveActivityProvider: LiveActivityPresentationProvider {
    let id = ActivityID.media
    let name = "Media"
    let showsAccessoryInMinimalPresentation = false
    let livePresentationSizing = LiveActivityPresentationSizing(
        fullContentWidth: .accessorySize,
        minimalContentWidth: .accessorySize
    )

    private let manager: MusicManager
    private let coordinator: BoringViewCoordinator
    private var managerObservation: AnyCancellable?
    private var coordinatorObservation: AnyCancellable?

    init(
        manager: MusicManager? = nil,
        coordinator: BoringViewCoordinator? = nil
    ) {
        self.manager = manager ?? .shared
        self.coordinator = coordinator ?? .shared
        managerObservation = self.manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        coordinatorObservation = self.coordinator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var livePresentationState: ActivityLivePresentationState {
        Self.presentationState(
            isEnabled: coordinator.musicLiveActivityEnabled,
            isPlaying: manager.isPlaying,
            isPlayerIdle: manager.isPlayerIdle
        )
    }

    static func presentationState(
        isEnabled: Bool,
        isPlaying: Bool,
        isPlayerIdle: Bool
    ) -> ActivityLivePresentationState {
        guard isEnabled, isPlaying || !isPlayerIdle else { return .hidden }
        return .visible(priority: isPlaying ? .normal : .low)
    }

    func makeAccessoryView() -> some View {
        MediaLivePresentationAccessoryView(manager: manager)
    }

    func makeFullView() -> some View {
        MediaLivePresentationView(manager: manager)
    }

    func makeMinimalView() -> some View {
        MediaMinimalLivePresentationView(manager: manager)
    }
}

struct ActivityLivePresentationSnapshot: Equatable, Sendable {
    static let empty = ActivityLivePresentationSnapshot(startedSequences: [:])

    let startedSequences: [ActivityID: Int]

    func startedSequence(for id: ActivityID) -> Int? {
        startedSequences[id]
    }
}

@MainActor
final class ActivityLivePresentationCoordinator: ObservableObject {
    static let shared = ActivityLivePresentationCoordinator(
        registry: LiveActivityPresentationProviderRegistry.shared
    )

    @Published private(set) var snapshot: ActivityLivePresentationSnapshot = .empty

    private let registry: LiveActivityPresentationProviderRegistry
    private var knownEligibility: [ActivityID: Bool] = [:]
    private var startedSequences: [ActivityID: Int] = [:]
    private var nextSequence = 0
    private var registryObservation: AnyCancellable?
    private var reconcileTask: Task<Void, Never>?

    init(registry: LiveActivityPresentationProviderRegistry) {
        self.registry = registry
        reconcile(recordStartsForNewEligibility: false)

        registryObservation = registry.objectWillChange.sink { [weak self] _ in
            #if DEBUG
            ActivityLivePresentationDebugLogger.logRegistryChangeReceived()
            #endif
            self?.scheduleReconcile()
        }
    }

    convenience init(registry: ActivityRegistry) {
        self.init(registry: LiveActivityPresentationProviderRegistry(activityRegistry: registry))
    }

    deinit {
        reconcileTask?.cancel()
        registryObservation?.cancel()
    }

    func waitForPendingReconciliation() async {
        await reconcileTask?.value
    }

    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.reconcile(recordStartsForNewEligibility: true)
        }
    }

    private func reconcile(recordStartsForNewEligibility: Bool) {
        #if DEBUG
        ActivityLivePresentationDebugLogger.logReconciliationStarted(
            recordStartsForNewEligibility: recordStartsForNewEligibility
        )
        #endif

        var nextEligibility: [ActivityID: Bool] = [:]
        var nextStartedSequences = startedSequences

        for provider in registry.providers {
            let isEligible = provider.livePresentationState.priority != nil
            let wasEligible = knownEligibility[provider.id] ?? false

            nextEligibility[provider.id] = isEligible

            if isEligible && !wasEligible {
                if recordStartsForNewEligibility {
                    nextSequence += 1
                    nextStartedSequences[provider.id] = nextSequence
                    #if DEBUG
                    ActivityLivePresentationDebugLogger.logBecameEligible(
                        activityID: provider.id,
                        sequence: nextSequence
                    )
                    #endif
                } else {
                    nextStartedSequences.removeValue(forKey: provider.id)
                    #if DEBUG
                    ActivityLivePresentationDebugLogger.logInitiallyEligible(
                        activityID: provider.id
                    )
                    #endif
                }
            } else if !isEligible {
                if wasEligible {
                    #if DEBUG
                    ActivityLivePresentationDebugLogger.logBecameIneligible(
                        activityID: provider.id
                    )
                    #endif
                }
                nextStartedSequences.removeValue(forKey: provider.id)
            }
        }

        nextStartedSequences = nextStartedSequences.filter {
            nextEligibility[$0.key] != nil
        }

        knownEligibility = nextEligibility
        startedSequences = nextStartedSequences
        snapshot = ActivityLivePresentationSnapshot(startedSequences: startedSequences)

        #if DEBUG
        ActivityLivePresentationDebugLogger.logReconciled(
            providers: registry.providers,
            snapshot: snapshot
        )
        #endif
    }
}

enum ActivityLivePresentationStack {
    case none
    case full(AnyLiveActivityPresentationProvider)
    case split(
        leading: AnyLiveActivityPresentationProvider,
        trailing: AnyLiveActivityPresentationProvider
    )

    var isVisible: Bool {
        if case .none = self { return false }
        return true
    }

    var identity: String {
        switch self {
        case .none:
            return "none"
        case .full(let activity):
            return "full:\(activity.id.rawValue)"
        case .split(let leading, let trailing):
            return "split:\(leading.id.rawValue):\(trailing.id.rawValue)"
        }
    }

    var debugSelectionDescription: String {
        switch self {
        case .none:
            return ".none"
        case .full(let activity):
            return ".full(\(activity.id.rawValue))"
        case .split(let leading, let trailing):
            return ".split(\(leading.id.rawValue), \(trailing.id.rawValue))"
        }
    }

    @MainActor
    func requiredAdditionalWidth(accessorySize: CGFloat) -> CGFloat? {
        switch self {
        case .none:
            return nil
        case .full(let activity):
            return accessorySize
                + activity.livePresentationSizing.fullContentWidth.resolved(
                    accessorySize: accessorySize
                )
                + 20
        case .split(let leading, let trailing):
            return minimalPresentationWidth(
                for: leading,
                accessorySize: accessorySize
            )
                + minimalPresentationWidth(for: trailing, accessorySize: accessorySize)
                + 20
        }
    }

    @MainActor
    private func minimalPresentationWidth(
        for activity: AnyLiveActivityPresentationProvider,
        accessorySize: CGFloat
    ) -> CGFloat {
        let contentWidth = activity.livePresentationSizing.minimalContentWidth.resolved(
            accessorySize: accessorySize
        )
        let accessorySpacing: CGFloat = activity.showsAccessoryInMinimalPresentation && contentWidth > 0
            ? 6
            : 0

        return contentWidth
            + (activity.showsAccessoryInMinimalPresentation ? accessorySize + accessorySpacing : 0)
    }
}

@MainActor
func selectedActivityLivePresentationStack(
    from providers: [AnyLiveActivityPresentationProvider],
    snapshot: ActivityLivePresentationSnapshot
) -> ActivityLivePresentationStack {
    let eligibleProviders = eligibleLiveActivitiesInSelectionOrder(
        from: providers,
        snapshot: snapshot
    )

    let selection: ActivityLivePresentationStack
    switch eligibleProviders.count {
    case 0:
        selection = .none
    case 1:
        selection = .full(eligibleProviders[0])
    default:
        selection = .split(leading: eligibleProviders[1], trailing: eligibleProviders[0])
    }

    #if DEBUG
    ActivityLivePresentationDebugLogger.logSelectorRun(
        eligibleActivities: eligibleProviders,
        snapshot: snapshot,
        selection: selection
    )
    #endif

    return selection
}

@MainActor
func selectedActivityLivePresentationStack(
    from activities: [AnyNotchActivity],
    snapshot: ActivityLivePresentationSnapshot
) -> ActivityLivePresentationStack {
    selectedActivityLivePresentationStack(
        from: activities.map { AnyLiveActivityPresentationProvider(activity: $0) },
        snapshot: snapshot
    )
}

@MainActor
private func eligibleLiveActivitiesInSelectionOrder(
    from providers: [AnyLiveActivityPresentationProvider],
    snapshot: ActivityLivePresentationSnapshot
) -> [AnyLiveActivityPresentationProvider] {
    providers.enumerated()
        .filter { _, provider in
            provider.livePresentationState.priority != nil
        }
        .sorted { lhs, rhs in
            let lhsSequence = snapshot.startedSequence(for: lhs.element.id)
            let rhsSequence = snapshot.startedSequence(for: rhs.element.id)

            switch (lhsSequence, rhsSequence) {
            case let (lhsSequence?, rhsSequence?) where lhsSequence != rhsSequence:
                return lhsSequence > rhsSequence
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
}

#if DEBUG
@MainActor
enum ActivityLivePresentationDebugLogger {
    private static var lastSelectorSignature: String?

    static func logRegistryChangeReceived() {
        log("provider registry change received; scheduling eligibility reconciliation")
    }

    static func logReconciliationStarted(recordStartsForNewEligibility: Bool) {
        log("reconciling eligibility recordStarts=\(recordStartsForNewEligibility)")
    }

    static func logBecameEligible(activityID: ActivityID, sequence: Int) {
        log("provider became eligible id=\(activityID.rawValue) sequence=\(sequence)")
    }

    static func logInitiallyEligible(activityID: ActivityID) {
        log("provider initially eligible id=\(activityID.rawValue) sequence=registry-order")
    }

    static func logBecameIneligible(activityID: ActivityID) {
        log("provider became ineligible id=\(activityID.rawValue)")
    }

    static func logReconciled(
        providers: [AnyLiveActivityPresentationProvider],
        snapshot: ActivityLivePresentationSnapshot
    ) {
        let eligibleProviders = eligibleLiveActivitiesInSelectionOrder(
            from: providers,
            snapshot: snapshot
        )
        log("eligible snapshot recencyOrder=[\(providerListDescription(providers: eligibleProviders, snapshot: snapshot))]")
    }

    static func logSelectorRun(
        eligibleActivities: [AnyLiveActivityPresentationProvider],
        snapshot: ActivityLivePresentationSnapshot,
        selection: ActivityLivePresentationStack
    ) {
        let candidates = providerListDescription(
            providers: eligibleActivities,
            snapshot: snapshot
        )
        let signature = "candidates=[\(candidates)] result=\(selection.debugSelectionDescription)"
        guard signature != lastSelectorSignature else { return }
        lastSelectorSignature = signature
        log("selector run \(signature)")
    }

    static func logContentViewPresentationChange(from oldValue: String, to newValue: String) {
        log("ContentView closed-notch presentation changed \(oldValue) -> \(newValue)")
    }

    private static func providerListDescription(
        providers: [AnyLiveActivityPresentationProvider],
        snapshot: ActivityLivePresentationSnapshot
    ) -> String {
        providers
            .map { provider in
                let sequence = snapshot.startedSequence(for: provider.id)
                    .map(String.init) ?? "registry-order"
                let priority = provider.livePresentationState.priority
                    .map { "\($0.rawValue)" } ?? "hidden"
                return "\(provider.id.rawValue)#seq=\(sequence)#priority=\(priority)"
            }
            .joined(separator: ", ")
    }

    private static func log(_ message: String) {
        print("[LiveActivityStack] \(message)")
    }
}
#endif

struct ExpandedActivityView: View {
    @ObservedObject var activity: AnyNotchActivity

    var body: some View {
        Group {
            if let height = activity.metadata.preferredExpandedHeight {
                activity.makeExpandedView()
                    .preferredOpenNotchHeight(height)
            } else {
                activity.makeExpandedView()
            }
        }
        .onAppear {
            activity.activityDidAppear()
        }
        .onDisappear {
            activity.activityDidDisappear()
        }
    }
}

struct ActivityConfigurationView: View {
    let activityID: ActivityID

    @ObservedObject private var registry = ActivityRegistry.shared

    var body: some View {
        if let activity = registry.activity(for: activityID), activity.supportsConfiguration {
            RegisteredActivityConfigurationView(activity: activity)
        } else {
            EmptyView()
        }
    }
}

private struct RegisteredActivityConfigurationView: View {
    @ObservedObject var activity: AnyNotchActivity

    var body: some View {
        activity.makeConfigurationView()
    }
}
