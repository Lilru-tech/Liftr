import Foundation

struct StrengthFinishIncompleteCounts: Equatable {
    let exercises: Int
    let sets: Int

    static let zero = StrengthFinishIncompleteCounts(exercises: 0, sets: 0)

    static func aggregate(_ parts: [StrengthFinishIncompleteCounts]) -> StrengthFinishIncompleteCounts {
        StrengthFinishIncompleteCounts(
            exercises: parts.reduce(0) { $0 + $1.exercises },
            sets: parts.reduce(0) { $0 + $1.sets }
        )
    }
}

enum StrengthFinishIncompleteCounting {
    static func counts<E>(
        exercises: [E],
        totalSets: (E) -> Int,
        completedSetIndex: (E) -> Int
    ) -> StrengthFinishIncompleteCounts {
        var incompleteSets = 0
        var incompleteExercises = 0
        for ex in exercises {
            let total = totalSets(ex)
            guard total > 0 else { continue }
            let done = min(max(0, completedSetIndex(ex)), total)
            let remaining = total - done
            incompleteSets += remaining
            if done == 0 {
                incompleteExercises += 1
            }
        }
        return StrengthFinishIncompleteCounts(exercises: incompleteExercises, sets: incompleteSets)
    }
}

enum StrengthFinishConfirmationCopy {
    static func incompleteWarning(exercises: Int, sets: Int) -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        if lang == "es" {
            return "Tienes \(exercises) ejercicios y \(sets) series sin terminar. Si finalizas el entrenamiento ahora, se eliminarán automáticamente de tu historial."
        }
        return "You have \(exercises) exercises and \(sets) sets left unfinished. If you finish now, they will be removed from your history automatically."
    }

    static var standardEarlyFinishBody: String {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        if lang == "es" {
            return "No has completado todas las series planificadas. El entrenamiento se guardará solo con las series que hayas hecho. Si finalizas ahora, se publicará automáticamente."
        }
        return "You haven't completed all planned sets. The workout will be saved with only the sets you actually performed. If you finish now, it will be published automatically."
    }

    static func message(
        incomplete: StrengthFinishIncompleteCounts,
        standardBody: String,
        dualPartnerNote: String? = nil
    ) -> String {
        var parts: [String] = []
        if incomplete.exercises > 0, incomplete.sets > 0 {
            parts.append(incompleteWarning(exercises: incomplete.exercises, sets: incomplete.sets))
        }
        parts.append(standardBody)
        if let dualPartnerNote, !dualPartnerNote.isEmpty {
            parts.append(dualPartnerNote)
        }
        return parts.joined(separator: "\n\n")
    }
}
