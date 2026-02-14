import SwiftUI

struct BJJLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: BJJViewModel
    var editSession: BJJSession? = nil

    @State private var sessionType: BJJSessionType = .nogi
    @State private var sessionDate = Date()
    @State private var durationMinutes = 60
    @State private var techniques: [String] = []
    @State private var techniqueInput = ""
    @State private var notes = ""
    @State private var showError = false

    private var isEditing: Bool { editSession != nil }

    private let commonTechniques = [
        "Guard Passing", "Submissions", "Takedowns",
        "Sweeps", "Escapes", "Drilling", "Positional Sparring",
        "Live Rolls", "Back Takes", "Mount", "Side Control"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Session Type
                Section("Session Type") {
                    Picker("Type", selection: $sessionType) {
                        ForEach(BJJSessionType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Date & Duration
                Section("Details") {
                    DatePicker("Date", selection: $sessionDate, displayedComponents: .date)

                    Stepper(value: $durationMinutes, in: 30...180, step: 5) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(durationMinutes) min")
                                .foregroundColor(NexusTheme.Colors.textSecondary)
                        }
                    }
                }

                // Techniques
                Section {
                    // Common technique suggestions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NexusTheme.Spacing.xs) {
                            ForEach(commonTechniques, id: \.self) { technique in
                                let isSelected = techniques.contains(technique)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if isSelected {
                                            techniques.removeAll { $0 == technique }
                                        } else {
                                            techniques.append(technique)
                                        }
                                    }
                                } label: {
                                    Text(technique)
                                        .font(.caption)
                                        .padding(.horizontal, NexusTheme.Spacing.sm)
                                        .padding(.vertical, NexusTheme.Spacing.xs)
                                        .background(isSelected ? NexusTheme.Colors.accent : NexusTheme.Colors.accent.opacity(0.1))
                                        .foregroundColor(isSelected ? .white : NexusTheme.Colors.accent)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, NexusTheme.Spacing.xxs)
                    }

                    // Selected techniques as removable chips
                    if !techniques.isEmpty {
                        FlowLayout(spacing: NexusTheme.Spacing.xs) {
                            ForEach(techniques, id: \.self) { technique in
                                HStack(spacing: 4) {
                                    Text(technique)
                                        .font(.caption)
                                    Button {
                                        withAnimation {
                                            techniques.removeAll { $0 == technique }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(NexusTheme.Colors.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, NexusTheme.Spacing.sm)
                                .padding(.vertical, NexusTheme.Spacing.xxs)
                                .background(NexusTheme.Colors.Semantic.blue.opacity(0.15))
                                .foregroundColor(NexusTheme.Colors.Semantic.blue)
                                .clipShape(Capsule())
                            }
                        }
                    }

                    // Custom technique input
                    HStack {
                        TextField("Add custom technique", text: $techniqueInput)
                            .textInputAutocapitalization(.words)
                            .onSubmit { addCustomTechnique() }

                        Button("Add") { addCustomTechnique() }
                            .disabled(techniqueInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Techniques Practiced")
                }

                // Notes
                Section("Notes") {
                    TextField("Session notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .onAppear { prefillEditData() }
            .navigationTitle(isEditing ? "Edit Session" : "Log BJJ Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveSession() }
                    }
                    .disabled(viewModel.isLogging)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.logError ?? "Failed to log session")
            }
            .interactiveDismissDisabled(viewModel.isLogging)
        }
    }

    private func addCustomTechnique() {
        let technique = techniqueInput.trimmingCharacters(in: .whitespaces)
        guard !technique.isEmpty, !techniques.contains(technique) else {
            techniqueInput = ""
            return
        }
        withAnimation {
            techniques.append(technique)
        }
        techniqueInput = ""
    }

    private func prefillEditData() {
        guard let session = editSession else { return }
        sessionType = BJJSessionType(rawValue: session.sessionType) ?? .nogi
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: session.sessionDate) {
            sessionDate = date
        }
        durationMinutes = session.durationMinutes
        techniques = session.techniques ?? []
        notes = session.notes ?? ""
    }

    private func saveSession() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        if let session = editSession {
            let request = BJJUpdateRequest(
                id: session.id,
                sessionDate: formatter.string(from: sessionDate),
                sessionType: sessionType.rawValue,
                durationMinutes: durationMinutes,
                techniques: techniques.isEmpty ? nil : techniques,
                notes: notes.isEmpty ? nil : notes
            )
            let success = await viewModel.updateSession(request)
            if success {
                dismiss()
            } else {
                showError = true
            }
        } else {
            let request = LogBJJRequest(
                sessionDate: formatter.string(from: sessionDate),
                sessionType: sessionType.rawValue,
                durationMinutes: durationMinutes,
                techniques: techniques.isEmpty ? nil : techniques,
                notes: notes.isEmpty ? nil : notes,
                source: "manual"
            )
            let success = await viewModel.logSession(request)
            if success {
                dismiss()
            } else {
                showError = true
            }
        }
    }
}

#Preview {
    BJJLogSheet(viewModel: BJJViewModel(), editSession: nil)
}
