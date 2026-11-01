import SwiftUI

/// The help page: an editorial-style guide with a table of contents and search.
/// Texts come from Help.strings (Markdown), one per language.
struct HelpView: View {
    static let windowID = "help"

    @EnvironmentObject private var store: SettingsStore   // re-renders when the language changes
    @State private var query = ""
    @State private var selected: String?

    private struct Chapter: Identifiable {
        let id: String
        let number: Int
        let title: String
        let body: String
    }

    private var chapters: [Chapter] {
        HelpSections.ids.enumerated().map { i, id in
            Chapter(id: id, number: i + 1, title: L10n.help("help.\(id).title"), body: L10n.help(id == "clock" && Installer.clockInWallpaper ? "help.clock.body.wallpaper" : "help.\(id).body"))
        }
    }

    private var shown: [Chapter] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return chapters }
        return chapters.filter { chapter in
            [chapter.title, plain(chapter.body)].contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead.id("top")
                        if shown.isEmpty {
                            Text(L10n.help("help.noResults"))
                                .font(.system(size: 17, design: .serif).italic())
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 40)
                        }
                        ForEach(shown) { chapter in
                            article(chapter).id(chapter.id)
                        }
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(.horizontal, 56)
                    .padding(.vertical, 44)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: selected) {
                    guard let selected else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(selected, anchor: .top) }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .environment(\.layoutDirection, L10n.current.rightToLeft ? .rightToLeft : .leftToRight)
    }

    // MARK: - Parts

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                LucideIcon("search", size: 13).foregroundStyle(.secondary)
                TextField(L10n.help("help.search"), text: $query).textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))

            Text(L10n.help("help.contents").uppercased(with: L10n.locale))
                .font(.system(size: 11, weight: .semibold)).tracking(L10n.allowsTracking ? 1.4 : 0)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { chapter in
                        Button {
                            selected = chapter.id
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(String(format: "%02d", chapter.number))
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                Text(chapter.title).font(.system(size: 13.5, weight: selected == chapter.id ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(selected == chapter.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 250)
        .background(.background.secondary)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.help("help.kicker").uppercased(with: L10n.locale))
                .font(.system(size: 12, weight: .bold)).tracking(L10n.allowsTracking ? 2 : 0)
                .foregroundStyle(Color(nsColor: hex(0xc8102e)))
            Text(L10n.help("help.headline"))
                .font(.system(size: 42, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.help("help.lede"))
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().frame(height: 3).foregroundStyle(.primary).padding(.top, 10)
        }
        .padding(.bottom, 8)
    }

    private func article(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(String(format: "%02d", chapter.number))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: hex(0xc8102e)))
                Text(highlighted(chapter.title))
                    .font(.system(size: 26, weight: .bold, design: .serif))
            }
            ForEach(Array(chapter.body.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(block.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        lineView(line)
                    }
                }
            }
            Divider().padding(.top, 16)
        }
        .padding(.top, 26)
    }

    /// A paragraph line, or a list item for lines starting with "• " or "1. ".
    @ViewBuilder private func lineView(_ line: String) -> some View {
        let marker = line.range(of: #"^(•|\d+\.)\s+"#, options: .regularExpression)
        if let marker {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line[marker].trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: hex(0xc8102e)))
                    .frame(minWidth: 16, alignment: .leading)
                Text(highlighted(String(line[marker.upperBound...]))).font(.system(size: 15.5)).lineSpacing(4)
            }
        } else {
            Text(highlighted(line)).font(.system(size: 15.5)).lineSpacing(4)
        }
    }

    // MARK: - Text helpers

    /// Markdown to styled text, with search hits marked.
    private func highlighted(_ markdown: String) -> AttributedString {
        var text = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return text }
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex,
              let range = text[searchFrom...].range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].backgroundColor = Color.yellow.opacity(0.55)
            text[range].foregroundColor = .black
            searchFrom = range.upperBound
        }
        return text
    }

    private func plain(_ markdown: String) -> String {
        guard let text = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return markdown }
        return String(text.characters)
    }
}

/// "Help" menu item and button target.
struct HelpButton: View {
    @Environment(\.openWindow) private var openWindow
    var label = true

    var body: some View {
        Button {
            openWindow(id: HelpView.windowID)
        } label: {
            if label {
                Label { Text(L10n.help("help.button")) } icon: { LucideIcon("circle-help", size: 15) }
            } else {
                Text(L10n.help("help.title"))
            }
        }
    }
}
