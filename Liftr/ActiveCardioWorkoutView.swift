import SwiftUI
import Supabase

struct ActiveCardioWorkoutView: View {
    let workoutId: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @State private var showCountdown = true
    @State private var isRunning = false
    @State private var elapsedSec: Int = 0
    @State private var isSaving = false
    @State private var error: String?
    @State private var cardio: CardioRow?
    @State private var remainingSec: Int = 0
    @State private var initialTargetSec: Int = 0
    @State private var distanceText: String = ""
    @State private var hasTargetTime: Bool = false
    @State private var mode: TimerMode = .stopwatch
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private struct CardioRow: Decodable {
        let id: Int
        let activity_code: String?
        let modality: String?
        let distance_km: Decimal?
        let duration_sec: Int?
    }
    
    private enum TimerMode {
        case stopwatch
        case countdown
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .gradientBG()
                
                VStack(spacing: 24) {
                    if let c = cardio {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(activityLabel(c))
                                .font(.title2.weight(.bold))
                            HStack(spacing: 10) {
                                if let d = c.distance_km {
                                    Text(String(format: "Target %.2f km",
                                                NSDecimalNumber(decimal: d).doubleValue))
                                }
                                if let target = c.duration_sec, target > 0 {
                                    Text("• \(formatTime(target))")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Active cardio workout")
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if hasTargetTime {
                        Picker("", selection: $mode) {
                            Text("Target time").tag(TimerMode.countdown)
                            Text("Free timer").tag(TimerMode.stopwatch)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(spacing: 8) {
                        Text(formatTime(mode == .countdown && hasTargetTime ? remainingSec : elapsedSec))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(mode == .countdown && hasTargetTime ? "Time left" : "Elapsed time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15)))
                    
                    if cardio != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Actual distance")
                                .font(.subheadline.weight(.semibold))
                            TextField("Distance (km)", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                    }
                    
                    HStack(spacing: 16) {
                        Button {
                            if isRunning {
                                isRunning = false
                            } else {
                                isRunning = true
                            }
                        } label: {
                            Text(isRunning
                                 ? "Pause"
                                 : (elapsedSec == 0 ? "Start" : "Resume"))
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.accentColor)
                                )
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            elapsedSec = 0
                            isRunning = false
                            if mode == .countdown && hasTargetTime {
                                remainingSec = initialTargetSec
                            }
                        } label: {
                            Text("Reset")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 100, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.secondary, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning || elapsedSec == 0)
                    }
                    
                    Button {
                        Task {
                            await saveAndFinishWorkout()
                        }
                    } label: {
                        Text("Finish workout")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.green.gradient)
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || elapsedSec == 0)
                    
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                }
                .padding(16)
                
                if isSaving {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Saving workout…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                
                if showCountdown {
                    StartWorkoutCountdownView {
                        withAnimation(.easeInOut) {
                            showCountdown = false
                            isRunning = true
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                }
            }
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onReceive(timer) { _ in
            guard isRunning else { return }
            
            if mode == .countdown && hasTargetTime {
                if remainingSec > 0 {
                    remainingSec -= 1
                    elapsedSec += 1
                } else {
                    isRunning = false
                }
            } else {
                elapsedSec += 1
            }
        }
        .task {
            await loadCardio()
        }
    }
    
    private func loadCardio() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("cardio_sessions")
                .select("id, activity_code, modality, distance_km, duration_sec")
                .eq("workout_id", value: workoutId)
                .single()
                .execute()
            
            let row = try JSONDecoder.supabase().decode(CardioRow.self, from: res.data)
            await MainActor.run {
                self.cardio = row

                if let dur = row.duration_sec, dur > 0 {
                    self.hasTargetTime = true
                    self.initialTargetSec = dur
                    self.remainingSec = dur
                    self.elapsedSec = 0
                    self.mode = .countdown
                } else {
                    self.hasTargetTime = false
                    self.initialTargetSec = 0
                    self.remainingSec = 0
                    self.elapsedSec = 0
                    self.mode = .stopwatch
                }

                if let d = row.distance_km {
                    self.distanceText = String(
                        format: "%.2f",
                        NSDecimalNumber(decimal: d).doubleValue
                    )
                } else {
                    self.distanceText = ""
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func saveAndFinishWorkout() async {
        await MainActor.run {
            isSaving = true
            isRunning = false
        }
        
        do {
            struct UpdatePayload: Encodable {
                let duration_sec: Int
                let distance_km: Decimal?
            }

            let trimmed = distanceText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")

            let distanceDecimal: Decimal?
            if trimmed.isEmpty {
                distanceDecimal = nil
            } else {
                distanceDecimal = Decimal(string: trimmed)
            }
            
            _ = try await SupabaseManager.shared.client
                .from("cardio_sessions")
                .update(
                    UpdatePayload(
                        duration_sec: elapsedSec,
                        distance_km: distanceDecimal
                    )
                )
                .eq("workout_id", value: workoutId)
                .execute()
            
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                self.error = error.localizedDescription
            }
        }
    }
    
    private func formatTime(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
    
    private func activityLabel(_ r: CardioRow) -> String {
        let code = (r.activity_code ?? r.modality ?? "cardio")
        return code.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
