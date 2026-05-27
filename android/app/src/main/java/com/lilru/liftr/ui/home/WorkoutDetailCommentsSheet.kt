package com.lilru.liftr.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.ClickableText
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R

@Composable
fun WorkoutDetailCommentsSheetContent(
    comments: List<WorkoutCommentUi>,
    commentDraft: TextFieldValue,
    onCommentDraftChange: (TextFieldValue) -> Unit,
    trackedMentions: List<TrackedMention>,
    onTrackedMentionsChange: (List<TrackedMention>) -> Unit,
    followees: List<CommentFollowee>,
    onRequestFollowees: () -> Unit,
    replyToCommentId: Int?,
    onCancelReply: () -> Unit,
    commentBusy: Boolean,
    onSendComment: () -> Unit,
    commentsCanLoadMore: Boolean,
    commentsLoadingMore: Boolean,
    onLoadMore: () -> Unit,
    onToggleLike: (Int) -> Unit,
    onReply: (Int) -> Unit,
    onDelete: (Int) -> Unit,
    onToggleReplies: (Int) -> Unit,
    onOpenProfile: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val mentionQuery = CommentMentionSupport.activeMentionQuery(
        commentDraft.text,
        commentDraft.selection.end
    )
    val showMentionPicker = mentionQuery != null
    val usernameToUserId = remember(comments, followees) {
        CommentMentionSupport.usernameToUserIdMap(followees, comments)
    }
    val filteredFollowees = remember(followees, mentionQuery) {
        CommentMentionSupport.filterFollowees(followees, mentionQuery ?: "")
    }

    if (showMentionPicker) {
        onRequestFollowees()
    }

    LazyColumn(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                stringResource(R.string.home_detail_comments_title),
                style = MaterialTheme.typography.titleMedium
            )
        }
        if (showMentionPicker) {
            item {
                MentionPicker(
                    followees = filteredFollowees,
                    onSelect = { followee ->
                        val tokenText = CommentMentionSupport.insertMentionToken(
                            currentText = commentDraft.text,
                            mentionQuery = mentionQuery,
                            username = followee.username
                        )
                        val updatedMentions = if (trackedMentions.any { it.userId == followee.userId }) {
                            trackedMentions
                        } else {
                            trackedMentions + TrackedMention(followee.userId, followee.username)
                        }
                        onTrackedMentionsChange(updatedMentions)
                        onCommentDraftChange(
                            TextFieldValue(
                                text = tokenText,
                                selection = androidx.compose.ui.text.TextRange(tokenText.length)
                            )
                        )
                    }
                )
            }
        }
        item {
            OutlinedTextField(
                value = commentDraft,
                onValueChange = onCommentDraftChange,
                label = {
                    Text(
                        if (replyToCommentId != null) {
                            stringResource(R.string.home_detail_comment_replying_to, replyToCommentId)
                        } else {
                            stringResource(R.string.home_detail_comment_hint)
                        }
                    )
                },
                modifier = Modifier.fillMaxWidth(),
                minLines = 1,
                maxLines = 4
            )
        }
        if (replyToCommentId != null) {
            item {
                OutlinedButton(onClick = onCancelReply) {
                    Text(stringResource(R.string.home_detail_comment_cancel_reply))
                }
            }
        }
        item {
            Button(
                onClick = onSendComment,
                enabled = !commentBusy && commentDraft.text.trim().isNotEmpty()
            ) {
                Text(
                    if (commentBusy) {
                        stringResource(R.string.home_detail_comment_sending)
                    } else {
                        stringResource(R.string.home_detail_comment_send)
                    }
                )
            }
        }
        if (comments.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.home_detail_comments_empty),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        } else {
            items(comments, key = { it.id }) { c ->
                CommentCard(
                    comment = c,
                    usernameToUserId = usernameToUserId,
                    onToggleLike = { onToggleLike(c.id) },
                    onReply = { onReply(c.id) },
                    onDelete = { onDelete(c.id) },
                    onToggleReplies = { onToggleReplies(c.id) },
                    onOpenProfile = { onOpenProfile(c.userId) },
                    onOpenMentionProfile = onOpenProfile,
                    modifier = Modifier.fillMaxWidth()
                )
                if (c.isExpanded && c.replies.isNotEmpty()) {
                    c.replies.forEach { reply ->
                        CommentCard(
                            comment = reply,
                            usernameToUserId = usernameToUserId,
                            onToggleLike = { onToggleLike(reply.id) },
                            onReply = { onReply(c.id) },
                            onDelete = { onDelete(reply.id) },
                            onToggleReplies = {},
                            onOpenProfile = { onOpenProfile(reply.userId) },
                            onOpenMentionProfile = onOpenProfile,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 20.dp)
                        )
                    }
                }
            }
            if (commentsCanLoadMore && comments.isNotEmpty()) {
                item {
                    OutlinedButton(
                        onClick = onLoadMore,
                        enabled = !commentsLoadingMore,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                    ) {
                        if (commentsLoadingMore) {
                            Text(stringResource(R.string.home_detail_comments_loading_more))
                        } else {
                            Text(stringResource(R.string.home_detail_comments_load_more))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MentionPicker(
    followees: List<CommentFollowee>,
    onSelect: (CommentFollowee) -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 180.dp)
                .padding(vertical = 4.dp)
        ) {
            if (followees.isEmpty()) {
                Text(
                    text = stringResource(R.string.home_detail_comment_mention_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(12.dp)
                )
            } else {
                followees.forEach { followee ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(followee) }
                            .padding(horizontal = 12.dp, vertical = 10.dp)
                    ) {
                        Text(
                            text = "@${followee.username}",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun CommentCard(
    comment: WorkoutCommentUi,
    usernameToUserId: Map<String, String>,
    onToggleLike: () -> Unit,
    onReply: () -> Unit,
    onDelete: () -> Unit,
    onToggleReplies: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenMentionProfile: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(modifier = modifier) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = comment.username?.takeIf { it.isNotBlank() } ?: comment.userId,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.clickable(onClick = onOpenProfile)
            )
            CommentBodyText(
                body = comment.body,
                usernameToUserId = usernameToUserId,
                onOpenMentionProfile = onOpenMentionProfile
            )
            Text(
                text = comment.createdAt?.substringBefore("T") ?: "-",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onToggleLike) {
                    val label = if (comment.likedByMe) {
                        stringResource(R.string.home_detail_unlike)
                    } else {
                        stringResource(R.string.home_detail_like)
                    }
                    Text("$label (${comment.likesCount})")
                }
                OutlinedButton(onClick = onReply) {
                    Text(stringResource(R.string.home_detail_comment_reply))
                }
                if (comment.canDelete) {
                    OutlinedButton(onClick = onDelete) {
                        Text(stringResource(R.string.home_detail_comment_delete))
                    }
                }
                if (comment.repliesCount > 0) {
                    OutlinedButton(onClick = onToggleReplies) {
                        Text(
                            if (comment.isExpanded) {
                                stringResource(R.string.home_detail_comment_hide_replies)
                            } else {
                                stringResource(R.string.home_detail_comment_view_replies, comment.repliesCount)
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CommentBodyText(
    body: String,
    usernameToUserId: Map<String, String>,
    onOpenMentionProfile: (String) -> Unit
) {
    val mentionColor = MaterialTheme.colorScheme.primary
    val annotated = remember(body, usernameToUserId, mentionColor) {
        buildAnnotatedString {
            var index = 0
            while (index < body.length) {
                val at = body.indexOf('@', index)
                if (at < 0) {
                    append(body.substring(index))
                    break
                }
                if (at > index) {
                    append(body.substring(index, at))
                }
                var end = at + 1
                while (end < body.length) {
                    val ch = body[end]
                    if (ch.isWhitespace()) break
                    if (!ch.isLetterOrDigit() && ch != '_') break
                    end++
                }
                if (end > at + 1) {
                    val token = body.substring(at, end)
                    val username = token.drop(1)
                    val userId = usernameToUserId[username]
                    if (userId != null) {
                        pushStringAnnotation(tag = "mention", annotation = userId)
                        withStyle(SpanStyle(color = mentionColor, fontWeight = FontWeight.SemiBold)) {
                            append(token)
                        }
                        pop()
                    } else {
                        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
                            append(token)
                        }
                    }
                    index = end
                } else {
                    append('@')
                    index = at + 1
                }
            }
        }
    }
    ClickableText(
        text = annotated,
        style = MaterialTheme.typography.bodyMedium,
        onClick = { offset ->
            annotated.getStringAnnotations(tag = "mention", start = offset, end = offset)
                .firstOrNull()
                ?.let { onOpenMentionProfile(it.item) }
        }
    )
}
