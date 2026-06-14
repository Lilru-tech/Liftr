package com.lilru.liftr.ui.pets

object PetProfileGreetings {
    private val messages = listOf(
        "Who's a good profile owner? You are!",
        "Your furriend is proud of you!",
        "Have you admired me today?",
        "So... when are we going for a walk?",
        "Alert: maximum cuteness activated.",
        "We make a pawsome team!",
        "Don't forget to hydrate... and pet me."
    )

    fun randomOwnProfileMessage(): String = messages.random()
}
