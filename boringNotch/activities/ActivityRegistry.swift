import Combine
import Defaults
import Foundation

enum ActivityRegistryError: Error, Equatable {
    case duplicateID(ActivityID)
}

@resultBuilder
enum ActivityRegistryBuilder {
    @MainActor
    static func buildExpression<Activity: NotchActivity>(
        _ activity: Activity
    ) -> [AnyNotchActivity] {
        [AnyNotchActivity(activity)]
    }

    static func buildBlock(_ components: [AnyNotchActivity]...) -> [AnyNotchActivity] {
        components.flatMap { $0 }
    }

    static func buildOptional(_ component: [AnyNotchActivity]?) -> [AnyNotchActivity] {
        component ?? []
    }

    static func buildEither(first component: [AnyNotchActivity]) -> [AnyNotchActivity] {
        component
    }

    static func buildEither(second component: [AnyNotchActivity]) -> [AnyNotchActivity] {
        component
    }

    static func buildArray(_ components: [[AnyNotchActivity]]) -> [AnyNotchActivity] {
        components.flatMap { $0 }
    }
}

@MainActor
final class ActivityEnablementStore: ObservableObject {
    static let shared: ActivityEnablementStore = {
        let store = ActivityEnablementStore(
            disabledActivityIDs: Set(Defaults[.disabledActivityIDs].map { ActivityID($0) }),
            persist: { disabledActivityIDs in
                Defaults[.disabledActivityIDs] = disabledActivityIDs
            }
        )

        store.defaultsObservation = Defaults.publisher(.disabledActivityIDs)
            .map { Set($0.newValue.map { ActivityID($0) }) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak store] disabledActivityIDs in
                guard store?.disabledActivityIDs != disabledActivityIDs else { return }
                store?.disabledActivityIDs = disabledActivityIDs
            }

        return store
    }()

    @Published private(set) var disabledActivityIDs: Set<ActivityID>

    private let persist: (([String]) -> Void)?
    private var defaultsObservation: AnyCancellable?

    init(
        disabledActivityIDs: Set<ActivityID> = [],
        persist: (([String]) -> Void)? = nil
    ) {
        self.disabledActivityIDs = disabledActivityIDs
        self.persist = persist
    }

    func isEnabled(_ activityID: ActivityID) -> Bool {
        !disabledActivityIDs.contains(activityID)
    }

    func setEnabled(_ isEnabled: Bool, for activityID: ActivityID) {
        var nextDisabledActivityIDs = disabledActivityIDs
        if isEnabled {
            nextDisabledActivityIDs.remove(activityID)
        } else {
            nextDisabledActivityIDs.insert(activityID)
        }

        guard nextDisabledActivityIDs != disabledActivityIDs else { return }
        disabledActivityIDs = nextDisabledActivityIDs
        persist?(nextDisabledActivityIDs.map(\.rawValue).sorted())
    }
}

@MainActor
final class ActivityChinVisibilityStore: ObservableObject {
    static let shared: ActivityChinVisibilityStore = {
        var hiddenActivityIDs = Set(Defaults[.activityIDsHiddenFromChin].map { ActivityID($0) })
        hiddenActivityIDs.insert(.quickNotes)

        let persistedHiddenActivityIDs = hiddenActivityIDs.map(\.rawValue).sorted()
        if Defaults[.activityIDsHiddenFromChin] != persistedHiddenActivityIDs {
            Defaults[.activityIDsHiddenFromChin] = persistedHiddenActivityIDs
        }

        let store = ActivityChinVisibilityStore(
            hiddenActivityIDs: hiddenActivityIDs,
            persist: { hiddenActivityIDs in
                Defaults[.activityIDsHiddenFromChin] = hiddenActivityIDs
            }
        )

        store.defaultsObservation = Defaults.publisher(.activityIDsHiddenFromChin)
            .map { Set($0.newValue.map { ActivityID($0) }) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak store] hiddenActivityIDs in
                guard store?.hiddenActivityIDs != hiddenActivityIDs else { return }
                store?.hiddenActivityIDs = hiddenActivityIDs
            }

        return store
    }()

    @Published private(set) var hiddenActivityIDs: Set<ActivityID>

    private let persist: (([String]) -> Void)?
    private var defaultsObservation: AnyCancellable?

    init(
        hiddenActivityIDs: Set<ActivityID> = [],
        persist: (([String]) -> Void)? = nil
    ) {
        self.hiddenActivityIDs = hiddenActivityIDs
        self.persist = persist
    }

    func isShown(_ activityID: ActivityID) -> Bool {
        !hiddenActivityIDs.contains(activityID)
    }

    func setShown(_ isShown: Bool, for activityID: ActivityID) {
        var nextHiddenActivityIDs = hiddenActivityIDs
        if isShown {
            nextHiddenActivityIDs.remove(activityID)
        } else {
            nextHiddenActivityIDs.insert(activityID)
        }

        guard nextHiddenActivityIDs != hiddenActivityIDs else { return }
        hiddenActivityIDs = nextHiddenActivityIDs
        persist?(nextHiddenActivityIDs.map(\.rawValue).sorted())
    }
}

@MainActor
final class ActivityRegistry: ObservableObject {
    static let shared: ActivityRegistry = {
        do {
            return try ActivityRegistry(enablementStore: .shared, chinVisibilityStore: .shared) {
                CalendarActivity()
                PomodoroActivity()
                QuickNotesActivity()
                DobermanActivity()
            }
        } catch {
            preconditionFailure("Invalid default activity registry: \(error)")
        }
    }()

    let activities: [AnyNotchActivity]

    private let activitiesByID: [ActivityID: AnyNotchActivity]
    private let enablementStore: ActivityEnablementStore
    private let chinVisibilityStore: ActivityChinVisibilityStore
    private var activityObservations: Set<AnyCancellable> = []
    private var enablementObservation: AnyCancellable?
    private var chinVisibilityObservation: AnyCancellable?

    init(
        enablementStore: ActivityEnablementStore? = nil,
        chinVisibilityStore: ActivityChinVisibilityStore? = nil,
        @ActivityRegistryBuilder activities: () -> [AnyNotchActivity]
    ) throws {
        let registeredActivities = activities()
        let resolvedEnablementStore = enablementStore ?? ActivityEnablementStore()
        let resolvedChinVisibilityStore = chinVisibilityStore ?? ActivityChinVisibilityStore()
        var indexedActivities: [ActivityID: AnyNotchActivity] = [:]

        for activity in registeredActivities {
            guard indexedActivities[activity.id] == nil else {
                throw ActivityRegistryError.duplicateID(activity.id)
            }
            indexedActivities[activity.id] = activity
        }

        self.activities = registeredActivities
        self.enablementStore = resolvedEnablementStore
        self.chinVisibilityStore = resolvedChinVisibilityStore
        activitiesByID = indexedActivities

        for activity in registeredActivities {
            activity.objectWillChange
                .sink { [weak self] in
                    self?.objectWillChange.send()
                }
                .store(in: &activityObservations)
        }

        enablementObservation = resolvedEnablementStore.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }

        chinVisibilityObservation = resolvedChinVisibilityStore.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
    }

    var enabledActivities: [AnyNotchActivity] {
        activities.filter { enablementStore.isEnabled($0.id) }
    }

    var availableActivities: [AnyNotchActivity] {
        enabledActivities.filter(\.isAvailable)
    }

    var availableActivityIDs: [ActivityID] {
        availableActivities.map(\.id)
    }

    var activeActivities: [AnyNotchActivity] {
        availableActivities.filter(\.isActive)
    }

    func activity(for id: ActivityID) -> AnyNotchActivity? {
        activitiesByID[id]
    }

    func isActivityEnabled(_ id: ActivityID) -> Bool {
        activitiesByID[id] != nil && enablementStore.isEnabled(id)
    }

    func isActivityAvailable(_ id: ActivityID) -> Bool {
        guard isActivityEnabled(id), let activity = activitiesByID[id] else { return false }
        return activity.isAvailable
    }

    func isActivityShownOnChin(_ id: ActivityID) -> Bool {
        activitiesByID[id] != nil && chinVisibilityStore.isShown(id)
    }

    func setActivityEnabled(_ isEnabled: Bool, for id: ActivityID) {
        guard activitiesByID[id] != nil else { return }
        enablementStore.setEnabled(isEnabled, for: id)
    }

    func setActivityShownOnChin(_ isShown: Bool, for id: ActivityID) {
        guard activitiesByID[id] != nil else { return }
        chinVisibilityStore.setShown(isShown, for: id)
    }
}
