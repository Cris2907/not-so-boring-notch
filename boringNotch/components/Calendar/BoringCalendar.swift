//
//  BoringCalendar.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import AppKit
import Defaults
import SwiftUI

struct CalendarMonthDay: Equatable {
    let date: Date
    let isInDisplayedMonth: Bool
}

enum CalendarMonthLayout {
    static func days(containing date: Date, calendar: Calendar = .current) -> [CalendarMonthDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstDay = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstDay) else {
            return []
        }

        return (0..<42).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            return CalendarMonthDay(
                date: day,
                isInDisplayedMonth: calendar.isDate(day, equalTo: firstDay, toGranularity: .month)
            )
        }
    }

    static func movingMonth(
        from selectedDate: Date,
        by value: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard let selectedMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start,
              let destinationMonth = calendar.date(byAdding: .month, value: value, to: selectedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: destinationMonth)
        else { return nil }

        var components = calendar.dateComponents([.era, .year, .month], from: destinationMonth)
        components.day = min(calendar.component(.day, from: selectedDate), dayRange.count)
        components.hour = 12
        return calendar.date(from: components)
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(0, min(calendar.firstWeekday - 1, symbols.count - 1))
        return Array(symbols[start...] + symbols[..<start])
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var webcamManager = WebcamManager.shared
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @State private var monthSwipeAccumulator = HorizontalSwipeAccumulator(threshold: 18)
    @State private var haptics = false

    private let calendar = Calendar.current
    private let dayColumns = Array(
        repeating: GridItem(.flexible(minimum: 20), spacing: 2),
        count: 7
    )

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            monthColumn
                .frame(width: 275)

            Divider()
                .overlay(.red.opacity(0.22))

            eventsColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .contentShape(Rectangle())
        .optionHorizontalTrackpadSwipe(isEnabled: true, allowsInertia: false) { delta, phase in
            handleMonthSwipe(delta: delta, phase: phase)
        }
        .sensoryFeedback(.alignment, trigger: haptics)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar")
        .onChange(of: selectedDate) { _, newDate in
            Task {
                await calendarManager.updateCurrentDate(newDate)
            }
        }
        .onAppear {
            let today = Date.now
            selectedDate = today
            displayedMonth = today
            if vm.isCameraExpanded {
                webcamManager.stopSession()
                vm.isCameraExpanded = false
            }
            Task {
                await calendarManager.updateCurrentDate(today)
            }
        }
    }

    private var monthColumn: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                monthButton(icon: "chevron.left", label: "Previous month") {
                    moveMonth(by: -1)
                }
                monthButton(icon: "chevron.right", label: "Next month") {
                    moveMonth(by: 1)
                }
            }

            LazyVGrid(columns: dayColumns, spacing: 2) {
                ForEach(Array(CalendarMonthLayout.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red.opacity(0.78))
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(CalendarMonthLayout.days(containing: displayedMonth, calendar: calendar).enumerated()), id: \.offset) { _, day in
                    dayButton(day)
                }
            }
        }
        .accessibilityHint("Hold Option and swipe horizontally with two fingers to change months")
    }

    private var eventsColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(selectedDate.formatted(.dateTime.year()))
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.82))
            }

            let filteredEvents = EventListView.filteredEvents(events: calendarManager.events)
            if filteredEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EventListView(events: calendarManager.events)
            }
        }
    }

    private func monthButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 20, height: 18)
                .background(.red.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: CalendarMonthDay) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day.date)

        return Button {
            select(day.date)
        } label: {
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: 10, weight: isSelected || isToday ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(day.isInDisplayedMonth ? 0.82 : 0.34))
                .frame(maxWidth: .infinity)
                .frame(height: 15)
                .background {
                    if isSelected {
                        Circle().fill(.red)
                    } else if isToday {
                        Circle().stroke(.red, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ date: Date) {
        selectedDate = date
        displayedMonth = date
        provideHapticFeedback()
    }

    private func moveMonth(by value: Int) {
        guard let destination = CalendarMonthLayout.movingMonth(
            from: selectedDate,
            by: value,
            calendar: calendar
        ) else { return }

        withAnimation(.smooth(duration: 0.2)) {
            selectedDate = destination
            displayedMonth = destination
        }
        provideHapticFeedback()
    }

    private func handleMonthSwipe(delta: CGFloat, phase: NSEvent.Phase) {
        if phase == .began || phase == .ended || phase == .cancelled {
            monthSwipeAccumulator.reset()
            return
        }

        guard let direction = monthSwipeAccumulator.consume(delta: delta) else { return }
        moveMonth(by: direction == .left ? 1 : -1)
    }

    private func provideHapticFeedback() {
        guard Defaults[.enableHaptics] else { return }
        haptics.toggle()
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date
    
    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

struct CalendarLivePresentationView: View {
    @ObservedObject var manager: CalendarManager
    let now: () -> Date

    var body: some View {
        if let event = CalendarLiveEventSelector.select(from: manager.events, at: now()) {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(event.end, style: .time)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text("\(event.title), ends \(event.end.formatted(date: .omitted, time: .shortened))")
            )
        }
    }
}

struct CalendarMinimalLivePresentationView: View {
    @ObservedObject var manager: CalendarManager
    let now: () -> Date

    var body: some View {
        if let event = CalendarLiveEventSelector.select(from: manager.events, at: now()) {
            Text(event.end, style: .time)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel(
                    Text("\(event.title), ends \(event.end.formatted(date: .omitted, time: .shortened))")
                )
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles


    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !Defaults[.hideCompletedReminders]
                }
            }
            // Filter out all-day events if setting is enabled
            if event.isAllDay && Defaults[.hideAllDayEvents] {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(events: events)
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let now = Date()
        // Determine a single target using preferred search order:
        // 1) first non-all-day upcoming/in-progress event
        // 2) first all-day event
        // 3) last event (fallback)
        let nonAllDayUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.end > now })
        let firstAllDay = filteredEvents.first(where: { $0.isAllDay })
        let lastEvent = filteredEvents.last
        guard let target = nonAllDayUpcoming ?? firstAllDay ?? lastEvent else { return }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredEvents) { event in
                    Button(action: {
                        if let url = event.calendarAppURL() {
                            openURL(url)
                        }
                    }) {
                        eventRow(event)
                    }
                    .id(event.id)
                    .padding(.leading, -5)
                    .buttonStyle(PlainButtonStyle())
                    .listRowSeparator(.automatic)
                    .listRowSeparatorTint(.gray.opacity(0.2))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                scrollToRelevantEvent(proxy: proxy)
            }
            .onChange(of: filteredEvents) { _, _ in
                scrollToRelevantEvent(proxy: proxy)
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type {
                isCompleted = completed
            } else {
                isCompleted = false
            }
            return AnyView(
                HStack(spacing: 8) {
                    ReminderToggle(
                        isOn: Binding(
                            get: { isCompleted },
                            set: { newValue in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: newValue
                                    )
                                }
                            }
                        ),
                        color: Color(event.calendar.color)
                    )
                    .opacity(1.0)  // Ensure the toggle is always fully opaque
                    HStack {
                        Text(event.title)
                            .font(.callout)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            } else {
                                Text(event.start, style: .time)
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                    }
                    .opacity(
                        isCompleted
                            ? 0.4
                            : event.start < Date.now && Calendar.current.isDateInToday(event.start)
                                ? 0.6 : 1.0
                    )
                }
                .padding(.vertical, 4)
            )
        } else {
            return AnyView(
                HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(.white)
                            Text(event.end, style: .time)
                                .foregroundColor(Color(white: 0.65))
                        }
                    }
                    .font(.caption)
                    .frame(minWidth: 44, alignment: .trailing)
                }
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.6 : 1.0)
            )
        }
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                // Inner fill
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

#Preview {
    CalendarView()
        .frame(width: 215, height: 130)
        .background(.black)
        .environmentObject(BoringViewModel())
}
