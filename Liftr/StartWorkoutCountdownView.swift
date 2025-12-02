import SwiftUI

struct StartWorkoutCountdownView: View {
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var counter: Int = 3
    @State private var showStartText = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text(showStartText ? "Start!" : "\(counter)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .transition(.scale.combined(with: .opacity))
            
            Text(showStartText ? "Go crush this workout 💪" : "Get ready…")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            
            Spacer()
        
        }
        .padding(.horizontal, 24)
        .onAppear {
            startCountdown()
        }
    }
    
    private func startCountdown() {
        counter = 3
        showStartText = false
        tick()
    }
    
    private func tick() {
        guard counter > 0 else {
            withAnimation(.spring()) {
                showStartText = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                onFinished()
            }
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.easeInOut) {
                counter -= 1
            }
            tick()
        }
    }
}
