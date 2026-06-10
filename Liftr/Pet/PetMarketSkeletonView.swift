import SwiftUI

struct PetMarketSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 52)
                    .padding(.horizontal)
                    .padding(.top)

                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 120, height: 20)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(0..<4, id: \.self) { _ in
                                    VStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(width: 70, height: 70)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(width: 80, height: 12)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(width: 50, height: 10)
                                    }
                                    .frame(width: 100, height: 160)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }
}
