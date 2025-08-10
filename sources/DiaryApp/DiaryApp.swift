import SwiftUI
import Combine

// MARK: - Models

struct DiaryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var date: Date
    var tags: [String]
    var mood: String? // optional emoji
    var pinned: Bool = false
}

struct UserProfile: Codable {
    var name: String = "You"
    var preferredColorHex: String = "#4F46E5" // default purple
}

// MARK: - Persistence Service

final class PersistenceService {
    static let shared = PersistenceService()
    let filename = "diary_entries.json"
    let userFile = "diary_user.json"
    private init() {}

    private func documentsURL(for file: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(file)
    }

    func save(entries: [DiaryEntry]) {
        guard let url = documentsURL(for: filename) else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: [.atomicWrite])
        } catch {
            print("Save error:", error)
        }
    }

    func loadEntries() -> [DiaryEntry] {
        guard let url = documentsURL(for: filename), FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([DiaryEntry].self, from: data)
        } catch {
            print("Load error:", error)
            return []
        }
    }

    func save(user: UserProfile) {
        guard let url = documentsURL(for: userFile) else { return }
        do {
            let data = try JSONEncoder().encode(user)
            try data.write(to: url, options: [.atomicWrite])
        } catch {
            print("Save user error:", error)
        }
    }

    func loadUser() -> UserProfile {
        guard let url = documentsURL(for: userFile), FileManager.default.fileExists(atPath: url.path) else { return UserProfile() }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            print("Load user error:", error)
            return UserProfile()
        }
    }
}

// MARK: - ViewModel

final class DiaryViewModel: ObservableObject {
    @Published var entries: [DiaryEntry] = [] {
        didSet { PersistenceService.shared.save(entries: entries) }
    }
    @Published var user: UserProfile = PersistenceService.shared.loadUser() {
        didSet { PersistenceService.shared.save(user: user) }
    }

    // Rewards
    @Published var points: Int = UserDefaults.standard.integer(forKey: "points") {
        didSet { UserDefaults.standard.set(points, forKey: "points") }
    }
    @Published var currentStreak: Int = UserDefaults.standard.integer(forKey: "streak") {
        didSet { UserDefaults.standard.set(currentStreak, forKey: "streak") }
    }
    @Published var lastEntryDate: Date? = {
        UserDefaults.standard.object(forKey: "lastEntryDate") as? Date
    }() {
        didSet { UserDefaults.standard.set(lastEntryDate, forKey: "lastEntryDate") }
    }
    @Published var badges: [String] = UserDefaults.standard.stringArray(forKey: "badges") ?? [] {
        didSet { UserDefaults.standard.set(badges, forKey: "badges") }
    }

    init() {
        entries = PersistenceService.shared.loadEntries()
        if entries.isEmpty {
            entries = DiaryViewModel.sampleEntries()
        }
    }

    // CRUD
    func add(_ entry: DiaryEntry) {
        entries.insert(entry, at: 0)
        rewardForNewEntry(on: entry.date)
    }
    func update(_ entry: DiaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
    }
    func delete(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    // Rewards logic
    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: b), to: Calendar.current.startOfDay(for: a)).day ?? 0
    }
    func rewardForNewEntry(on date: Date = Date()) {
        points += 10
        if let last = lastEntryDate {
            let days = daysBetween(date, last)
            if days == 1 {
                currentStreak += 1
            } else if days == 0 {
                // same day, no change
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }
        lastEntryDate = date
        evaluateBadges()
    }
    private func evaluateBadges() {
        var newBadges = badges
        if points >= 100 && !badges.contains("Centurion") { newBadges.append("Centurion") }
        if currentStreak >= 7 && !badges.contains("7-Day Streak") { newBadges.append("7-Day Streak") }
        if entries.count >= 30 && !badges.contains("30 Entries") { newBadges.append("30 Entries") }
        badges = newBadges
    }
    func togglePin(_ entry: DiaryEntry) {
        var e = entry
        e.pinned.toggle()
        update(e)
    }
    static func sampleEntries() -> [DiaryEntry] {
        [
            DiaryEntry(title: "Welcome to Your Diary", body: "This is your private space to capture thoughts, goals, and memories. Write something today to earn points and build your streak!", date: Date().addingTimeInterval(-3600), tags: ["intro"], mood: "🙂", pinned: true),
            DiaryEntry(title: "Morning run", body: "Felt energetic after breakfast. 5km in 30 minutes.", date: Date().addingTimeInterval(-86400), tags: ["health","run"], mood: "😅"),
            DiaryEntry(title: "Idea: Side project", body: "Sketching an app to help small teams plan sprints.", date: Date().addingTimeInterval(-3*86400), tags: ["work","ideas"], mood: "🤔")
        ]
    }
}

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8)*17, (int >> 4 & 0xF)*17, (int & 0xF)*17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Main App

@main
struct DiaryApp: App {
    @StateObject var vm = DiaryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject var vm: DiaryViewModel
    @State private var selection: DiaryEntry?
    @State private var showEditor = false
    @State private var searchText = ""
    @State private var selectedTag: String?

    var filteredEntries: [DiaryEntry] {
        vm.entries.filter { entry in
            (selectedTag == nil || entry.tags.contains(selectedTag!)) &&
            (searchText.isEmpty || entry.title.localizedCaseInsensitiveContains(searchText) || entry.body.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: headerView) {
                    HStack {
                        TextField("Search entries", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button {
                            showEditor = true
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            TagChip(tag: "All", isSelected: selectedTag == nil) { selectedTag = nil }
                            ForEach(Array(Set(vm.entries.flatMap { $0.tags })).sorted(), id: \.self) { tag in
                                TagChip(tag: tag, isSelected: selectedTag == tag) { selectedTag = tag }
                            }
                        }
                    }
                }
                Section(header: Text("Pinned")) {
                    ForEach(vm.entries.filter { $0.pinned && filteredEntries.contains($0) }) { entry in
                        EntryRow(entry: entry) { selection = entry }
                    }
                }
                Section(header: Text("All Entries")) {
                    ForEach(filteredEntries.filter { !$0.pinned }) { entry in
                        EntryRow(entry: entry) { selection = entry }
                    }
                    .onDelete { idx in
                        let items = filteredEntries.filter { !$0.pinned }
                        idx.forEach { i in
                            vm.delete(items[i])
                        }
                    }
                }
                Section {
                    NavigationLink(destination: RewardsView()) {
                        Label("Rewards", systemImage: "gift")
                    }
                    NavigationLink(destination: ProfileView()) {
                        Label("Profile", systemImage: "person.circle")
                    }
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Diary")
            .sheet(isPresented: $showEditor) {
                EntryEditorView(initial: nil) { newEntry in
                    vm.add(newEntry)
                    showEditor = false
                }
                .environmentObject(vm)
            }
            .background(
                NavigationLink(destination: selection.map { EntryDetailView(entry: $0) }, isActive: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) { EmptyView() }
            )
        }
    }

    var headerView: some View {
        HStack {
            Text("Search entries")
            Spacer()
        }
    }
}

struct EntryRow: View {
    var entry: DiaryEntry
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(entry.title).font(.headline)
                        if entry.pinned {
                            Image(systemName: "pin.fill").foregroundColor(.yellow)
                        }
                    }
                    Text(entry.body).lineLimit(1).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(entry.date, style: .date).font(.caption)
                    if let mood = entry.mood {
                        Text(mood)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TagChip: View {
    var tag: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.capitalized)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Capsule().fill(Color.accentColor.opacity(0.15)) : Capsule().strokeBorder(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

struct EntryEditorView: View {
    @EnvironmentObject var vm: DiaryViewModel
    @Environment(\.presentationMode) var presentationMode
    @State var entry: DiaryEntry
    var onComplete: (DiaryEntry) -> Void

    init(initial: DiaryEntry?, onComplete: @escaping (DiaryEntry) -> Void) {
        _entry = State(initialValue: initial ?? DiaryEntry(title: "", body: "", date: Date(), tags: [], mood: nil))
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Title")) {
                    TextField("Title", text: $entry.title)
                }
                Section(header: Text("Body")) {
                    TextEditor(text: $entry.body).frame(minHeight: 200)
                }
                Section(header: Text("Tags (comma separated)")) {
                    TextField("e.g. travel,work", text: Binding(
                        get: { entry.tags.joined(separator: ",") },
                        set: { entry.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    ))
                }
                Section(header: Text("Mood (Emoji)")) {
                    TextField("Emoji (optional)", text: Binding(
                        get: { entry.mood ?? "" },
                        set: { entry.mood = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section {
                    Toggle("Pin this entry", isOn: $entry.pinned)
                }
            }
            .navigationTitle(entry.title.isEmpty ? "New Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if vm.entries.contains(where: { $0.id == entry.id }) {
                            vm.update(entry)
                        } else {
                            vm.add(entry)
                        }
                        onComplete(entry)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct EntryDetailView: View {
    @EnvironmentObject var vm: DiaryViewModel
    @State var entry: DiaryEntry
    @State private var editMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.title).font(.largeTitle)
                    HStack {
                        Text(entry.date, style: .date)
                        if let mood = entry.mood {
                            Text(mood)
                        }
                    }
                }
                Spacer()
                Button {
                    vm.togglePin(entry)
                    entry.pinned.toggle()
                } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                }
            }
            ScrollView {
                Text(entry.body)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .padding()
        .navigationTitle(entry.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    editMode = true
                }
            }
        }
        .sheet(isPresented: $editMode) {
            EntryEditorView(initial: entry) { updatedEntry in
                entry = updatedEntry
                vm.update(updatedEntry)
                editMode = false
            }
            .environmentObject(vm)
        }
    }
}

struct RewardsView: View {
    @EnvironmentObject var vm: DiaryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Points").font(.title2)
                    Spacer()
                    Text("\(vm.points)").font(.title).bold()
                }
                HStack {
                    Text("Streak").font(.title2)
                    Spacer()
                    Text("\(vm.currentStreak) days").font(.title).bold()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Badges").font(.headline)
                    if vm.badges.isEmpty {
                        Text("Keep writing to earn badges!").foregroundColor(.secondary)
                    } else {
                        ForEach(vm.badges, id: \.self) { badge in
                            HStack {
                                Image(systemName: "star.fill")
                                Text(badge)
                                Spacer()
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).stroke())
                        }
                    }
                }
                Divider()

                VStack(alignment: .leading) {
                    Text("Daily Missions").font(.headline)
                    MissionRow(title: "Write an entry today", reward: 10, completed: hasWrittenToday()) {
                        performMission()
                    }
                    MissionRow(title: "Tag 3 entries", reward: 20, completed: hasTagged3()) {
                        performTagMission()
                    }
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Rewards")
    }

    func hasWrittenToday() -> Bool {
        guard let last = vm.lastEntryDate else { return false }
        return Calendar.current.isDateInToday(last)
    }
    func performMission() {
        if !hasWrittenToday() {
            vm.points += 10
            vm.lastEntryDate = Date()
            vm.currentStreak += 1
        }
    }
    func hasTagged3() -> Bool {
        vm.entries.filter { $0.tags.count >= 1 }.count >= 3
    }
    func performTagMission() {
        if !hasTagged3() {
            vm.points += 20
        }
    }
}

struct MissionRow: View {
    var title: String
    var reward: Int
    var completed: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text("Reward: \(reward) pts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if completed {
                Label("Done", systemImage: "checkmark.circle")
            }
            Button(action: action) {
                Text(completed ? "Claimed" : "Claim")
            }
            .disabled(completed)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).stroke())
    }
}

struct ProfileView: View {
    @EnvironmentObject var vm: DiaryViewModel
    @State private var name: String = ""
    @State private var colorHex: String = ""

    var body: some View {
        Form {
            Section(header: Text("Personalize")) {
                TextField("Name", text: $name)
                TextField("Accent hex (e.g. #4F46E5)", text: $colorHex)
                Button("Save") {
                    vm.user.name = name.isEmpty ? vm.user.name : name
                    vm.user.preferredColorHex = colorHex.isEmpty ? vm.user.preferredColorHex : colorHex
                }
            }
            Section(header: Text("About")) {
                Text("A private diary with built-in rewards to help build the writing habit.")
                Text("Entries are stored locally for privacy.")
            }
        }
        .onAppear {
            name = vm.user.name
            colorHex = vm.user.preferredColorHex
        }
        .navigationTitle("Profile")
    }
}

struct SettingsView: View {
    @EnvironmentObject var vm: DiaryViewModel
    @AppStorage("appearance") var appearance: String = "system"

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Section {
                Button("Export entries") {
                    exportEntries()
                }
            }
        }
        .navigationTitle("Settings")
    }

    func exportEntries() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(vm.entries),
           let jsonString = String(data: data, encoding: .utf8) {
            print("Exported entries JSON:\n\(jsonString.prefix(1000))")
        }
    }
}
struct DiaryApp_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DiaryViewModel())
    }
}
