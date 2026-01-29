import SwiftUI

struct AvatarMini: View {
    let urlString: String?

    var body: some View {
        ZStack {
            Circle().fill(.thinMaterial)

            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().scaleEffect(0.75)
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }
}
