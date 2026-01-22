import SwiftUI

struct FeatureRequestsListView: View {
    @EnvironmentObject var app: AppState
    
    @State private var loading = false
    @State private var error: String?
    @State private var items: [FeatureRequestRow] = []
    @State private var showCreate = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            VStack(spacing: 12) {
                header

                Group {
                    if loading {
                        ProgressView()
                            .padding(.top, 20)
                    } else if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    } else if items.isEmpty {
                        VStack(spacing: 10) {
                            Text("No feature requests yet")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        List {
                            ForEach(items) { fr in
                                NavigationLink {
                                    FeatureRequestDetailView(fr: fr)
                                        .gradientBG()
                                } label: {
                                    FeatureRequestCard(
                                        fr: fr,
                                        isLoggedIn: app.userId != nil,
                                        onVotedChanged: { await reload() }
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if app.userId != nil {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .padding(.trailing, 18)
                .padding(.bottom, 18)
                .safeAreaPadding(.bottom, 8)
                .accessibilityLabel("Add feature request")
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showCreate) {
            FeatureRequestCreateView(
                onCreated: {
                    showCreate = false
                    Task { @MainActor in
                        await reload()
                    }
                }
            )
            .gradientBG()
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("See what’s planned and vote on ideas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if app.userId == nil {
                Text("Log in to submit requests or vote.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 6)
    }
    
    @MainActor
    private func reload() async {
        loading = true
        error = nil
        defer { loading = false }

        do {
            let rows = try await FeatureRequestsAPI.fetchRequests()
            items = rows
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct FeatureRequestCard: View {
    @EnvironmentObject var app: AppState
    
    let fr: FeatureRequestRow
    let isLoggedIn: Bool
    let onVotedChanged: () async -> Void
    
    @State private var isVoting = false
    @State private var iVoted: Bool = false
    @State private var loadedVoteState = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18))
                )
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fr.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                
                Text(fr.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                
                HStack(spacing: 10) {
                    Label("\(fr.votes_count ?? 0)", systemImage: "hand.thumbsup")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Label("\(fr.comments_count ?? 0)", systemImage: "bubble.left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if isLoggedIn {
                        Button {
                            Task { await toggleVote() }
                        } label: {
                            HStack(spacing: 6) {
                                if isVoting { ProgressView().controlSize(.small) }
                                Image(systemName: iVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                                Text(iVoted ? "Voted" : "Upvote")
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isVoting || !loadedVoteState)
                    }
                }
            }
            .padding(12)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .task {
            await loadVoteStateIfNeeded()
        }
    }
    
    private func loadVoteStateIfNeeded() async {
        guard !loadedVoteState else { return }
        guard let uid = app.userId else {
            await MainActor.run {
                loadedVoteState = true
                iVoted = false
            }
            return
        }
        do {
            let voted = try await FeatureRequestsAPI.fetchMyVote(requestId: fr.id, userId: uid)
            await MainActor.run {
                self.iVoted = voted
                self.loadedVoteState = true
            }
        } catch {
            await MainActor.run {
                self.iVoted = false
                self.loadedVoteState = true
            }
        }
    }
    
    private func toggleVote() async {
        guard let uid = app.userId else { return }
        guard !isVoting else { return }
        await MainActor.run { isVoting = true }
        defer { Task { await MainActor.run { isVoting = false } } }
        
        do {
            if iVoted {
                try await FeatureRequestsAPI.unvote(requestId: fr.id, userId: uid)
                await MainActor.run { iVoted = false }
            } else {
                try await FeatureRequestsAPI.vote(requestId: fr.id, userId: uid)
                await MainActor.run { iVoted = true }
            }
            await onVotedChanged()
        } catch {
        }
    }
    
    @ViewBuilder
    private func statusPill(_ status: String) -> some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
            .foregroundStyle(.secondary)
    }
}
