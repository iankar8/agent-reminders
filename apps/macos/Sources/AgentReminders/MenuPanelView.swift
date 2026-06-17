import SwiftUI
import AppKit
import AgentRemindersCore

struct MenuPanelView: View {
    @EnvironmentObject var model: ReminderViewModel

    /// Weak handle to the host NSPanel, injected by MenuBarPanel so the
    /// ResizeHandle can mutate the window frame live.
    let panelBox: WeakPanelBox

    @State private var composerKind: ReminderKind = .todo
    @State private var draft = ""
    @State private var draftTime = ""
    @State private var showHistory = false
    @State private var editingID: String?

    init(panelBox: WeakPanelBox = WeakPanelBox()) {
        self.panelBox = panelBox
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            metrics
            composer
            Divider()
            content
            footer
            ResizeHandle(panel: panelBox.panel)
        }
        .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Reminders").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 0) {
                    Text("\(model.openCount)").contentTransition(.numericText()).monospacedDigit()
                    Text(" open • ")
                    Text("\(model.dueCount)").contentTransition(.numericText()).monospacedDigit()
                    Text(" due")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .animation(Motion.listChange, value: model.openCount)
                .animation(Motion.listChange, value: model.dueCount)
            }
            Spacer()
            iconButton("arrow.clockwise", help: "Refresh") { model.tick() }
            iconButton("folder", help: "Reveal store file") { model.openStore() }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // MARK: Metrics

    private var metrics: some View {
        HStack(spacing: 8) {
            MetricCell(label: "Todos", value: model.todoCount, system: "circle")
            MetricCell(label: "Due", value: model.dueCount, system: "exclamationmark.circle", tint: model.dueCount > 0 ? .orange : nil)
            MetricCell(label: "Reminders", value: model.reminderCount, system: "bell")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 7) {
            Picker("", selection: $composerKind) {
                Text("Todo").tag(ReminderKind.todo)
                Text("Reminder").tag(ReminderKind.reminder)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .animation(Motion.segThumb, value: composerKind)

            HStack(spacing: 6) {
                TextField(composerKind == .todo ? "Add a to-do…" : "Remind me to…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                if composerKind == .reminder {
                    TextField("10m", text: $draftTime)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .onSubmit(add)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmed.isEmpty)
            }
            .animation(Motion.listChange, value: composerKind)
        }
        .padding(.horizontal, 12).padding(.bottom, 9)
    }

    private func add() {
        if composerKind == .todo {
            model.addTodo(draft)        // optimistic: reload() animates the new row in
        } else {
            model.addReminder(draft, at: draftTime)
        }
        draft = ""; draftTime = ""      // field clears the same frame
    }

    // MARK: Lists

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if isEmpty {
                    emptyState
                        .staggered(0)
                } else {
                    section("Due", model.dueItems)
                    section("Open to-dos", model.openTodos)
                    section("Upcoming reminders", model.upcomingReminders)
                    if !model.history.isEmpty {
                        historyDisclosure
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .animation(Motion.listChange, value: model.items)
        }
        // Flexible: the list fills whatever height the panel resize gives us,
        // so dragging the handle grows the visible list (Motion.resizeReflow
        // smooths the internal reflow).
        .frame(maxHeight: .infinity)
        .animation(Motion.resizeReflow, value: panelBox.panel?.frame.height)
    }

    private var isEmpty: Bool {
        model.dueItems.isEmpty && model.openTodos.isEmpty && model.upcomingReminders.isEmpty
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [AgentReminder]) -> some View {
        if !items.isEmpty {
            SectionHeader(title: title, count: items.count)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ReminderRow(item: item, editingID: $editingID)
                    .staggered(index)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity.combined(with: .scale(scale: 0.94))
                    ))
            }
        }
    }

    private var historyDisclosure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(Motion.listChange) { showHistory.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showHistory ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("Done & fired").font(.system(size: 10.5, weight: .semibold))
                        .textCase(.uppercase).foregroundStyle(.secondary)
                    Text("\(model.history.count)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        .contentTransition(.numericText()).monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 3)
            }
            .buttonStyle(.plain)

            if showHistory {
                ForEach(model.history) { item in
                    ReminderRow(item: item, editingID: $editingID)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        ))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34)).foregroundStyle(.green.opacity(0.85))
            Text("All clear").font(.system(size: 14, weight: .semibold))
            Text("No to-dos or reminders need you right now.\nAgents and the composer above add new ones here.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if !model.notificationsAuthorized {
                Image(systemName: "bell.slash").font(.system(size: 10))
                Text("Notifications off").font(.system(size: 10.5))
            } else {
                Image(systemName: "bell.badge").font(.system(size: 10)).foregroundStyle(.secondary)
                Text("Notifying on due").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary.opacity(0.4))
    }

    private func iconButton(_ system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }
}

// MARK: - Metric cell

private struct MetricCell: View {
    let label: String
    let value: Int
    let system: String
    var tint: Color?

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: system).font(.system(size: 10))
                Text("\(value)").font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tint ?? .primary)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        .animation(Motion.listChange, value: value)
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase).foregroundStyle(.secondary)
            Text("\(count)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .contentTransition(.numericText()).monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 3)
    }
}

// MARK: - Row

private struct ReminderRow: View {
    let item: AgentReminder
    @Binding var editingID: String?
    @EnvironmentObject var model: ReminderViewModel
    @State private var hovering = false
    @State private var pressed = false

    private var isEditing: Bool { editingID == item.id }
    private var isClosed: Bool { [.done, .fired, .cancelled, .expired].contains(item.status) }

    var body: some View {
        Group {
            if isEditing {
                InlineEditor(item: item, editingID: $editingID)
            } else {
                row
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear))
                // Subtle sheen on hover: a faint top-edge highlight.
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(.white.opacity(hovering ? 0.06 : 0), lineWidth: 1)
                )
        )
        .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .offset(y: hovering ? -1 : 0)               // 1px lift
        .scaleEffect(pressed ? 0.996 : 1)
        .animation(Motion.hover, value: hovering)
        .animation(Motion.press, value: pressed)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 9) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: 12.5))
                    .strikethrough(item.status == .done, color: .secondary)
                    .foregroundStyle(isClosed ? .secondary : .primary)
                    .lineLimit(2)
                Text(metaLine).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if hovering && !isClosed {
                actions
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                trailing
                    .transition(.opacity)
            }
        }
    }

    private var leading: some View {
        Group {
            switch item.status {
            case .open where item.kind == .todo:
                Button { model.complete(item) } label: {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            case .open:
                Image(systemName: "bell").foregroundStyle(.tint)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .fired:
                Image(systemName: "bell.fill").foregroundStyle(.secondary)
            default:
                Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 14)).frame(width: 18)
    }

    private var trailing: some View {
        Group {
            if item.status == .open, let label = dueLabel(item) {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(label == "due" ? .orange : .secondary)
            } else if isClosed {
                Text(item.status.rawValue).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if item.kind == .todo {
                rowButton("checkmark", help: "Done") { model.complete(item) }
            }
            Menu {
                Button("10 minutes") { model.snooze(item, by: "10m") }
                Button("1 hour") { model.snooze(item, by: "1h") }
                Button("Tomorrow") { model.snooze(item, by: "tomorrow") }
            } label: {
                Image(systemName: "clock").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
            rowButton("pencil", help: "Edit") { editingID = item.id }
            rowButton("trash", help: "Delete") { model.delete(item) }
        }
    }

    private func rowButton(_ system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 12)).frame(width: 22, height: 22)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }

    private var metaLine: String {
        var parts: [String] = [item.kind == .todo ? "To-do" : "Reminder"]
        if let id = item.target.id, item.target.kind != .newAgent { parts.append(id) }
        if item.status == .fired { parts.append("fired") }
        if item.status == .done, let done = item.doneAt, let label = shortTime(done) { parts.append("done \(label)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Inline editor

private struct InlineEditor: View {
    let item: AgentReminder
    @Binding var editingID: String?
    @EnvironmentObject var model: ReminderViewModel

    @State private var text: String
    @State private var kind: ReminderKind
    @State private var time: String

    init(item: AgentReminder, editingID: Binding<String?>) {
        self.item = item
        self._editingID = editingID
        _text = State(initialValue: item.text)
        _kind = State(initialValue: item.kind)
        _time = State(initialValue: "")
    }

    var body: some View {
        VStack(spacing: 6) {
            Picker("", selection: $kind) {
                Text("Todo").tag(ReminderKind.todo)
                Text("Reminder").tag(ReminderKind.reminder)
            }
            .pickerStyle(.segmented).labelsHidden()

            TextField("Text", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3)

            if kind == .reminder {
                TextField("New time (e.g. 2h, tomorrow) — blank keeps current", text: $time)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
            }

            HStack {
                Button("Cancel") { editingID = nil }.buttonStyle(.plain).font(.system(size: 11))
                Spacer()
                Button("Save", action: save).buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(text.trimmed.isEmpty)
            }
        }
    }

    private func save() {
        // todo -> clear any fire time; reminder -> set new time, or keep current when blank.
        let fireAt: String? = kind == .todo ? "" : (time.trimmed.isEmpty ? nil : time.trimmed)
        model.update(item, text: text.trimmed, kind: kind, fireAt: fireAt)
        editingID = nil
    }
}

// MARK: - Time helpers

private func dueLabel(_ item: AgentReminder) -> String? {
    guard let fireAt = item.fireAt, let date = ReminderTime.parseStored(fireAt) else { return nil }
    let delta = date.timeIntervalSince(Date())
    if delta <= 0 { return "due" }
    let minutes = Int(delta / 60)
    if minutes < 60 { return "in \(max(minutes, 1))m" }
    let hours = Int(delta / 3600)
    if hours < 24 { return "in \(hours)h" }
    return "in \(Int(delta / 86_400))d"
}

private func shortTime(_ iso: String) -> String? {
    guard let date = ReminderTime.parseStored(iso) else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}
