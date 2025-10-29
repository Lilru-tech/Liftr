import SwiftUI
import Supabase

struct CommentsSheet: View {
  @EnvironmentObject var app: AppState
  let workoutId: Int
  let ownerId: UUID
  var onDidChange: (() async -> Void)?
  @State private var page = 0
  private let pageSize = 20
  @State private var canLoadMore = true
  @State private var isLoading = false
  @State private var items: [CommentItem] = []
  @State private var profiles: [UUID: ProfileRow] = [:]
  @State private var newBody = ""
  @State private var sending = false

  struct ProfileRow: Decodable { let user_id: UUID; let username: String; let avatar_url: String? }

  struct CommentWire: Decodable, Identifiable {
    let id: Int
    let workout_id: Int
    let parent_id: Int?
    let user_id: UUID
    let body: String?
    let replies_count: Int
    let likes_count: Int
    let deleted_at: Date?
    let deleted_by: UUID?
    let created_at: Date
    let profiles: ProfileRow?
  }

    struct CommentItem: Identifiable {
      let id: Int
      let parentId: Int?
      let userId: UUID
      let body: String?
      let repliesCount: Int
      var likesCount: Int
      var likedByMe: Bool
      let deletedAt: Date?
      let createdAt: Date
      var profile: ProfileRow?
      var replies: [CommentItem] = []
      var repliesLoaded: Bool = false
      var isExpanded: Bool = false

      func hash(into hasher: inout Hasher) {
        hasher.combine(id)
      }
    }

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          AvatarView(urlString: profiles[app.userId ?? UUID()]?.avatar_url)
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          TextField("Add a comment…", text: $newBody, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
          Button {
            Task { await sendComment(parentId: nil) }
          } label: {
            if sending { ProgressView() } else { Text("Send").font(.callout.weight(.semibold)) }
          }
          .disabled(sending || newBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)

        List {
          ForEach(items) { it in
            CommentRowView(
              item: it,
              ownerId: ownerId,
              profile: profiles[it.userId],
              onToggleLike: { Task { await toggleLike(commentId: it.id) } },
              onReply: { text in Task { await sendComment(parentId: it.id, bodyOverride: text) } },
              onDelete: { Task { await softDelete(commentId: it.id) } },
              onExpand: { Task { await loadReplies(for: it.id) } }
            )
            .listRowBackground(Color.clear)
            .onAppear {
              if it.id == items.last?.id, canLoadMore, !isLoading {
                Task { await loadPage(reset: false) }
              }
            }

            if it.isExpanded {
              ForEach(it.replies) { r in
                CommentRowView(
                  item: r,
                  ownerId: ownerId,
                  profile: profiles[r.userId],
                  isReply: true,
                  onToggleLike: { Task { await toggleLike(commentId: r.id) } },
                  onReply: { text in Task { await sendComment(parentId: it.id, bodyOverride: text) } },
                  onDelete: { Task { await softDelete(commentId: r.id) } },
                  onExpand: { }
                )
                .listRowBackground(Color.clear)
              }
            }
          }

          if isLoading && !items.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
              .listRowBackground(Color.clear)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
      .padding(.top, 8)
      .navigationTitle("Comments")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await refreshAll() }
          } label: { Image(systemName: "arrow.clockwise") }
        }
      }
      .task { await refreshAll() }
    }
  }

  private func refreshAll() async {
    await loadMyProfileIfNeeded()
    await loadPage(reset: true)
  }

  private func loadMyProfileIfNeeded() async {
    guard let me = app.userId, profiles[me] == nil else { return }
    do {
      let pRes = try await SupabaseManager.shared.client
        .from("profiles")
        .select("user_id, username, avatar_url")
        .eq("user_id", value: me.uuidString)
        .single()
        .execute()
      let p = try JSONDecoder.supabase().decode(ProfileRow.self, from: pRes.data)
      await MainActor.run { profiles[me] = p }
    } catch { }
  }

  private func loadPage(reset: Bool) async {
    guard !isLoading else { return }
    await MainActor.run {
      if reset { items = []; page = 0; canLoadMore = true }
      isLoading = true
    }
    defer { Task { await MainActor.run { isLoading = false } } }

    do {
        let from = page * pageSize
        let to = from + pageSize - 1
        let res = try await SupabaseManager.shared.client
          .from("workout_comments")
          .select("id,workout_id,parent_id,user_id,body,replies_count,likes_count,deleted_at,deleted_by,created_at,profiles!workout_comments_user_id_fkey(user_id,username,avatar_url)")
          .eq("workout_id", value: workoutId)
          .is("parent_id", value: nil)
          .order("created_at", ascending: true)
          .range(from: from, to: to)
          .execute()
        print("⤵️ workout_comments status:", res.status)
        if let raw = String(data: res.data, encoding: .utf8) {
          print("⤵️ workout_comments json:", raw)
        }
      let rows = try JSONDecoder.supabase().decode([CommentWire].self, from: res.data)
      let ids = rows.map { $0.id }
      var likedSet: Set<Int> = []
      if let me = app.userId, !ids.isEmpty {
        let likeRes = try await SupabaseManager.shared.client
          .from("workout_comment_likes")
          .select("comment_id")
          .in("comment_id", values: ids)
          .eq("user_id", value: me.uuidString)
          .execute()
        struct LikeOnly: Decodable { let comment_id: Int }
        let likesMine = try JSONDecoder.supabase().decode([LikeOnly].self, from: likeRes.data)
        likedSet = Set(likesMine.map { $0.comment_id })
      }

        let newItems: [CommentItem] = rows.map {
          let visibleBody = visibleBodyFor($0)
          let prof = $0.profiles
          if let prof { profiles[prof.user_id] = prof }
          return CommentItem(
            id: $0.id,
            parentId: $0.parent_id,
            userId: $0.user_id,
            body: visibleBody,
            repliesCount: $0.replies_count,
            likesCount: $0.likes_count,
            likedByMe: likedSet.contains($0.id),
            deletedAt: $0.deleted_at,
            createdAt: $0.created_at,
            profile: $0.profiles
          )
        }

        await MainActor.run {
          var copy = items
          copy.append(contentsOf: newItems)
          items = copy
          canLoadMore = rows.count == pageSize
          if canLoadMore { page += 1 }
        }

    } catch {
      await MainActor.run { canLoadMore = false }
    }
  }

    private func loadReplies(for parentId: Int, forceReload: Bool = false) async {
        guard let idx = items.firstIndex(where: { $0.id == parentId }) else { return }
          if items[idx].repliesLoaded && !forceReload {
            await MainActor.run {
              print("🧵 toggle expand for parent \(parentId) (already loaded)")
              withAnimation { items[idx].isExpanded.toggle() }
            }
            return
          }

    do {
      let res = try await SupabaseManager.shared.client
        .from("workout_comments")
        .select("id,workout_id,parent_id,user_id,body,replies_count,likes_count,deleted_at,deleted_by,created_at,profiles!workout_comments_user_id_fkey(user_id,username,avatar_url)")
        .eq("workout_id", value: workoutId)
        .eq("parent_id", value: parentId)
        .order("created_at", ascending: true)
        .limit(200)
        .execute()
      let rows = try JSONDecoder.supabase().decode([CommentWire].self, from: res.data)

      let ids = rows.map { $0.id }
      var likedSet: Set<Int> = []
      if let me = app.userId, !ids.isEmpty {
        let likeRes = try await SupabaseManager.shared.client
          .from("workout_comment_likes")
          .select("comment_id")
          .in("comment_id", values: ids)
          .eq("user_id", value: me.uuidString)
          .execute()
        struct LikeOnly: Decodable { let comment_id: Int }
        let likesMine = try JSONDecoder.supabase().decode([LikeOnly].self, from: likeRes.data)
        likedSet = Set(likesMine.map { $0.comment_id })
      }

      let replies: [CommentItem] = rows.map {
        let visibleBody = visibleBodyFor($0)
        if let prof = $0.profiles { profiles[prof.user_id] = prof }
        return CommentItem(
          id: $0.id,
          parentId: $0.parent_id,
          userId: $0.user_id,
          body: visibleBody,
          repliesCount: $0.replies_count,
          likesCount: $0.likes_count,
          likedByMe: likedSet.contains($0.id),
          deletedAt: $0.deleted_at,
          createdAt: $0.created_at,
          profile: $0.profiles
        )
      }

        await MainActor.run {
          if let i = items.firstIndex(where: { $0.id == parentId }) {
            print("🧵 setting \(replies.count) replies for parent \(parentId); expanding row")
            var parent = items[i]
            parent.replies = replies
            parent.repliesLoaded = true
            parent.isExpanded = true
            items[i] = parent
            let snapshot = items
            items = snapshot
          }
        }
    } catch {
        print("❌ loadReplies error for parent \(parentId):", error)
    }
  }

    private func visibleBodyFor(_ c: CommentWire) -> String? {
      return c.deleted_at == nil ? c.body : nil
    }

  private func sendComment(parentId: Int?, bodyOverride: String? = nil) async {
    guard let me = app.userId else { return }
    let text = (bodyOverride ?? newBody).trimmingCharacters(in: .whitespacesAndNewlines)
      print("💬 sendComment parentId:\(parentId?.description ?? "nil") text:'\(text)'")
    guard !text.isEmpty else { return }

    await MainActor.run { sending = true }
    defer { Task { await MainActor.run { sending = false } } }

    struct Insert: Encodable { let workout_id: Int; let parent_id: Int?; let user_id: UUID; let body: String }
    do {
      _ = try await SupabaseManager.shared.client
        .from("workout_comments")
        .insert(Insert(workout_id: workoutId, parent_id: parentId, user_id: me, body: text))
        .execute()

      if parentId == nil {
        await MainActor.run { newBody = "" }
      }

        if let pid = parentId {
            if let idx = items.firstIndex(where: { $0.id == pid }) {
                if !items[idx].isExpanded {
                    await MainActor.run { items[idx].isExpanded = true }
                }
            }
            await loadReplies(for: pid, forceReload: true)
        } else {
            await refreshAll()
            print("💬 root comment inserted → refreshAll()")
        }

      await onDidChange?()
    } catch {
        print("❌ sendComment error:", error)
    }
  }

  private func toggleLike(commentId: Int) async {
    guard let me = app.userId else { return }
    let (isLiked, path) = currentLikeState(commentId: commentId)
      print("♥️ toggleLike tapped for \(commentId) – current liked:", isLiked)
    do {
      if isLiked {
          print("♥️ unliking comment \(commentId)")
        _ = try await SupabaseManager.shared.client
          .from("workout_comment_likes")
          .delete()
          .eq("comment_id", value: commentId)
          .eq("user_id", value: me.uuidString)
          .execute()
        await bumpLikeLocally(commentId: commentId, delta: -1, liked: false)
      } else {
        struct LikeInsert: Encodable { let comment_id: Int; let user_id: UUID }
          print("♥️ liking comment \(commentId)")
        _ = try await SupabaseManager.shared.client
          .from("workout_comment_likes")
          .insert(LikeInsert(comment_id: commentId, user_id: me))
          .execute()
        await bumpLikeLocally(commentId: commentId, delta: +1, liked: true)
      }
    } catch {
        print("❌ toggleLike error:", error)
      await reloadSingle(commentId: commentId, at: path)
    }
  }

  private func currentLikeState(commentId: Int) -> (Bool, IndexPath?) {
    if let i = items.firstIndex(where: { $0.id == commentId }) {
      return (items[i].likedByMe, IndexPath(row: i, section: 0))
    }
    for (idx, parent) in items.enumerated() where parent.isExpanded {
      if let j = parent.replies.firstIndex(where: { $0.id == commentId }) {
        return (parent.replies[j].likedByMe, IndexPath(row: j, section: idx+1))
      }
    }
    return (false, nil)
  }

    @MainActor
    private func bumpLikeLocally(commentId: Int, delta: Int, liked: Bool) async {
        if let i = items.firstIndex(where: { $0.id == commentId }) {
            var it = items[i]
            it.likesCount = max(0, it.likesCount + delta)
            it.likedByMe = liked
            items[i] = it
            print("↩️ updated top-level comment \(commentId) → likes:\(it.likesCount) likedByMe:\(it.likedByMe)")
        } else {
            for idx in items.indices where items[idx].isExpanded {
                if let j = items[idx].replies.firstIndex(where: { $0.id == commentId }) {
                    var reply = items[idx].replies[j]
                    reply.likesCount = max(0, reply.likesCount + delta)
                    reply.likedByMe = liked
                    items[idx].replies[j] = reply
                    print("↩️ updated reply \(commentId) in parent \(items[idx].id) → likes:\(reply.likesCount) likedByMe:\(reply.likedByMe)")
                    break
                }
            }
        }
        let snapshot = items
        items = snapshot
    }

  private func reloadSingle(commentId: Int, at _: IndexPath?) async {
    do {
      let res = try await SupabaseManager.shared.client
        .from("workout_comments")
        .select("id,workout_id,parent_id,user_id,body,replies_count,likes_count,deleted_at,deleted_by,created_at,profiles!workout_comments_user_id_fkey(user_id,username,avatar_url)")
        .eq("id", value: commentId)
        .single()
        .execute()
      let c = try JSONDecoder.supabase().decode(CommentWire.self, from: res.data)
      let bodyVisible = visibleBodyFor(c)
      let item = CommentItem(
        id: c.id,
        parentId: c.parent_id,
        userId: c.user_id,
        body: bodyVisible,
        repliesCount: c.replies_count,
        likesCount: c.likes_count,
        likedByMe: false,
        deletedAt: c.deleted_at,
        createdAt: c.created_at,
        profile: c.profiles
      )
      if let me = app.userId {
        let likeRes = try await SupabaseManager.shared.client
          .from("workout_comment_likes")
          .select("comment_id")
          .eq("comment_id", value: commentId)
          .eq("user_id", value: me.uuidString)
          .limit(1)
          .execute()
        struct LikeOnly: Decodable { let comment_id: Int }
        let liked = try JSONDecoder.supabase().decode([LikeOnly].self, from: likeRes.data).isEmpty == false
        await MainActor.run { upsert(item: item, liked: liked) }
      } else {
        await MainActor.run { upsert(item: item, liked: false) }
      }
    } catch { }
  }

  @MainActor
  private func upsert(item: CommentItem, liked: Bool) {
    if let i = items.firstIndex(where: { $0.id == item.id }) {
        print("🔁 upsert comment \(item.id) liked:\(liked)")
      var copy = item; copy.likedByMe = liked
      items[i] = copy
      let snapshot = items
      items = snapshot
      return
    }
      for idx in items.indices where items[idx].isExpanded {
        if let j = items[idx].replies.firstIndex(where: { $0.id == item.id }) {
          var copy = item; copy.likedByMe = liked
          items[idx].replies[j] = copy
          print("🔁 upsert reply \(item.id) in parent \(items[idx].id) liked:\(liked)")
          let snapshot = items
          items = snapshot
          return
        }
      }
  }

    private func softDelete(commentId: Int) async {
        guard let me = app.userId else { return }
        do {
            print("🗑️ softDelete \(commentId) started")
            struct Patch: Encodable { let deleted_at: Date; let deleted_by: UUID }
            _ = try await SupabaseManager.shared.client
                .from("workout_comments")
                .update(Patch(deleted_at: Date(), deleted_by: me))
                .eq("id", value: commentId)
                .execute()

            await reloadSingle(commentId: commentId, at: nil)
            await MainActor.run {
                let snapshot = items
                items = snapshot
            }

            print("🗑️ softDelete \(commentId) done – reloaded")
            await onDidChange?()
        } catch {
            print("❌ softDelete update error for \(commentId):", error)
        }
    }
}

private struct CommentRowView: View {
  let item: CommentsSheet.CommentItem
  let ownerId: UUID
  let profile: CommentsSheet.ProfileRow?
  var isReply: Bool = false

  var onToggleLike: () async -> Void
  var onReply: (_ text: String) async -> Void
  var onDelete: () async -> Void
  var onExpand: () async -> Void

  @State private var replyText = ""
  @State private var showReply = false

  var canDelete: Bool {
    if let p = profile { return p.user_id == item.userId || ownerId == p.user_id }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        AvatarView(urlString: profile?.avatar_url)
          .frame(width: 32, height: 32)
          .clipShape(RoundedRectangle(cornerRadius: 8))

        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(profile.map { "@\($0.username)" } ?? "@user")
              .font(.subheadline.weight(.semibold))
            Text("• \(relative(item.createdAt))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let body = item.body {
            Text(body).font(.subheadline)
          } else {
            Text("Comment deleted")
              .font(.subheadline.italic())
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

          Button { print("♥️ Like tapped for item \(item.id)"); Task { await onToggleLike() } } label: {
            HStack(spacing: 6) {
              Image(systemName: item.likedByMe ? "heart.fill" : "heart")
                .symbolRenderingMode(.palette)
                .foregroundStyle(item.likedByMe ? .red : .secondary)
              Text("\(item.likesCount)")
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .contentShape(Rectangle())
          }
          .buttonStyle(.borderless)
      }

      HStack(spacing: 10) {
        Button {
          showReply.toggle()
        } label: {
          Label("Reply", systemImage: "arrowshape.turn.up.left")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)

          if item.repliesCount > 0 && !isReply {
              Button {
                print("🧵 Toggle replies tapped for parent \(item.id)")
                Task { await onExpand() }
              } label: {
                Text(item.isExpanded
                     ? "Hide replies"
                     : (item.repliesCount == 1 ? "View 1 reply" : "View \(item.repliesCount) replies"))
                  .font(.caption.weight(.semibold))
                  .contentShape(Rectangle())
              }
              .buttonStyle(.borderless)
          }

        if canDelete && item.body != nil {
            Button(role: .destructive) {
              print("🗑️ Delete tapped for \(item.id)")
              Task { await onDelete() }
            } label: {
            Label("Delete", systemImage: "trash")
          }
          .buttonStyle(.borderless)
        }
      }
      .font(.caption)

      if showReply {
        HStack(spacing: 8) {
          TextField("Write a reply…", text: $replyText, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
          Button("Send") {
            let t = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
              print("💬 quick reply send for parent \(item.id) text:'\(t)'")
            Task {
              await onReply(t)
              replyText = ""
              showReply = false
            }
          }
          .font(.callout.weight(.semibold))
          .buttonStyle(.borderless)
        }
      }
    }
    .padding(.vertical, 8)
    .padding(.leading, isReply ? 44 : 0)
  }

  private func relative(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
  }
}
