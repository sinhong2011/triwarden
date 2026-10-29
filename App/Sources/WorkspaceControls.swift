import SwiftUI

/// Management-page controls share the vault toolbar's height and chrome, without its vault-search token behavior.
struct WorkspaceSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var moveToList: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13)).focused(focused)
                .onKeyPress(.escape) { guard !text.isEmpty else { return .ignored }; text = ""; return .handled }
                .onKeyPress(.downArrow) { guard let moveToList else { return .ignored }; moveToList(); return .handled }
            if !text.isEmpty {
                Button { text = ""; focused.wrappedValue = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                }.buttonStyle(.plain).accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 12).frame(height: 32)
        .modifier(HeaderChrome(shape: .capsule, hovering: hovering || focused.wrappedValue))
        .contentShape(.capsule).onTapGesture { focused.wrappedValue = true }.onHover { hovering = $0 }
    }
}

struct WorkspaceFilter<Value: Hashable>: View {
    let title: LocalizedStringKey
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        ActionMenu(entries: options.map { option in
            ActionMenuEntry(title: option.1, checked: selection == option.0) { selection = option.0 }
        }) {
            HStack(spacing: 8) {
                Text(verbatim: options.first { $0.0 == selection }?.1 ?? "").font(.system(size: 13)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .modifier(HeaderChrome(shape: .capsule)).contentShape(.capsule)
        }.fixedSize().accessibilityLabel(Text(title))
            .accessibilityValue(Text(verbatim: options.first { $0.0 == selection }?.1 ?? ""))
    }
}

/// A command shown as the user will type it, with its copy action beside it.
struct CommandWell: View {
    let command: String
    let copyLabel: LocalizedStringKey
    var prominent = false
    let copy: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: command).font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                copy(); copied = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
            } label: {
                Label(copied ? "Copied" : copyLabel, systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(prominent ? .appPrimarySmall : .appSecondarySmall).fixedSize()
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .help(command)
    }
}

/// One way to begin, as a card the whole of which can be clicked.
struct StartChoiceCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let note: LocalizedStringKey
    var badge: LocalizedStringKey?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        if let badge {
                            Text(badge).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(.primary.opacity(0.15)))
                        }
                    }
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    .padding(.top, 10)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panelStrong, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.panelEdge))
            .overlay { if hovering { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(0.03)) } }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }
}

/// Numbered steps joined by short rules. Done steps show a check; with `select`, each step is a button.
struct StepTrack: View {
    let titles: [String]
    let current: Int
    var select: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                if let select {
                    Button { select(index) } label: { step(index, title) }.buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: title))
                        .accessibilityAddTraits(index == current ? .isSelected : [])
                } else {
                    step(index, title)
                }
                if index < titles.count - 1 {
                    Rectangle().fill(.primary.opacity(0.1)).frame(height: 1).frame(minWidth: 8, maxWidth: 28)
                }
            }
        }
        .accessibilityElement(children: select == nil ? .ignore : .contain)
        .accessibilityLabel(Text("Step \(current + 1) of \(titles.count)"))
    }

    private func step(_ index: Int, _ title: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(index <= current ? AnyShapeStyle(Color.brandFill) : AnyShapeStyle(.primary.opacity(0.08)))
                if index < current {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text(verbatim: String(index + 1)).font(.system(size: 9, weight: .bold)).monospacedDigit()
                        .foregroundStyle(index == current ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
            }.frame(width: 16, height: 16)
            Text(verbatim: title).font(.system(size: 11, weight: index == current ? .semibold : .regular))
                .foregroundStyle(index == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1).fixedSize()
        }.contentShape(.rect)
    }
}

