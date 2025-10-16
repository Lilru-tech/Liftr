import SwiftUI

struct CustomTabBar: View {
  @Binding var selected: Tab
  let isAuthenticated: Bool
  var onPlus: () -> Void
  var onRequireAuth: () -> Void   // qué hacer si NO hay sesión

  var body: some View {
    HStack(spacing: 22) {
      TabButton(icon: "house.fill", label: "Home", isSelected: selected == .home) { selected = .home }
      TabButton(icon: "magnifyingglass", label: "Search", isSelected: selected == .search) { selected = .search }

      Button(action: { isAuthenticated ? onPlus() : onRequireAuth() }) {
        Image(systemName: "plus.circle.fill")
          .font(.system(size: 44, weight: .bold))
          .shadow(radius: 4)
          .accessibilityLabel(isAuthenticated ? "Add workout" : "Login required")
      }
      .padding(.horizontal, 4)
      .opacity(isAuthenticated ? 1 : 0.55)  // visual de “deshabilitado”

      TabButton(icon: "trophy.fill", label: "Ranking", isSelected: selected == .ranking) { selected = .ranking }
      TabButton(icon: "person.crop.circle", label: "Profile", isSelected: selected == .profile) { selected = .profile }
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(Color(.systemGray6).opacity(0.9))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    )
    .padding(.horizontal, 24)
  }
}

private struct TabButton: View {
  let icon: String
  let label: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: icon).font(.system(size: 20, weight: .semibold))
        Text(label).font(.caption2)
      }
      .foregroundStyle(isSelected ? Color.primary : Color.secondary)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity)
    }
  }
}
