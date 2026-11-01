import SwiftUI

struct OrderTab: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        let s = store.settings
        Form {
            Section {
                Picker(L("Order"), selection: $store.settings.orderMode) {
                    Label { Text(L("Take turns")) } icon: { LucideIcon("repeat") }.tag(NyheterSettings.OrderMode.turns)
                    Label { Text(L("In order")) } icon: { LucideIcon("list-ordered") }.tag(NyheterSettings.OrderMode.blocks)
                    Label { Text(L("Random")) } icon: { LucideIcon("shuffle") }.tag(NyheterSettings.OrderMode.random)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text(explanation(s.orderMode))
            }

            let enabled = s.enabledProviders.map(\.id)
            switch s.orderMode {
            case .turns:
                Section {
                    // Only sources in use are listed; entries for switched-off sources stay remembered.
                    let visible = s.turnPattern.indices.filter { enabled.contains(s.turnPattern[$0]) }
                    ForEach(Array(visible.enumerated()), id: \.element) { position, index in
                        row(s.turnPattern[index], at: position, count: visible.count,
                            up: { swapTurn(index, visible[max(0, position - 1)]) },
                            down: { swapTurn(index, visible[min(visible.count - 1, position + 1)]) },
                            remove: visible.count > 1 ? { store.settings.turnPattern.remove(at: index) } : nil)
                    }
                    Menu {
                        ForEach(s.enabledProviders) { provider in
                            Button(provider.name) { store.settings.turnPattern.append(provider.id) }
                        }
                    } label: {
                        Label { Text(L("Add to the rotation")) } icon: { LucideIcon("plus") }
                    }
                    .fixedSize()
                } header: {
                    SectionHeader(L("One round"), icon: "repeat")
                } footer: {
                    Text(L("The round repeats until the stories run out. Add a source several times to show it more often. Enabled sources missing from the list are added last."))
                }
            case .blocks:
                Section {
                    let order = Sources.unique(Sources.withMissingSources(s.blockOrder, enabled: enabled))
                    ForEach(Array(order.enumerated()), id: \.element) { i, id in
                        HStack {
                            LucideIcon("grip-vertical", size: 14).foregroundStyle(.secondary)
                            Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                            Text(Sources.provider(id)?.name ?? id)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .help(L("Drag to reorder"))
                        .draggable(id) {
                            Text(Sources.provider(id)?.name ?? id).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let dragged = items.first else { return false }
                            return moveBlock(order, dragged: dragged, onto: id)
                        }
                    }
                } header: {
                    SectionHeader(L("Sources in order"), icon: "list-ordered")
                }
            case .random:
                EmptyView()
            }

            Section {
                Stepper(value: $store.settings.maxPerSource, in: 1...NyheterSettings.maxStories) {
                    LabeledContent(L("Maximum per source"), value: "\(s.maxPerSource)")
                }
            } header: {
                SectionHeader(L("Amount"), icon: "layers")
            } footer: {
                Text(L("The rotation holds at most %d stories in total. The newest story from each source comes first.", NyheterSettings.maxStories))
            }

            Section {
                Text(sample(s)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeader(L("Preview"), icon: "eye")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ id: String, at i: Int, count: Int, up: @escaping () -> Void, down: @escaping () -> Void,
                     remove: (() -> Void)?) -> some View {
        HStack {
            Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
            Text(Sources.provider(id)?.name ?? id)
            Spacer()
            Button(action: up) { LucideIcon("chevron-up") }.disabled(i == 0)
            Button(action: down) { LucideIcon("chevron-down") }.disabled(i == count - 1)
            if let remove {
                Button(action: remove) { LucideIcon("circle-minus") }
            }
        }
        .buttonStyle(.borderless)
    }

    private func swapTurn(_ a: Int, _ b: Int) {
        guard a != b else { return }
        store.settings.turnPattern.swapAt(a, b)
    }

    /// Drops a source onto another's place (dragging down lands after it, up before it).
    /// Switched-off sources keep their remembered places at the end.
    private func moveBlock(_ visible: [String], dragged: String, onto target: String) -> Bool {
        guard dragged != target, let from = visible.firstIndex(of: dragged), let to = visible.firstIndex(of: target) else { return false }
        var order = visible
        order.remove(at: from)
        order.insert(dragged, at: to)
        withAnimation { store.settings.blockOrder = order + store.settings.blockOrder.filter { !visible.contains($0) } }
        return true
    }

    private func explanation(_ mode: NyheterSettings.OrderMode) -> String {
        switch mode {
        case .turns: return L("The sources take turns in a round you decide, one story at a time.")
        case .blocks: return L("All stories from the first source, then all from the next, and so on.")
        case .random: return L("All stories are shuffled. A new shuffle at every update.")
        }
    }

    private func sample(_ s: NyheterSettings) -> String {
        let enabled = s.enabledProviders.map(\.id)
        guard !enabled.isEmpty else { return L("No sources are enabled.") }
        switch s.orderMode {
        case .turns:
            let lap = Sources.withMissingSources(s.turnPattern, enabled: enabled)
            let sequence = (0..<12).map { Sources.label(lap[$0 % lap.count]) }
            return sequence.joined(separator: " → ") + " …"
        case .blocks:
            return Sources.unique(Sources.withMissingSources(s.blockOrder, enabled: enabled))
                .map { L("all from %@", Sources.label($0)) }.joined(separator: " → ")
        case .random:
            return L("For example:") + " " + (0..<10).map { _ in Sources.label(enabled.randomElement()!) }.joined(separator: " → ") + " …"
        }
    }
}
