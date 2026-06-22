import SwiftUI

struct ClimbingSessionEditor: View {
    @Binding var sport: SportForm

    var body: some View {
        Divider()
        FieldRowPlain {
            Picker("", selection: $sport.clEnvironment) {
                ForEach(ClimbingEnvironment.allCases) { env in
                    Text(env.label).tag(env)
                }
            }
            .pickerStyle(.segmented)
        }

        Divider().padding(.vertical, 6)
        FieldRowPlain {
            Picker("", selection: $sport.clPrimaryStyle) {
                ForEach(ClimbingStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.menu)
        }

        Divider().padding(.vertical, 6)
        WorkoutMetricFieldsRow {
            workoutMetricField("Routes sent", text: $sport.clRoutesSent, keyboard: .numberPad)
            workoutMetricField("Attempts", text: $sport.clRoutesAttempted, keyboard: .numberPad)
        }

        Divider().padding(.vertical, 6)
        WorkoutMetricFieldsRow {
            workoutMetricField("Vertical m", text: $sport.clTotalVerticalM, keyboard: .numberPad)
            workoutMetricField("Flashes", text: $sport.clFlashes, keyboard: .numberPad)
            workoutMetricField("Falls", text: $sport.clFalls, keyboard: .numberPad)
        }

        Divider().padding(.vertical, 6)
        WorkoutMetricFieldsRow {
            workoutMetricField("Move s", text: $sport.clMovingTimeSec, keyboard: .numberPad)
            workoutMetricField("Pause s", text: $sport.clPausedTimeSec, keyboard: .numberPad)
        }

        Divider().padding(.vertical, 6)
        WorkoutMetricFieldsRow {
            workoutMetricField("Venue", text: $sport.clVenueName, keyboard: .default)
        }

        if sport.clEnvironment == .outdoor {
            Divider().padding(.vertical, 6)
            WorkoutMetricFieldsRow {
                workoutMetricField("Weather", text: $sport.clWeather, keyboard: .default)
            }
        }

        Divider().padding(.vertical, 6)
        WorkoutMetricFieldsRow {
            workoutMetricField("Avg HR", text: $sport.clAvgHR, keyboard: .numberPad)
            workoutMetricField("Max HR", text: $sport.clMaxHR, keyboard: .numberPad)
        }

        Divider().padding(.vertical, 6)
        FieldRowPlain {
            Picker("", selection: $sport.clHighestGradeSystem) {
                ForEach(ClimbingGradeSystem.allCases) { sys in
                    Text(sys.label).tag(sys)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: sport.clHighestGradeSystem) { _, newSystem in
                sport.clHighestGradeValue = ClimbingRouteFormatting.sanitizeGradeValue(
                    sport.clHighestGradeValue,
                    for: newSystem
                )
            }
        }
        Divider().padding(.vertical, 6)
        FieldRowPlain {
            Picker("", selection: $sport.clHighestGradeValue) {
                Text("—").tag("")
                ForEach(ClimbingGradeSystem.grades(for: sport.clHighestGradeSystem), id: \.self) { grade in
                    Text(grade).tag(grade)
                }
            }
            .pickerStyle(.menu)
        }

        Divider().padding(.vertical, 6)
        HStack {
            Text("Routes")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Add route") {
                sport.clRoutes.append(ClimbingRouteForm(style: sport.clPrimaryStyle, gradeSystem: defaultGradeSystem(for: sport.clPrimaryStyle)))
            }
            .font(.subheadline)
        }

        ForEach($sport.clRoutes) { $route in
            climbingRouteCard(route: $route) {
                sport.clRoutes.removeAll { $0.id == route.id }
                ClimbingRouteFormatting.syncSessionSummary(from: sport.clRoutes, into: &sport)
            }
        }
        .onChange(of: sport.clRoutes) { _, _ in
            ClimbingRouteFormatting.syncSessionSummary(from: sport.clRoutes, into: &sport)
        }
    }

    @ViewBuilder
    private func climbingRouteCard(route: Binding<ClimbingRouteForm>, onDelete: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Route name", text: route.routeName)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
            Picker("Style", selection: route.style) {
                ForEach(ClimbingStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.menu)
            Picker("Grade system", selection: route.gradeSystem) {
                ForEach(ClimbingGradeSystem.allCases) { sys in
                    Text(sys.label).tag(sys)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: route.wrappedValue.gradeSystem) { _, newSystem in
                route.wrappedValue.gradeValue = ClimbingRouteFormatting.sanitizeGradeValue(
                    route.wrappedValue.gradeValue,
                    for: newSystem
                )
            }
            Picker("Grade", selection: route.gradeValue) {
                Text("—").tag("")
                ForEach(ClimbingGradeSystem.grades(for: route.wrappedValue.gradeSystem), id: \.self) { grade in
                    Text(grade).tag(grade)
                }
            }
            .pickerStyle(.menu)
            HStack {
                TextField("Attempts", text: route.attempts)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Toggle("Sent", isOn: route.sent)
                Toggle("Flash", isOn: route.flash)
            }
        }
        .padding(.vertical, 8)
        Divider()
    }

    private func defaultGradeSystem(for style: ClimbingStyle) -> ClimbingGradeSystem {
        switch style {
        case .boulder: return .v_scale
        case .top_rope, .lead, .trad, .mixed: return .french
        }
    }
}
