import SwiftUI
import Supabase
import PhotosUI
import UIKit

private struct ProfileCounts: Decodable, Identifiable {
  let user_id: UUID
  let followers: Int
  let following: Int
  var id: UUID { user_id }
}

private struct ProfileRow: Decodable {
  let user_id: UUID
  let username: String
  let avatar_url: String?
  let bio: String?
}

private struct DayActivity: Decodable, Identifiable {
  let day: String
  let workouts_count: Int
  var id: String { day }
}

private struct WorkoutRow: Decodable, Identifiable {
  let id: Int
  let kind: String
  let title: String?
  let started_at: Date?
  let ended_at: Date?
}

private struct WorkoutScoreRow: Decodable {
  let workout_id: Int
  let score: Double
}

private struct OnlyStartedAt: Decodable {
  let started_at: Date?
}

private struct GetMonthActivityParams: Encodable {
  let p_user_id: UUID
  let p_year: Int
  let p_month: Int
}

private extension JSONDecoder {
  static func supabase() -> JSONDecoder {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .custom { decoder in
      let s = try decoder.singleValueContainer().decode(String.self)

      do {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
      }

      do {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
      }

      do {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        if let d = f.date(from: s) { return d }
      }

      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath,
              debugDescription: "Invalid ISO/RFC3339 date: \(s)")
      )
    }
    return dec
  }
}

struct ProfileView: View {
  @EnvironmentObject var app: AppState

  @State private var counts: ProfileCounts?
  @State private var username: String = ""
  @State private var avatarURL: String?
  @State private var loading = false
  @State private var error: String?
  @State private var pickedItem: PhotosPickerItem?
  @State private var uploadingAvatar = false
  @State private var monthDate = Date()
  @State private var monthDays: [Date?] = []
  @State private var activity: [Date: Int] = [:]
  @State private var selectedDay: Date?
  @State private var bio: String? = nil
  @State private var showEditProfile = false
  @State private var bioExpanded = false

    enum Tab: String { case calendar = "Calendar", prs = "PRs", settings = "Settings" }
  @State private var tab: Tab = .calendar

  var body: some View {
    NavigationStack {
      GradientBackground {
          VStack(spacing: 12) {
            headerCard

              Picker("", selection: $tab) {
                Text("Calendar").tag(Tab.calendar)
                Text("PRs").tag(Tab.prs)
                Text("Settings").tag(Tab.settings)
              }
            .pickerStyle(.segmented)
            .padding(.horizontal)

              switch tab {
              case .calendar: calendarView
              case .prs: prsView
              case .settings: settingsView
              }
          }
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .task {
            let session = try? await SupabaseManager.shared.client.auth.session
            print("[Auth] user.id:", session?.user.id.uuidString ?? "nil")
            await loadProfileHeader()
          }
          .onChange(of: monthDate) { _, newDate in
            monthDays = monthDaysGrid(for: newDate)
            selectedDay = nil
            Task { await loadMonthActivity() }
          }
      }
      .navigationTitle("Profile")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $showEditProfile) {
        EditProfileSheet(
          initialBio: bio ?? "",
          onSaved: { newBio in
            self.bio = newBio.isEmpty ? nil : newBio
          }
        )
      }
    }
  }
    
    private var prsView: some View {
      PRsListView()
    }

  private var headerCard: some View {
    HStack(alignment: .center, spacing: 14) {
        PhotosPicker(selection: $pickedItem, matching: .images) {
          ZStack {
            AvatarView(urlString: avatarURL)
              .frame(width: 64, height: 64)
              .overlay(
                Group {
                  if uploadingAvatar {
                    ProgressView().scaleEffect(0.8)
                  }
                },
                alignment: .bottomTrailing
              )
          }
        }
        .onChange(of: pickedItem) { _, newItem in
          Task { await handlePickedItem(newItem) }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("@\(username.isEmpty ? "user" : username)")
            .font(.title3).fontWeight(.semibold)
          HStack(spacing: 14) {
            HStack(spacing: 4) {
              Image(systemName: "person.2.fill")
              Text("\(counts?.followers ?? 0) followers")
            }.font(.subheadline)
            HStack(spacing: 4) {
              Image(systemName: "arrowshape.turn.up.right.fill")
              Text("\(counts?.following ?? 0) following")
            }.font(.subheadline)
          }
          .foregroundStyle(.secondary)

          if let bio, !bio.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text(bio)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(bioExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .animation(.easeInOut, value: bioExpanded)

              HStack(spacing: 14) {
                Button(bioExpanded ? "Show less" : "Read more") {
                  bioExpanded.toggle()
                }
                .font(.caption)
                .buttonStyle(.plain)

                Button {
                  showEditProfile = true
                } label: {
                  Label("Edit", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit bio")
              }
              .foregroundStyle(.secondary)
            }
          } else {
            Button {
              showEditProfile = true
            } label: {
              Label("Add bio", systemImage: "pencil")
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
          }
        }
      Spacer()
    }
    .padding(16)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.22), lineWidth: 0.8))
    .padding(.horizontal)
  }

  private var calendarView: some View {
    VStack(spacing: 12) {
      HStack {
        Button {
          monthDate = Calendar.current.date(byAdding: .month, value: -1, to: monthDate)!
        } label: { Image(systemName: "chevron.left") }

        Spacer()
        Text(monthTitle(for: monthDate)).font(.headline)
        Spacer()

        Button {
          monthDate = Calendar.current.date(byAdding: .month, value: 1, to: monthDate)!
        } label: { Image(systemName: "chevron.right") }
      }
      .padding(.horizontal)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
          ForEach(weekdays(), id: \.self) { w in
            Text(w).font(.caption2).foregroundStyle(.secondary)
          }
          ForEach(monthDays.indices, id: \.self) { idx in
            let day = monthDays[idx]
            let count = day.flatMap { activity[$0.startOfDay] } ?? 0

            Button {
              if let day { selectedDay = day }
            } label: {
              ZStack {
                RoundedRectangle(cornerRadius: 8)
                  .fill(day != nil && count > 0 ? Color.green.opacity(min(0.15 + Double(count)*0.1, 0.35)) : Color.clear)

                if let day {
                  Text("\(Calendar.current.component(.day, from: day))").font(.footnote)
                } else {
                  Text("")
                }
              }
              .frame(height: 36)
            }
            .buttonStyle(.plain)
            .disabled(day == nil)
          }
        }
        .padding(.horizontal)

        if let selectedDay {
          DayWorkoutsList(selectedDay: selectedDay)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
          Text("Select a day to see your workouts")
            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
        }
    }
    .task { await prepareMonthAndLoad() }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

    private struct PRRow: Decodable, Identifiable {
      let kind: String
      let user_id: UUID
      let label: String
      let metric: String
      let value: Double
      let achieved_at: Date

      var id: String { "\(kind)|\(label)|\(metric)|\(achieved_at.timeIntervalSince1970)" }
    }

    private struct PRsListView: View {
      @EnvironmentObject var app: AppState

      enum KindFilter: String, CaseIterable { case all = "All", strength = "Strength", cardio = "Cardio", sport = "Sport" }
      @State private var filter: KindFilter = .all
      @State private var search: String = ""
      @State private var prs: [PRRow] = []
      @State private var loading = false
      @State private var error: String?
        
        private var sections: [(title: String, items: [PRRow])] {
          grouped(by: sectionKey)
        }

      var body: some View {
        VStack(spacing: 10) {
          HStack {
              Picker("Kind", selection: $filter) {
                ForEach(KindFilter.allCases, id: \.self) { kind in
                  Text(kind.rawValue).tag(kind)
                }
              }
            .pickerStyle(.segmented)
          }
          .padding(.horizontal)

            List {
              if loading { ProgressView().frame(maxWidth: .infinity) }

              ForEach(sections, id: \.title) { section in
                Section(section.title) {
                  ForEach(section.items, id: \.id) { pr in
                      HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                          Text(pr.label).font(.body.weight(.semibold))
                          Text(prettyMetricName(pr.metric, kind: pr.kind))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                          Text(formatValue(pr))
                            .font(.headline)
                            .fontWeight(.semibold)
                          Text(dateOnly(pr.achieved_at))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                      }
                  }
                }
              }
            }
          .listStyle(.insetGrouped)
        }
        .task { await load() }
        .onChange(of: filter) { _, _ in Task { await load() } }
      }

      private func load() async {
        guard let uid = app.userId else { return }
        loading = true; defer { loading = false }

        do {
            var query: PostgrestFilterBuilder = SupabaseManager.shared.client
              .from("vw_user_prs")
              .select("*")
              .eq("user_id", value: uid.uuidString)

            if filter != .all {
              query = query.eq("kind", value: filter.rawValue.lowercased())
            }

            let res = try await query
              .order("achieved_at", ascending: false)
              .execute()
          let rows = try JSONDecoder.supabase().decode([PRRow].self, from: res.data)
          await MainActor.run { prs = rows }
        } catch {
          await MainActor.run { self.error = error.localizedDescription }
        }
      }

      private func sectionKey(_ pr: PRRow) -> String {
        switch pr.kind {
        case "strength": return "Strength"
        case "cardio":   return "Cardio"
        case "sport":    return "Sport"
        default:         return "Other"
        }
      }

      private func grouped(by key: (PRRow) -> String) -> [(title: String, items: [PRRow])] {
        let dict = Dictionary(grouping: filtered(prs), by: key)
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.achieved_at > $1.achieved_at }) }
      }

      private func filtered(_ items: [PRRow]) -> [PRRow] {
        guard !search.isEmpty else { return items }
        return items.filter { $0.label.localizedCaseInsensitiveContains(search) || $0.metric.localizedCaseInsensitiveContains(search) }
      }

        private func prettyMetricName(_ metric: String, kind: String) -> String {
          let m = metric.lowercased()
          if m == "max_hr" { return "Max HR" }
          if m == "longest_duration_sec" { return "Longest duration" }
          if m == "longest_distance_km" { return "Longest distance" }
          if m == "fastest_pace_sec_per_km" { return "Fastest pace" }
          if m == "max_elevation_m" { return "Max elevation" }
          if m == "est_1rm_kg" { return "Estimated 1RM" }
          if m == "max_weight_kg" { return "Max weight" }
          if m == "best_set_volume_kg" { return "Best set volume" }
          if m == "max_reps" { return "Max reps" }
          return snakeToTitle(m)
        }

        private func formatValue(_ pr: PRRow) -> String {
          let m = pr.metric.lowercased()
          let v = pr.value

          if m.hasSuffix("_kg") || m == "est_1rm_kg" || m == "max_weight_kg" || m == "best_set_volume_kg" {
            return String(format: "%.1f kg", v)
          }
          if m.contains("reps") {
            return "\(Int(v.rounded())) reps"
          }
          if m == "max_hr" {
            return "\(Int(v.rounded())) bpm"
          }
          if m == "longest_distance_km" {
            return String(format: "%.1f km", v)
          }
          if m == "max_elevation_m" {
            return "\(Int(v.rounded())) m"
          }
          if m == "fastest_pace_sec_per_km" {
            return paceString(fromSeconds: v)
          }
          if m.hasSuffix("_sec") || m.contains("duration") {
            return durationString(fromSeconds: v)
          }
          return String(format: "%.2f", v)
        }

        private func durationString(fromSeconds secondsDouble: Double) -> String {
          let s = max(0, Int(secondsDouble.rounded()))
          let h = s / 3600
          let m = (s % 3600) / 60
          let sec = s % 60
          if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
          return String(format: "%d:%02d", m, sec)
        }

        private func paceString(fromSeconds secondsDouble: Double) -> String {
          let s = max(1, Int(secondsDouble.rounded()))
          let m = s / 60
          let sec = s % 60
          return String(format: "%d:%02d /km", m, sec)
        }

        private func snakeToTitle(_ s: String) -> String {
          s.replacingOccurrences(of: "_", with: " ")
            .capitalized
        }

      private func dateOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
      }
    }

  private var settingsView: some View {
    List {
      Section("Account") {
        Text("User ID: \(app.userId?.uuidString ?? "–")")
      }
      Section {
        Button(role: .destructive) { app.signOut() } label: { Text("Sign out") }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func loadProfileHeader() async {
    guard let uid = app.userId else { return }
    loading = true; defer { loading = false }

    do {
      let res1 = try await SupabaseManager.shared.client
        .from("profiles")
        .select()
        .eq("user_id", value: uid.uuidString)
        .single()
        .execute()

      let profile = try JSONDecoder.supabase().decode(ProfileRow.self, from: res1.data)
      username = profile.username
      avatarURL = profile.avatar_url
      bio = profile.bio

      let res2 = try await SupabaseManager.shared.client
        .from("vw_profile_counts")
        .select()
        .eq("user_id", value: uid.uuidString)
        .execute()

      let rows = try JSONDecoder.supabase().decode([ProfileCounts].self, from: res2.data)
      counts = rows.first ?? ProfileCounts(user_id: uid, followers: 0, following: 0)
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func prepareMonthAndLoad() async {
    monthDays = monthDaysGrid(for: monthDate)
    await loadMonthActivity()
  }

  private func loadMonthActivity() async {
    guard let uid = app.userId else { return }
    let cal = Calendar.current
    let year = cal.component(.year, from: monthDate)
    let month = cal.component(.month, from: monthDate)

      do {
        var cal = Calendar.current
        cal.timeZone = .current
        let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        let res = try await SupabaseManager.shared.client
          .from("workouts")
          .select("started_at")
          .eq("user_id", value: uid.uuidString)
          .gte("started_at", value: iso.string(from: monthStart))
          .lt("started_at", value: iso.string(from: monthEnd))
          .execute()

        let rows = try JSONDecoder.supabase().decode([OnlyStartedAt].self, from: res.data)

        var dict: [Date: Int] = [:]
        for r in rows {
          if let d = r.started_at {
            let key = cal.startOfDay(for: d)
            dict[key, default: 0] += 1
          }
        }

        await MainActor.run { self.activity = dict }
      } catch {
        await MainActor.run { self.error = error.localizedDescription }
      }
  }

    private func handlePickedItem(_ item: PhotosPickerItem?) async {
      guard let item, let uid = app.userId else { return }
      await MainActor.run { uploadingAvatar = true }

      func log(_ m: String) { print("[Avatar]", m) }

      do {
        log("start")

        let data = try await item.loadTransferable(type: Data.self) ?? Data()
        guard let uiImage = UIImage(data: data) else {
          throw NSError(domain: "image", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        guard let jpeg = resizedJPEG(from: uiImage, maxSide: 1024, quality: 0.85) else {
          throw NSError(domain: "jpeg", code: -2, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
        }
        log("jpeg size: \(kbString(jpeg))")

        let fileName = "\(uid.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
        log("upload → \(fileName)")
        try await SupabaseManager.shared.client.storage
          .from("avatars")
          .upload(fileName, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))

        log("upload ok")

        let publicURL = try SupabaseManager.shared.client.storage
          .from("avatars")
          .getPublicURL(path: fileName)
        log("publicURL: \(publicURL.absoluteString)")

        let payload: [String: String] = ["avatar_url": publicURL.absoluteString]
        log("update profiles")
        _ = try await SupabaseManager.shared.client
          .from("profiles")
          .update(payload)
          .eq("user_id", value: uid.uuidString)
          .execute()
        log("update ok")

        let check = try await SupabaseManager.shared.client
          .from("profiles")
          .select("avatar_url")
          .eq("user_id", value: uid.uuidString)
          .single()
          .execute()
        log("db row: " + (String(data: check.data, encoding: .utf8) ?? "—"))

        await MainActor.run {
          self.avatarURL = publicURL.absoluteString
        }
      } catch {
        await MainActor.run { self.error = error.localizedDescription }
        print("[Avatar][ERROR]", error.localizedDescription)
      }

      await MainActor.run { uploadingAvatar = false }
    }

  private func monthTitle(for date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f.string(from: date).capitalized
  }

  private func weekdays() -> [String] {
    let f = DateFormatter(); f.locale = .current; return f.shortWeekdaySymbols
  }

    private func monthDaysGrid(for date: Date) -> [Date?] {
      let cal = Calendar.current
      let range = cal.range(of: .day, in: .month, for: date)!
      let first = cal.date(from: cal.dateComponents([.year, .month], from: date))!
      let firstWeekdayIndex = cal.component(.weekday, from: first) - cal.firstWeekday
      let leading = (firstWeekdayIndex + 7) % 7
      let monthDates: [Date] = range.compactMap { day -> Date? in
        cal.date(byAdding: .day, value: day - 1, to: first)
      }

      var grid: [Date?] = Array(repeating: nil, count: leading) + monthDates.map { Optional($0) }
      while grid.count % 7 != 0 { grid.append(nil) }
      return grid
    }
}

private struct AvatarView: View {
  let urlString: String?
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12).fill(.thinMaterial)
      if let urlString, let url = URL(string: urlString) {
        AsyncImage(url: url) { phase in
          switch phase {
          case .empty: ProgressView()
          case .success(let img): img.resizable().scaledToFill()
          case .failure: Image(systemName: "person.fill").resizable().scaledToFit().padding(12)
          @unknown default: EmptyView()
          }
        }
      } else {
        Image(systemName: "person.fill").resizable().scaledToFit().padding(12)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

private struct DayWorkoutsList: View {
  let selectedDay: Date
  @EnvironmentObject var app: AppState
  @State private var workouts: [WorkoutRow] = []
  @State private var scores: [Int: Double] = [:]
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(dateTitle(selectedDay))
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)

        if workouts.isEmpty {
          Text("No workouts this day").foregroundStyle(.secondary).padding(.horizontal)
        } else {
            GeometryReader { geo in
              ScrollView {
                LazyVStack(spacing: 12) {
                  ForEach(workouts) { w in
                    ZStack {
                      RoundedRectangle(cornerRadius: 14)
                        .fill(backgroundFor(kind: w.kind))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15)))

                      HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                          Text(w.title ?? w.kind.capitalized)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)

                          Text(timeRange(w))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                          kindBadge(w.kind)
                        }
                        Spacer()
                        if let sc = scores[w.id] {
                          Text(scoreString(sc))
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(Color.black.opacity(0.08)))
                            .overlay(Capsule().stroke(.white.opacity(0.15)))
                            .accessibilityLabel("Score \(scoreString(sc))")
                        }
                      }
                      .padding(14)
                    }
                    .padding(.horizontal)
                  }
                }
                Color.clear.frame(height: 8)
              }
            }
        }
    }
    .task(id: selectedDay) { await load() }
    .onChange(of: selectedDay) { _, _ in
      workouts = []
      scores = [:]
    }
  }

    private func load() async {
      guard let uid = app.userId else { return }

        var cal = Calendar.current
        cal.timeZone = .current
        let start = cal.startOfDay(for: selectedDay)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current

      do {
        let res = try await SupabaseManager.shared.client
          .from("workouts")
          .select("*")
          .eq("user_id", value: uid.uuidString)
          .gte("started_at", value: iso.string(from: start))
          .lt("started_at", value: iso.string(from: end))
          .order("started_at", ascending: false)
          .execute()

          let rows = try JSONDecoder.supabase().decode([WorkoutRow].self, from: res.data)
          let ids = rows.map { $0.id }
          var scoresDict: [Int: Double] = [:]
          if !ids.isEmpty {
            let scoreRes = try await SupabaseManager.shared.client
              .from("workout_scores")
              .select("workout_id, score")
              .in("workout_id", values: ids)
              .execute()
            let scoreRows = try JSONDecoder.supabase().decode([WorkoutScoreRow].self, from: scoreRes.data)
            scoresDict = Dictionary(uniqueKeysWithValues: scoreRows.map { ($0.workout_id, $0.score) })
          }

          await MainActor.run {
            workouts = rows
            scores = scoresDict
          }
        } catch {
        await MainActor.run { self.error = error.localizedDescription }
      }
    }

  private func dateTitle(_ d: Date) -> String {
    let f = DateFormatter(); f.dateStyle = .full; return f.string(from: d)
  }

  private func timeRange(_ w: WorkoutRow) -> String {
    let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
    guard let started = w.started_at else { return "—" }
    let s = f.string(from: started)
    if let ended = w.ended_at { return "\(s) – \(f.string(from: ended))" }
    return s
  }
    
    private func scoreString(_ s: Double) -> String {
      String(format: "%.0f", s)
    }

    @ViewBuilder
    private func kindBadge(_ kind: String) -> some View {
      Text(kind.capitalized)
        .font(.caption2.weight(.semibold))
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.black.opacity(0.06)))
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
    
    private func backgroundFor(kind: String) -> AnyShapeStyle {
      switch kind.lowercased() {
      case "strength": return AnyShapeStyle(Color.green.opacity(0.10).gradient)
      case "cardio":   return AnyShapeStyle(Color.blue.opacity(0.10).gradient)
      case "sport":    return AnyShapeStyle(Color.orange.opacity(0.10).gradient)
      default:         return AnyShapeStyle(.ultraThinMaterial)
      }
    }
}

private extension Date {
  var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

private func resizedJPEG(from image: UIImage, maxSide: CGFloat = 1024, quality: CGFloat = 0.85) -> Data? {
  let size = image.size
  let scale = min(maxSide / max(size.width, size.height), 1)
  let newSize = CGSize(width: size.width * scale, height: size.height * scale)

  UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
  image.draw(in: CGRect(origin: .zero, size: newSize))
  let resized = UIGraphicsGetImageFromCurrentImageContext()
  UIGraphicsEndImageContext()

  return resized?.jpegData(compressionQuality: quality)
}

private func kbString(_ data: Data) -> String {
  String(format: "%.1f KB", Double(data.count)/1024.0)
}
