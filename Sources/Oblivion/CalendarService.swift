import EventKit
import AppKit

struct CalendarMeeting: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarName: String
    var participants: [String]
    var location: String
    var notes: String
    var meetingURL: URL?
    var preparationContext: String {
        "Scheduled meeting\n\(title)\n\(start.formatted(date: .complete, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))\nCalendar \(calendarName)\nParticipants\n\(participants.joined(separator: "\n"))\nLocation\n\(location)\nEvent notes\n\(notes)"
    }
}

@MainActor final class CalendarService: ObservableObject {
    @Published private(set) var meetings: [CalendarMeeting] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var loading = false
    @Published var message: String?
    @Published var showSetup = false
    private let store = EKEventStore()
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    var connected: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess && defaults.bool(forKey: "calendarEnabled") }
    var selectedIDs: Set<String> { Set(defaults.stringArray(forKey: "calendarIDs") ?? []) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) }; refreshTask?.cancel() }
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.refresh()
        }
    }
    func connect() async {
        guard !loading else { return }
        loading = true; message = nil
        defer { loading = false }
        do {
            guard try await store.requestFullAccessToEvents() else { message = "Allow Calendar access in System Settings to see upcoming calls."; showSetup = true; return }
            defaults.set(true, forKey: "calendarEnabled")
            refresh(); showSetup = true
        } catch { message = error.localizedDescription; showSetup = true }
    }
    func toggleCalendar(_ id: String) {
        var ids = selectedIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        defaults.set(Array(ids), forKey: "calendarIDs"); refresh()
    }
    func disconnect() {
        defaults.set(false, forKey: "calendarEnabled"); defaults.removeObject(forKey: "calendarIDs")
        meetings = []; calendars = []; message = nil
    }
    func refresh() {
        guard connected else { meetings = []; return }
        calendars = store.calendars(for: .event).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if defaults.object(forKey: "calendarIDs") == nil {
            let google = calendars.filter { $0.source.title.localizedCaseInsensitiveContains("google") || $0.source.title.localizedCaseInsensitiveContains("gmail") }
            defaults.set(google.map(\.calendarIdentifier), forKey: "calendarIDs")
        }
        let chosen = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { meetings = []; return }
        let now = Date(), end = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: chosen)
        meetings = store.events(matching: predicate).filter {
            !$0.isAllDay && $0.endDate > now && $0.status != .canceled && !($0.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }.sorted { $0.startDate < $1.startDate }.prefix(100).map { event in
            let location = event.location ?? "", notes = String((event.notes ?? "").prefix(12000))
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let text = location + "\n" + notes
            let url = event.url ?? detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first { url in
                let host = url.host?.lowercased() ?? ""
                return host == "meet.google.com" || host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "teams.microsoft.com"
            }
            return CalendarMeeting(id: (event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? event.calendarItemIdentifier) + "/" + String(event.startDate.timeIntervalSince1970), title: event.title ?? "Scheduled call", start: event.startDate, end: event.endDate, calendarName: event.calendar.title, participants: event.attendees?.map { $0.name ?? $0.url.absoluteString } ?? [], location: location, notes: notes, meetingURL: url)
        }
    }
}
