import SwiftUI
import AppKit

struct DetailView: View {
    @EnvironmentObject var state: AppState
    var detail: AppState.Detail
    @State private var search = ""
    @State private var editingSegment: TranscriptSegment?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(detail.rawValue).font(.system(size: 14, weight: .semibold)); Spacer(); Button { state.detail = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary) }.padding(20)
            if let call = state.selected {
                switch detail {
                case .notes: notes(call)
                case .stories: stories(call)
                case .transcript: transcript(call)
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
            .sheet(item: $editingSegment) { segment in TranscriptEditor(segment: segment) { text, speaker in
                if let id = state.selectedID { state.modify(id) { record in if let index = record.transcript.firstIndex(where: { $0.id == segment.id }) { record.transcript[index].correction = text == segment.original ? nil : text; record.transcript[index].speaker = speaker } } }
                editingSegment = nil
            } }
    }

    private func notes(_ call: CallRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR NOTES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { state.selected?.notes ?? "" }, set: { value in state.modify(call.id) { $0.notes = value } })).font(.system(size: 13)).scrollContentBackground(.hidden).frame(minHeight: 190).padding(6).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                HStack { Text("CALL NOTES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary); Spacer(); Button { state.updateNotes(callID: call.id) } label: { Label("Update", systemImage: "sparkles") }.font(.system(size: 11)).disabled(state.notesBusy.contains(call.id)) }
                if call.generatedNotes.isEmpty { Text("Findings, open questions, and follow-ups will live here. Your own notes above stay yours.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4) }
                else { TextEditor(text: Binding(get: { state.selected?.generatedNotes ?? "" }, set: { value in state.modify(call.id) { $0.generatedNotes = value; $0.generatedNotesEdited = true } })).font(.system(size: 13)).scrollContentBackground(.hidden).frame(minHeight: 320) }
                if let suggestion = call.suggestedNotes {
                    DisclosureGroup("Updated notes ready") {
                        Text(suggestion).font(.system(size: 12)).textSelection(.enabled).padding(.vertical, 8)
                        HStack {
                            Button("Replace call notes") { state.modify(call.id) { $0.generatedNotes = suggestion; $0.suggestedNotes = nil; $0.generatedNotesEdited = false } }
                            Button("Dismiss") { state.modify(call.id) { $0.suggestedNotes = nil } }
                        }.font(.system(size: 11))
                    }
                    Text("Your edits are preserved until you accept an update.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button("Ask about these notes") { state.composer = "What are the most important takeaways from my notes?" }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private func stories(_ call: CallRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Full answers, in your words. Save a chat response or add one here.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                Button { state.editingStory = PreparedStory(title: "", body: "") } label: { Label("Add prepared answer", systemImage: "plus") }.controlSize(.small)
                ForEach(call.stories) { story in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(story.title).font(.system(size: 13, weight: .semibold)); Spacer(); Image(systemName: story.approved ? "checkmark.seal" : "pencil").foregroundStyle(.secondary) }
                        if !story.cues.isEmpty { Text(story.cues).font(.system(size: 11)).foregroundStyle(.secondary) }
                        Text(story.body).font(.system(size: 12)).lineLimit(4).foregroundStyle(.secondary)
                        HStack { Button("Edit") { state.editingStory = story }; Spacer(); Button("Use now") { state.useStory(story) }.disabled(state.activeCallID != call.id) }.buttonStyle(.plain).font(.system(size: 11))
                    }.padding(13).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private func transcript(_ call: CallRecord) -> some View {
        VStack(spacing: 12) {
            HStack { Image(systemName: "magnifyingglass"); TextField("Search transcript", text: $search).textFieldStyle(.plain) }.font(.system(size: 12)).padding(9).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18)
            if call.transcript.isEmpty {
                ContentUnavailableView("Your conversation, captured", systemImage: "waveform", description: Text("Start a call to transcribe on this Mac, or import a transcript."))
                Button("Import transcript…") { state.importTranscript() }.padding(.bottom, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(call.transcript.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || $0.speaker.localizedCaseInsensitiveContains(search) }) { segment in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(segment.timestamp).monospacedDigit(); Text(segment.speaker).fontWeight(.medium); Spacer(); if !segment.isFinal { Text("live") } }
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(segment.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).foregroundStyle(segment.isFinal ? .primary : .secondary)
                                HStack {
                                    Button("Ask about this") { state.composer = "Help me understand this part of the call [\(segment.timestamp), \(segment.speaker)]:\n\"\(segment.text)\"" }
                                    Button("Edit") { editingSegment = segment }
                                    if segment.correction != nil { Text("Edited").foregroundStyle(.tertiary) }
                                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.id(segment.id)
                        }
                        ForEach(call.sessions.flatMap(\.interruptions), id: \.self) { issue in Label(issue, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange) }
                    }.padding(.horizontal, 20).padding(.bottom, 24)
                }.defaultScrollAnchor(.bottom)
                HStack { Text("\(call.transcript.count) passages"); Spacer(); Button("Export") { state.exportCall() } }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 15)
            }
        }.frame(maxHeight: .infinity)
    }
}

struct StoryEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var story: PreparedStory
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prepared answer").font(.title2.weight(.semibold))
            TextField("Title", text: $story.title).textFieldStyle(.roundedBorder)
            TextField("Questions this answer fits", text: $story.cues).textFieldStyle(.roundedBorder)
            TextEditor(text: $story.body).font(.system(size: 14)).padding(8).frame(minHeight: 280).overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.12)))
            Toggle("Approved wording — use this full answer during calls", isOn: $story.approved).font(.system(size: 12))
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save answer") { if story.title.isEmpty { story.title = "Prepared answer" }; state.saveStory(story); dismiss() }.keyboardShortcut(.defaultAction).disabled(story.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width: 570)
    }
}

struct TranscriptEditor: View {
    @Environment(\.dismiss) private var dismiss
    var segment: TranscriptSegment
    var save: (String, String) -> Void
    @State private var text = ""
    @State private var speaker = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit transcript · \(segment.timestamp)").font(.title2.weight(.semibold))
            TextField("Speaker", text: $speaker).textFieldStyle(.roundedBorder)
            TextEditor(text: $text).font(.system(size: 14)).frame(height: 180).padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.1)))
            Text("Original: \(segment.original)").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Restore original") { text = segment.original }; Spacer(); Button("Save") { save(text, speaker); dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 520).onAppear { text = segment.text; speaker = segment.speaker }
    }
}

struct CallSetupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "waveform").font(.system(size: 28)).padding(.bottom, 2)
            Text("Ready for your conversation?").font(.system(size: 24, weight: .semibold))
            Text("Oblivion listens to your microphone and meeting audio, transcribes on this Mac, and uses your preparation to help you in the moment.").font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            Picker("Meeting audio", selection: $state.audioSource) {
                Text("All system audio").tag("")
                Text("Google Chrome (Meet)").tag("com.google.Chrome")
                Text("Zoom Workplace").tag("us.zoom.xos")
            }.pickerStyle(.menu)
            VStack(alignment: .leading, spacing: 7) {
                Label("Share a meeting tab or a separate application window.", systemImage: "macwindow")
                Text("A full-display share may include the floating copilot. ⌘⇧Space instantly hides it. Tell participants you’re transcribing when appropriate.")
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(14).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            Text("Transcripts are saved locally. Relevant text goes to Codex for advice. Raw audio recordings are not saved.").font(.system(size: 11)).foregroundStyle(.tertiary)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Start in chat") { Task { await state.startCall(popOut: false) } }; Button("Start & pop out") { Task { await state.startCall() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.primary) }
        }.padding(30).frame(width: 510)
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("personalBackground") private var background = ""
    @AppStorage("prepModel") private var prepModel = ""
    @AppStorage("liveModel") private var liveModel = ""
    @AppStorage("codexPath") private var codexPath = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Settings").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Form {
                Section("Personal context") {
                    Text("Your background, preferred introduction, and facts you want available across calls.").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextEditor(text: $background).font(.system(size: 13)).frame(height: 100)
                }
                Section("Appearance") { Picker("Theme", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") } }
                Section("Codex") {
                    CodexStatusView(service: state.codex)
                    Picker("Preparation", selection: $prepModel) { Text("Automatic").tag(""); ForEach(state.codex.models) { Text($0.name).tag($0.id) } }
                    Picker("Live coaching", selection: $liveModel) { Text("Automatic · fast").tag(""); ForEach(state.codex.models) { Text($0.name).tag($0.id) } }
                    TextField("Executable path (optional)", text: $codexPath)
                    Button("Reconnect") { state.codex.disconnect(); Task { await state.reconnect() } }
                }
                Section("Speaker names") {
                    AttributionStatusView(attribution: state.attribution)
                    Button("Set up Meet companion…") {
                        do { let folder = try state.attribution.installMeetCompanion(root: state.library.root); NSWorkspace.shared.open(folder) }
                        catch { state.error = error.localizedDescription }
                    }
                    Text("In chrome://extensions, enable Developer mode, choose Load unpacked, and select the Meet folder. In a meeting, open the extension and choose Use this meeting.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Allow Zoom Accessibility") { state.attribution.requestAccessibility() }
                }
                Section("Call shortcuts") {
                    LabeledContent("Hide / show", value: "⌘⇧Space")
                    LabeledContent("Return to chat", value: "⌘⇧X")
                    LabeledContent("Ask copilot anywhere", value: "⌘⌥K")
                    Text("⌘K also opens questions inside the call window. ⌘X keeps its normal Cut behavior.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("Your library") { Button("Show local files") { NSWorkspace.shared.open(state.library.root) }; Text("No raw audio recordings are retained.").font(.system(size: 11)).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
        }.padding(24).frame(width: 560, height: 680)
    }
}

struct CodexStatusView: View {
    @ObservedObject var service: CodexService
    var body: some View { Label(service.status, systemImage: service.isConnected ? "checkmark.circle" : "circle.dotted").font(.system(size: 12)).foregroundStyle(service.isConnected ? Color.green : Color.secondary) }
}

struct AttributionStatusView: View {
    @ObservedObject var attribution: MeetingAttribution
    var body: some View { Text(attribution.status).font(.system(size: 12)).foregroundStyle(.secondary) }
}
