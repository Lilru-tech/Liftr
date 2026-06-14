import SwiftUI

struct MarketItemImage: View {
    let url: URL?
    var size: CGFloat = 88
    var modalHeight: CGFloat? = nil

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(width: size, height: displayHeight)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: modalHeight == nil ? size : nil, height: displayHeight)
                    .frame(maxWidth: modalHeight == nil ? size : .infinity)
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: min(displayHeight * 0.45, 48)))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: displayHeight)
            @unknown default:
                EmptyView()
            }
        }
        .id(url?.absoluteString ?? "missing")
    }

    private var displayHeight: CGFloat {
        modalHeight ?? size
    }
}
