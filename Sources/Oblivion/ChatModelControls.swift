import SwiftUI

/// Observe the catalog directly; it loads independently of the conversation.
struct ChatModelControls: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var service: CodexService
    @AppStorage("prepModel") private var defaultModel = ""
    @AppStorage("prepEffort") private var defaultEffort = ""

    private var modelID: String? {
        if let saved = state.selected?.prepModel { return saved }
        if service.models.contains(where: { $0.id == defaultModel }) { return defaultModel }
        return service.model(live: false)
    }
    private var option: ModelOption? { service.models.first { $0.id == modelID } }
    private var effort: String? {
        let preference = state.selected == nil ? defaultEffort : state.selected?.prepEffort
        return try? service.turnSelection(modelOverride: modelID, effortOverride: preference).effort
    }
    private func effortName(_ value: String) -> String {
        ["xhigh": "Extra high", "none": "None"][value] ?? value.capitalized
    }

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Menu {
                Button("Automatic") { setModel(nil) }
                Divider()
                ForEach(service.models) { model in
                    Button { setModel(model.id) } label: {
                        if model.id == modelID { Label(model.name, systemImage: "checkmark") }
                        else { Text(model.name) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(option?.name ?? (modelID == nil ? "Connecting…" : "Model unavailable")).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.padding(.horizontal, 7).padding(.vertical, 4).contentShape(Rectangle())
            }.accessibilityLabel("Chat model").help("Model for this chat")
            if let option, !option.efforts.isEmpty {
                Menu {
                    ForEach(option.efforts, id: \.self) { value in
                        Button { setEffort(value) } label: {
                            if value == effort { Label(effortName(value), systemImage: "checkmark") }
                            else { Text(effortName(value)) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(effortName(effort ?? option.defaultEffort))
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }.padding(.horizontal, 7).padding(.vertical, 4).contentShape(Rectangle())
                }.accessibilityLabel("Reasoning effort").help("How much reasoning to use for this chat")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
        .disabled(state.isBusy || service.models.isEmpty)
    }

    private func setModel(_ model: String?) {
        if let id = state.selectedID { state.setChatModel(model, callID: id) }
        else { defaultModel = model ?? ""; defaultEffort = "" }
    }
    private func setEffort(_ effort: String) {
        if let id = state.selectedID { state.modify(id) { $0.prepEffort = effort } }
        else { defaultEffort = effort }
    }
}
