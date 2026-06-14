import Foundation

enum PetProfileGreetings {
    static func randomOwnProfileMessage() -> String {
        [
            "Who's a good profile owner? You are!",
            "Your furriend is proud of you!",
            "Have you admired me today?",
            "So... when are we going for a walk?",
            "Alert: maximum cuteness activated.",
            "We make a pawsome team!",
            "Don't forget to hydrate... and pet me."
        ].randomElement() ?? "Your pet is watching."
    }
}
