import SwiftUI
import SwiftData
import WidgetKit
import UniformTypeIdentifiers

struct PersonListView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false
    @State private var editingPerson: Person?
    @State private var exportDocument: PersonBackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importResultMessage: String?

    private var sortedByUpcoming: [Person] {
        people.sorted { $0.daysUntilNextBirthday < $1.daysUntilNextBirthday }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedByUpcoming) { person in
                    Button {
                        editingPerson = person
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(person.emoji ?? "🎂")
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(person.name)
                                        .font(.body)
                                    Spacer()
                                    if person.daysUntilNextBirthday == 0 {
                                        Text("Today!").font(.caption.bold()).foregroundStyle(.orange)
                                    } else {
                                        Text("\(person.daysUntilNextBirthday)d")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                // Truncated Text measures slightly wider than the width it's
                                // assigned (due to the "..." not being taken into account),
                                // which causes the whole row to shift and re-center.
                                // Instead, use an overlay to force the alignment.
                                Text(" ")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .leading) {
                                        Text(subtitle(for: person))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    .clipped()
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button(role: .destructive) {
                            deletePerson(person)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Everyone")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            do {
                                exportDocument = PersonBackupDocument(data: try PersonBackup.exportData(people: people))
                                showingExporter = true
                            } catch {
                                importResultMessage = "Couldn't prepare export: \(error.localizedDescription)"
                            }
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import…", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditPersonView(person: nil)
            }
            .sheet(item: $editingPerson) { person in
                AddEditPersonView(person: person)
            }
            .overlay {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No one yet",
                        systemImage: "person.badge.plus",
                        description: Text("Tap + to add the first birthday to track.")
                    )
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "BirthdayBuzz Backup"
            ) { result in
                if case .failure(let error) = result {
                    importResultMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    importPeople(from: url)
                case .failure(let error):
                    importResultMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            .alert("Import/Export", isPresented: .constant(importResultMessage != nil), presenting: importResultMessage) { _ in
                Button("OK") { importResultMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private func importPeople(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let result = try PersonBackup.importData(data, into: modelContext, existingPeople: people)
            NotificationManager.refreshMorningNotifications(people: people)
            NotificationManager.refreshEveningReminders(people: people)
            WidgetCenter.shared.reloadAllTimelines()
            importResultMessage = "Imported \(result.added) \(result.added == 1 ? "person" : "people")"
                + (result.skipped > 0 ? ", skipped \(result.skipped) already in your list." : ".")
        } catch {
            importResultMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func subtitle(for person: Person) -> String {
        let date = dateLabel(for: person)
        guard let notes = person.notes, !notes.isEmpty else { return date }
        return "\(date) · \(notes)"
    }

    private func dateLabel(for person: Person) -> String {
        var components = DateComponents()
        components.month = person.birthMonth
        components.day = person.birthDay
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            deletePerson(sortedByUpcoming[index])
        }
    }

    private func deletePerson(_ person: Person) {
        modelContext.delete(person)
        try? modelContext.save()
        let remainingPeople = people.filter { $0.id != person.id }
        NotificationManager.refreshMorningNotifications(people: remainingPeople)
        NotificationManager.refreshEveningReminders(people: remainingPeople)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Person.self, configurations: config)

    let julia = Person(name: "Julia", birthMonth: 7, birthDay: 6, birthYear: 1990, emoji: "🎂", notes: "Make a card")
    let annMarie = Person(name: "Ann Marie", birthMonth: 7, birthDay: 7, emoji: "🎂")
    let noNotes = Person(name: "Chris", birthMonth: 12, birthDay: 25, birthYear: 1985, emoji: "🎄")

    container.mainContext.insert(julia)
    container.mainContext.insert(annMarie)
    container.mainContext.insert(noNotes)

    return PersonListView()
        .modelContainer(container)
}
