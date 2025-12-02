import SwiftUI
import Supabase

struct Exercise: Identifiable, Decodable {
    let id: Int64
    let name: String
    let name_es: String?
    let name_en: String?
    let category: String?
    let modality: String?
    let muscle_primary: String?
    let equipment: String?
    
    func localizedName(for language: ExerciseLanguage) -> String {
        switch language {
        case .spanish:
            return name_es ?? name
        case .english:
            return name_en ?? name
        }
    }
}

struct PickerHandle: Identifiable {
    let id: UUID
}

enum ExerciseLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .spanish: return "Spanish"
        case .english: return "English"
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case alphabetic = "Alphabetic"
    case mostUsed   = "Most used"
    case favorites  = "Favorites"
    case recent     = "Recently used"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .alphabetic: return "A–Z"
        case .mostUsed:   return "Most used"
        case .favorites:  return "Favorites"
        case .recent:     return "Recently used"
        }
    }
}

struct ExercisePickerSheet: View {
    let all: [Exercise]
    @Binding var selected: Exercise?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("exerciseLanguage") private var exerciseLanguageRaw: String = ExerciseLanguage.spanish.rawValue
    @State private var query = ""
    @State private var sortMode: SortMode = .alphabetic
    @State private var loading = false
    @State private var exercises: [Exercise] = []
    @State private var favorites = Set<Int64>()
        
    private var exerciseLanguage: ExerciseLanguage {
        ExerciseLanguage(rawValue: exerciseLanguageRaw) ?? .spanish
    }
    
    var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return exercises }
        return exercises.filter { $0.localizedName(for: exerciseLanguage).lowercased().contains(q) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    SectionCard {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, ex in
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.localizedName(for: exerciseLanguage))
                                        Text(
                                            [ex.category, ex.muscle_primary, ex.equipment]
                                                .compactMap { $0 }
                                                .filter { $0.lowercased() != "strength" }
                                                .joined(separator: " · ")
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        Task { await toggleFavorite(ex.id) }
                                    } label: {
                                        Image(systemName: favorites.contains(ex.id) ? "star.fill" : "star")
                                            .font(.subheadline)
                                            .foregroundStyle(favorites.contains(ex.id) ? .yellow : .secondary)
                                            .opacity(0.9)
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                            .accessibilityLabel(favorites.contains(ex.id) ? "Unfavorite" : "Favorite")
                                            .accessibilityAddTraits(.isButton)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    print("[EXERCISE_PICKER] Row tapped – id=\(ex.id), name='\(ex.name)' (language=\(exerciseLanguageRaw), sortMode=\(sortMode.rawValue))")
                                    selected = ex
                                    dismiss()
                                }
                                if idx < filtered.count - 1 {
                                    Divider()
                                        .padding(.leading, 8)
                                        .opacity(0.75)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listSectionSeparator(.hidden, edges: .top)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $query)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(ExerciseLanguage.allCases) { lang in
                            Button {
                                print("[EXERCISE_PICKER] Language menu tapped – selecting \(lang.label) (\(lang.rawValue)). Previous=\(exerciseLanguageRaw)")
                                exerciseLanguageRaw = lang.rawValue
                                print("[EXERCISE_PICKER] exerciseLanguageRaw now = \(exerciseLanguageRaw)")
                            } label: {
                                HStack {
                                    Text(lang.label)
                                    if exerciseLanguage == lang {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text(exerciseLanguage.label)
                        }
                    }
                    .accessibilityLabel("Language")
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(SortMode.allCases) { mode in
                            Button(mode.label) {
                                print("[EXERCISE_PICKER] Sort menu tapped – mode=\(mode.label) (\(mode.rawValue))")
                                sortMode = mode
                                Task {
                                    print("[EXERCISE_PICKER] Calling loadExercises() after changing sortMode to \(mode.rawValue)")
                                    await loadExercises()
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter")
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
            .overlay {
                if loading {
                    ProgressView("Loading…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task {
                print("[EXERCISE_PICKER] .task onAppear – calling loadExercises() (sortMode=\(sortMode.rawValue), language=\(exerciseLanguageRaw))")
                await loadExercises()
            }
        }
    }
    
    private func loadExercises() async {
        if loading {
            print("[EXERCISE_PICKER] loadExercises() called but already loading – ignoring (sortMode=\(sortMode.rawValue))")
            return
        }
        loading = true
        print("[EXERCISE_PICKER] loadExercises() START – sortMode=\(sortMode.rawValue), language=\(exerciseLanguageRaw)")
        defer {
            loading = false
            print("[EXERCISE_PICKER] loadExercises() END – final exercises.count=\(exercises.count)")
        }
        do {
            await loadFavorites()
            
            switch sortMode {
            case .alphabetic:
                let res = try await SupabaseManager.shared.client
                    .from("exercises")
                    .select("*")
                    .eq("is_public", value: true)
                    .eq("modality", value: "strength")
                    .order("name", ascending: true)
                    .execute()
                exercises = try JSONDecoder().decode([Exercise].self, from: res.data)
                
            case .mostUsed:
                let params: [String: AnyJSON] = [
                    "p_modality": try .init("strength"),
                    "p_search":   try .init(AnyJSON.null),
                    "p_limit":    try .init(200)
                ]
                let res = try await SupabaseManager.shared.client
                    .rpc("get_exercises_usage", params: params)
                    .execute()
                let used = try JSONDecoder.supabaseCustom().decode([ExerciseUsage].self, from: res.data)
                
                exercises = used.compactMap { usage in
                    if let full = all.first(where: { $0.id == usage.id }) {
                        return full
                    } else {
                        return Exercise(
                            id: usage.id,
                            name: usage.name,
                            name_es: nil,
                            name_en: nil,
                            category: nil,
                            modality: "strength",
                            muscle_primary: nil,
                            equipment: nil
                        )
                    }
                }
                
            case .favorites:
                if favorites.isEmpty {
                    exercises = []
                } else {
                    let ids = favorites.map(Int.init)
                    let res = try await SupabaseManager.shared.client
                        .from("exercises")
                        .select("*")
                        .eq("is_public", value: true)
                        .eq("modality", value: "strength")
                        .in("id", values: ids)
                        .order("name", ascending: true)
                        .execute()
                    exercises = try JSONDecoder().decode([Exercise].self, from: res.data)
                }
            case .recent:
                let params: [String: AnyJSON] = [
                    "p_modality": try .init("strength"),
                    "p_search":   try .init(AnyJSON.null),
                    "p_limit":    try .init(200)
                ]
                let res = try await SupabaseManager.shared.client
                    .rpc("get_exercises_usage", params: params)
                    .execute()
                
                let used = try JSONDecoder.supabaseCustom().decode([ExerciseUsage].self, from: res.data)
                
                let sorted = used
                    .filter { $0.last_used_at != nil && $0.times_used > 0 }
                    .sorted { (a, b) in
                        (a.last_used_at ?? .distantPast) > (b.last_used_at ?? .distantPast)
                    }
                
                exercises = sorted.compactMap { usage in
                    if let full = all.first(where: { $0.id == usage.id }) {
                        return full
                    } else {
                        return Exercise(
                            id: usage.id,
                            name: usage.name,
                            name_es: nil,
                            name_en: nil,
                            category: nil,
                            modality: "strength",
                            muscle_primary: nil,
                            equipment: nil
                        )
                    }
                }
            }
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            print("Error loading exercises:", error)
        }
    }
    
    private func loadFavorites() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("user_favorite_exercises")
                .select("exercise_id")
                .execute()
            
            struct Row: Decodable { let exercise_id: Int64 }
            let rows = try JSONDecoder().decode([Row].self, from: res.data)
            
            await MainActor.run {
                favorites = Set(rows.map { $0.exercise_id })
            }
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            print("Error loading favorites:", error)
        }
    }
    
    private struct FavoriteRow: Encodable {
        let user_id: UUID
        let exercise_id: Int64
    }
    
    private func toggleFavorite(_ exerciseId: Int64) async {
        let client = SupabaseManager.shared.client
        
        if favorites.contains(exerciseId) {
            await MainActor.run {
                _ = favorites.remove(exerciseId)
                if sortMode == .favorites {
                    exercises.removeAll { $0.id == exerciseId }
                }
            }
            
            do {
                let session = try await client.auth.session
                _ = try await client
                    .from("user_favorite_exercises")
                    .delete()
                    .eq("user_id", value: session.user.id)
                    .eq("exercise_id", value: Int(exerciseId))
                    .execute()
            } catch {
                await MainActor.run { _ = favorites.insert(exerciseId) }
                print("Error unfavorite:", error)
            }
        } else {
            await MainActor.run { _ = favorites.insert(exerciseId) }
            
            do {
                let session = try await client.auth.session
                struct FavInsert: Encodable { let user_id: UUID; let exercise_id: Int }
                let row = FavInsert(user_id: session.user.id, exercise_id: Int(exerciseId))
                
                _ = try await client
                    .from("user_favorite_exercises")
                    .upsert([row], onConflict: "user_id,exercise_id", returning: .minimal)
                    .execute()
            } catch let err as PostgrestError {
                if err.code != "23505" {
                    await MainActor.run { _ = favorites.remove(exerciseId) }
                    print("Error favorite:", err)
                }
            } catch {
                await MainActor.run { _ = favorites.remove(exerciseId) }
                print("Error favorite:", error)
            }
        }
    }
}
