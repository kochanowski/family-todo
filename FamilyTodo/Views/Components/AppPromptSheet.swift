import Foundation
import SwiftUI

struct AppPromptSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    let title: String
    let message: String?
    let placeholder: String
    @Binding var text: String
    let secondaryTitle: String
    let primaryTitle: String
    let primaryStyle: AppModalPrimaryStyle
    let onCancel: (() -> Void)?
    let onSubmit: (String) -> Void

    init(
        title: String,
        message: String? = nil,
        placeholder: String,
        text: Binding<String>,
        secondaryTitle: String = "Cancel",
        primaryTitle: String,
        primaryStyle: AppModalPrimaryStyle = .accent,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (String) -> Void
    ) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        _text = text
        self.secondaryTitle = secondaryTitle
        self.primaryTitle = primaryTitle
        self.primaryStyle = primaryStyle
        self.onCancel = onCancel
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(themeStore.font(for: .inlineTitle))
                .foregroundStyle(.primary)

            if let message {
                Text(message)
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $text)
                .font(themeStore.font(for: .inlineTitle))
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.12))
                }
                .onSubmit {
                    submitAndDismiss()
                }

            Spacer(minLength: 0)

            AppModalActionRow(
                secondaryTitle: secondaryTitle,
                primaryTitle: primaryTitle,
                primaryStyle: primaryStyle,
                isPrimaryDisabled: trimmedValue.isEmpty,
                onSecondary: {
                    onCancel?()
                    dismiss()
                },
                onPrimary: submitAndDismiss
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .presentationDetents([.height(message == nil ? 230 : 260)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private var trimmedValue: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitAndDismiss() {
        guard !trimmedValue.isEmpty else { return }
        onSubmit(trimmedValue)
        dismiss()
    }
}

struct CategoryEditorSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    let primaryTitle: String
    let onCancel: () -> Void
    let onSubmit: (String, String) -> Void

    @State private var name: String
    @State private var selectedColorHex: String

    init(
        title: String,
        initialName: String,
        initialColorHex: String,
        primaryTitle: String,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.primaryTitle = primaryTitle
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        _name = State(initialValue: initialName)
        _selectedColorHex = State(
            initialValue: MemberColorToken.normalize(hex: initialColorHex) ?? MemberColorToken.fallbackHex
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category Name", text: $name)
                        .font(themeStore.font(for: .listRowTitle))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Category Name")
                        .font(themeStore.font(for: .sectionHeader))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }

                Section {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                        spacing: 12
                    ) {
                        ForEach(MemberColorToken.allCases, id: \.self) { token in
                            let hex = token.hex
                            Button {
                                selectedColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selectedColorHex == hex {
                                            Circle()
                                                .stroke(Color.primary, lineWidth: 2)
                                                .padding(1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Category Color")
                        .font(themeStore.font(for: .sectionHeader))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(themeStore.font(for: .buttonLabel))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        onSubmit(trimmedName, selectedColorHex)
                        dismiss()
                    } label: {
                        Text(primaryTitle)
                            .font(themeStore.font(for: .buttonLabel))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct BacklogAssigneePickerSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let title: String
    let actionTitle: String
    let members: [Member]
    let autoConfirmOnSelection: Bool
    @Binding var selectedAssigneeId: UUID?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if members.isEmpty {
                    Text("No members available.")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(.secondary)
                }

                ForEach(members) { member in
                    Button {
                        selectedAssigneeId = member.id
                        if autoConfirmOnSelection {
                            onConfirm()
                        }
                    } label: {
                        HStack {
                            Text(member.displayName)
                                .font(themeStore.font(for: .inlineTitle))
                                .foregroundStyle(.primary)
                            Spacer()
                            if !autoConfirmOnSelection, selectedAssigneeId == member.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !autoConfirmOnSelection {
                        Button(actionTitle) {
                            onConfirm()
                        }
                        .font(themeStore.font(for: .buttonLabel))
                        .disabled(selectedAssigneeId == nil)
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationBackground(.ultraThinMaterial)
    }
}

struct BacklogItemEditSheet: View {
    let item: BacklogItem
    let members: [Member]
    let onSave: (String, String?, UUID?) -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var assigneeId: UUID?
    @State private var showDeleteConfirmation = false

    init(
        item: BacklogItem,
        members: [Member],
        onSave: @escaping (String, String?, UUID?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.members = members
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes ?? "")
        _assigneeId = State(initialValue: item.assigneeId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Title", text: $title)
                        .font(themeStore.font(for: .listRowTitle))
                }

                Section("Assignee") {
                    if members.isEmpty {
                        Text("No members available.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Who", selection: $assigneeId) {
                            Text("Unassigned").tag(UUID?.none)
                            ForEach(members) { member in
                                Text(member.displayName).tag(Optional(member.id))
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .font(themeStore.font(for: .listRowTitle))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                }

                Section {
                    Button("Delete Item", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Idea Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(themeStore.font(for: .buttonLabel))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Idea Item")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        commit()
                    } label: {
                        Text("Save")
                            .font(themeStore.font(for: .buttonLabel))
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showDeleteConfirmation) {
                AppConfirmationSheet(
                    title: "Delete this item?",
                    message: "This action cannot be undone.",
                    primaryTitle: "Delete",
                    primaryStyle: .destructive,
                    onPrimary: {
                        onDelete()
                        dismiss()
                    }
                )
            }
        }
    }

    private func commit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmedTitle, trimmedNotes.isEmpty ? nil : trimmedNotes, assigneeId)
        dismiss()
    }
}
