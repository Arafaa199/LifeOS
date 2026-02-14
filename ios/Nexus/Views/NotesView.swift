import SwiftUI
import os

struct NotesView: View {
    @State private var notes: [Note] = []
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var allTags: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var noteToDelete: Note?
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var editingNote: Note?
    @State private var editingTitle = ""
    @State private var editingTags: [String] = []
    @State private var newTagInput = ""
    @State private var isDeleting = false
    @State private var isUpdating = false
    @State private var showUpdateError = false
    @State private var updateErrorMessage = ""

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "notes")

    var body: some View {
        Group {
            if isLoading && notes.isEmpty {
                ThemeLoadingView(message: "Loading notes...")
            } else if let error = errorMessage, notes.isEmpty {
                errorView(error)
            } else if notes.isEmpty && searchText.isEmpty && selectedTag == nil {
                emptyView
            } else {
                notesList
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search notes...")
        .onChange(of: searchText) { _, _ in
            Task { await searchNotes() }
        }
        .refreshable {
            await loadNotes()
        }
        .task {
            await loadNotes()
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        List {
            // Tags filter section
            if !allTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allTags, id: \.self) { tag in
                                TagChip(
                                    tag: tag,
                                    isSelected: selectedTag == tag,
                                    onTap: {
                                        if selectedTag == tag {
                                            selectedTag = nil
                                        } else {
                                            selectedTag = tag
                                        }
                                        Task { await searchNotes() }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            // Notes
            if filteredNotes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("No notes match your search")
                    )
                }
            } else {
                Section(noteSectionHeader) {
                    ForEach(filteredNotes) { note in
                        NavigationLink {
                            NoteDetailView(
                                note: note,
                                onEdit: {
                                    editingNote = note
                                    editingTitle = note.title ?? note.displayTitle
                                    editingTags = note.tags ?? []
                                    showEditSheet = true
                                }
                            )
                        } label: {
                            NoteRow(
                                note: note,
                                onEdit: {
                                    editingNote = note
                                    editingTitle = note.title ?? note.displayTitle
                                    editingTags = note.tags ?? []
                                    showEditSheet = true
                                },
                                onDelete: {
                                    noteToDelete = note
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                noteToDelete = note
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog("Delete Note?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let note = noteToDelete {
                    Task { await deleteNote(note) }
                }
            }
        } message: {
            Text("Are you sure you want to delete this note? This action cannot be undone.")
        }
        .sheet(isPresented: $showEditSheet) {
            editNoteSheet
        }
        .alert("Update Failed", isPresented: $showUpdateError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateErrorMessage)
        }
    }

    private var noteSectionHeader: String {
        if let tag = selectedTag {
            return "Tagged: #\(tag)"
        } else if !searchText.isEmpty {
            return "Results"
        }
        return "Recent Notes"
    }

    private var filteredNotes: [Note] {
        notes
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Notes Indexed", systemImage: "doc.text")
        } description: {
            Text("Run the Obsidian indexer to sync your notes")
        } actions: {
            Button("Refresh") {
                Task { await loadNotes() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                Task { await loadNotes() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Edit Sheet

    private var editNoteSheet: some View {
        NavigationView {
            Form {
                Section("Title") {
                    TextField("Note title", text: $editingTitle)
                }

                Section("Tags") {
                    // Existing tags as removable chips
                    if !editingTags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(editingTags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                        .font(.system(size: 13))
                                    Button {
                                        editingTags.removeAll { $0 == tag }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(NexusTheme.Colors.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(NexusTheme.Colors.accent.opacity(0.12))
                                .foregroundColor(NexusTheme.Colors.accent)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Add new tag
                    HStack {
                        TextField("Add tag", text: $newTagInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { addTag() }

                        Button("Add") { addTag() }
                            .disabled(newTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let note = editingNote {
                    Section {
                        LabeledContent("Path", value: note.relativePath)
                        if let wordCount = note.wordCount {
                            LabeledContent("Words", value: "\(wordCount)")
                        }
                    }
                }
            }
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showEditSheet = false
                        editingNote = nil
                        editingTitle = ""
                        editingTags = []
                        newTagInput = ""
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let note = editingNote {
                            Task { await updateNote(note) }
                        }
                    }
                    .disabled(isUpdating || editingTitle.isEmpty)
                }
            }
        }
    }

    // MARK: - Tag Helpers

    private func addTag() {
        // Strip # prefix and whitespace
        var tag = newTagInput.trimmingCharacters(in: .whitespaces)
        if tag.hasPrefix("#") {
            tag = String(tag.dropFirst())
        }
        tag = tag.trimmingCharacters(in: .whitespaces)

        // Don't add empty or duplicate tags
        guard !tag.isEmpty, !editingTags.contains(tag) else {
            newTagInput = ""
            return
        }

        editingTags.append(tag)
        newTagInput = ""
    }

    // MARK: - API

    private func loadNotes() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.searchNotes(limit: 100)
            notes = response.notes
            extractTags()
            logger.info("Loaded \(response.count) notes")
        } catch {
            if notes.isEmpty {
                errorMessage = error.localizedDescription
            }
            logger.error("Failed to load notes: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func searchNotes() async {
        isLoading = true

        do {
            let response = try await NexusAPI.shared.searchNotes(
                query: searchText.isEmpty ? nil : searchText,
                tag: selectedTag,
                limit: 100
            )
            notes = response.notes
            logger.info("Search returned \(response.count) notes")
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func extractTags() {
        var tagSet = Set<String>()
        for note in notes {
            if let tags = note.tags {
                tags.forEach { tagSet.insert($0) }
            }
        }
        allTags = Array(tagSet).sorted()
    }

    private func deleteNote(_ note: Note) async {
        guard let noteId = note.noteId else {
            logger.error("Cannot delete note without ID")
            return
        }

        // Guard against deleting a note that's currently being edited
        if editingNote?.id == note.id {
            showEditSheet = false
            editingNote = nil
            editingTitle = ""
            editingTags = []
        }

        isDeleting = true

        // Optimistic removal: remove from UI immediately
        let deletedIndex = notes.firstIndex { $0.id == note.id }
        notes.removeAll { $0.id == note.id }
        noteToDelete = nil

        do {
            let _: NoteDeleteResponse = try await NexusAPI.shared.delete("/webhook/nexus-note-delete?id=\(noteId)")
            logger.info("Note deleted: \(note.displayTitle)")
        } catch {
            logger.error("Failed to delete note: \(error.localizedDescription)")
            errorMessage = "Failed to delete note: \(error.localizedDescription)"

            // Restore the note if delete failed
            if let index = deletedIndex {
                notes.insert(note, at: index)
            } else {
                notes.append(note)
            }
        }
        isDeleting = false
    }

    private func updateNote(_ note: Note) async {
        guard let noteId = note.noteId else {
            logger.error("Cannot update note without ID")
            updateErrorMessage = "Cannot update note without ID"
            showUpdateError = true
            return
        }

        isUpdating = true
        do {
            let _: NoteUpdateResponse = try await DocumentsAPI.shared.updateNote(
                id: noteId,
                title: editingTitle.isEmpty ? nil : editingTitle,
                tags: editingTags.isEmpty ? nil : editingTags
            )
            // Reload notes to get updated data from server
            await loadNotes()
            // Only clear editing state on success
            showEditSheet = false
            editingNote = nil
            editingTitle = ""
            editingTags = []
            newTagInput = ""
            logger.info("Note updated: \(note.displayTitle)")
        } catch {
            // Show error alert but preserve editing state so user doesn't lose their edits
            logger.error("Failed to update note: \(error.localizedDescription)")
            updateErrorMessage = error.localizedDescription
            showUpdateError = true
        }
        isUpdating = false
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: Note
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(NexusTheme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: noteIcon)
                    .font(.system(size: 16))
                    .foregroundColor(NexusTheme.Colors.accent)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let folder = note.folder {
                        Label(folder, systemImage: "folder")
                    }

                    if let wordCount = note.wordCount {
                        Label("\(wordCount) words", systemImage: "text.word.spacing")
                    }

                    if let relativeDate = note.relativeDate {
                        Text(relativeDate)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

                // Tags
                if let tags = note.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(NexusTheme.Colors.accent.opacity(0.1))
                                .foregroundColor(NexusTheme.Colors.accent)
                                .clipShape(Capsule())
                        }
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var noteIcon: String {
        if let folder = note.folder?.lowercased() {
            if folder.contains("project") { return "folder.fill" }
            if folder.contains("daily") || folder.contains("journal") { return "calendar" }
            if folder.contains("work") { return "briefcase.fill" }
            if folder.contains("learn") || folder.contains("study") { return "book.fill" }
            if folder.contains("idea") { return "lightbulb.fill" }
        }
        return "doc.text.fill"
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("#\(tag)")
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? NexusTheme.Colors.accent : NexusTheme.Colors.accent.opacity(0.1))
                .foregroundColor(isSelected ? .white : NexusTheme.Colors.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        NotesView()
    }
}
