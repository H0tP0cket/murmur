import SwiftUI
import AppKit

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var calendar: CalendarService
    private var calls: [CallRecord] {
        state.calls.filter { !$0.archived && (state.selectedFolderID == nil || $0.folderID == state.selectedFolderID) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(state.selectedFolder?.name ?? "Your next conversation.").font(.system(size: 29, weight: .medium)).tracking(-0.6)
                    Text(state.selectedFolder == nil ? "A little preparation goes a long way." : "Every call, together in one place.").font(.system(size: 14)).foregroundStyle(.secondary)
                }.padding(.top, 24)
                if state.selectedFolder == nil { upcoming }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(state.selectedFolder == nil ? "Recent calls" : "Calls").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button { state.newCall() } label: { Label("New call", systemImage: "plus") }.buttonStyle(.bordered).controlSize(.small)
                    }
                    if calls.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Make room for a great conversation.").font(.system(size: 17, weight: .medium))
                            Text("Start a chat to bring your context, questions, and ideas together.").font(.system(size: 13)).foregroundStyle(.secondary)
                            Button("Prepare a call") { state.newCall() }.buttonStyle(.bordered).padding(.top, 4)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(calls) { call in
                                Button { state.selectedID = call.id } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: call.sessions.isEmpty ? "bubble.left" : "waveform").font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 34, height: 38)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(call.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                            if let name = state.folders.first(where: { $0.id == call.folderID })?.name { Text(name).font(.system(size: 12)).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        Text(call.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.system(size: 12)).foregroundStyle(.tertiary)
                                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                                }.buttonStyle(QuietButtonStyle()).contextMenu { CallFolderMenu(callID: call.id) }
                            }
                        }
                    }
                }
            }.frame(maxWidth: 770).padding(.horizontal, 40).padding(.bottom, 40).frame(maxWidth: .infinity)
        }.task { calendar.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in calendar.scheduleRefresh() }
            .sheet(isPresented: $calendar.showSetup) { CalendarSetupView(calendar: calendar) }
    }
    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Coming up").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if calendar.loading { ProgressView().controlSize(.small) }
                Button(calendar.connected ? "Calendars" : "Sync Google Calendar") {
                    if calendar.connected { calendar.refresh(); calendar.showSetup = true } else { Task { await calendar.connect() } }
                }.buttonStyle(.bordered).controlSize(.small).disabled(calendar.loading)
            }
            if calendar.meetings.isEmpty {
                HStack(spacing: 15) {
                    Image(systemName: "calendar").font(.system(size: 22)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(calendar.connected ? "A little breathing room." : "Your calendar, ready to prep.").font(.system(size: 15, weight: .medium))
                        Text(calendar.connected ? "No upcoming events in your selected calendars over the next two weeks." : "Connect your calendar to turn an upcoming meeting into a prep chat.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09)))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(calendar.meetings.prefix(8).enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 20) }
                        HStack(spacing: 18) {
                            VStack(spacing: 1) {
                                Text(event.start, format: .dateTime.day()).font(.system(size: 25, weight: .medium)).monospacedDigit()
                                Text(event.start, format: .dateTime.month(.abbreviated)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.frame(width: 38)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                Text("\(event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())) – \(event.end.formatted(date: .omitted, time: .shortened))").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button(state.calls.contains(where: { $0.calendarEventID == event.id }) ? "Open chat" : "Prepare") { state.prepareEvent(event) }.buttonStyle(.bordered).controlSize(.small)
                                .contextMenu { ForEach(state.folders) { folder in Button("Prepare in \(folder.name)") { state.prepareEvent(event, folderID: folder.id) } } }
                        }.padding(20)
                    }
                }.background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09)))
            }
        }
    }
}

struct CallFolderMenu: View {
    @EnvironmentObject var state: AppState
    let callID: UUID
    var body: some View {
        Menu("Move to folder") {
            Button("No folder") { state.moveCall(callID, to: nil) }
            ForEach(state.folders) { folder in Button(folder.name) { state.moveCall(callID, to: folder.id) } }
        }
    }
}

struct CalendarSetupView: View {
    @ObservedObject var calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Your calendars").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Connect Google in macOS Internet Accounts and enable Calendars. MurMur reads only the calendars you select here and never changes events.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            Button("Connect Google in System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!) }
            if let message = calendar.message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
            if calendar.calendars.isEmpty {
                Text("After connecting Google, return here and refresh to choose your calendars.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                            Toggle(isOn: Binding(get: { calendar.selectedIDs.contains(item.calendarIdentifier) }, set: { _ in calendar.toggleCalendar(item.calendarIdentifier) })) {
                                VStack(alignment: .leading, spacing: 3) { Text(item.title); Text(item.source.title).font(.system(size: 11)).foregroundStyle(.secondary) }
                            }.toggleStyle(.checkbox)
                        }
                    }.padding(4)
                }.frame(maxHeight: 230)
            }
            HStack {
                Button("Refresh calendars") { Task { await calendar.connect() } }.disabled(calendar.loading)
                Spacer()
                if calendar.connected { Button("Disconnect") { calendar.disconnect(); dismiss() }.foregroundStyle(.secondary) }
            }
            Text("Your calendar stays on this Mac. Only details of an event you choose to prepare become context for its chat.").font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(3)
        }.padding(26).frame(width: 500)
    }
}
