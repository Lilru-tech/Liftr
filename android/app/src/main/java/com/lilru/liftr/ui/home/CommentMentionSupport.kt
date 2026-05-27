package com.lilru.liftr.ui.home

data class TrackedMention(
    val userId: String,
    val username: String
)

data class CommentFollowee(
    val userId: String,
    val username: String,
    val avatarUrl: String?
)

object CommentMentionSupport {
  private val mentionToken = Regex("""@([A-Za-z0-9_]+)""")

    fun activeMentionQuery(text: String, cursor: Int): String? {
        val safeCursor = cursor.coerceIn(0, text.length)
        val prefix = text.substring(0, safeCursor)
        val at = prefix.lastIndexOf('@')
        if (at < 0) return null
        val after = prefix.substring(at + 1)
        if (after.any { it.isWhitespace() }) return null
        return after
    }

    fun resolvedMentionIds(body: String, tracked: List<TrackedMention>): List<String> {
        val seen = mutableSetOf<String>()
        val out = mutableListOf<String>()
        for (m in tracked) {
            if (!body.contains("@${m.username}")) continue
            if (seen.add(m.userId)) out.add(m.userId)
        }
        return out
    }

    fun filterFollowees(followees: List<CommentFollowee>, query: String): List<CommentFollowee> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return followees
        return followees.filter { it.username.lowercase().contains(q) }
    }

    fun insertMentionToken(
        currentText: String,
        mentionQuery: String?,
        username: String
    ): String {
        val token = "@$username "
        val needle = "@" + (mentionQuery ?: "")
        if (!mentionQuery.isNullOrEmpty()) {
            val idx = currentText.lastIndexOf(needle)
            if (idx >= 0) {
                return currentText.substring(0, idx) + token + currentText.substring(idx + needle.length)
            }
        }
        return if (currentText.isEmpty()) token else currentText + token
    }

    fun mentionUsernamesInBody(body: String): List<String> =
        mentionToken.findAll(body).map { it.groupValues[1] }.distinct().toList()

    fun usernameToUserIdMap(
        followees: List<CommentFollowee>,
        comments: List<WorkoutCommentUi>
    ): Map<String, String> {
        val map = mutableMapOf<String, String>()
        followees.forEach { map[it.username] = it.userId }
        comments.forEach { c ->
            c.username?.let { map[it] = c.userId }
            c.replies.forEach { r ->
                r.username?.let { map[it] = r.userId }
            }
        }
        return map
    }
}
