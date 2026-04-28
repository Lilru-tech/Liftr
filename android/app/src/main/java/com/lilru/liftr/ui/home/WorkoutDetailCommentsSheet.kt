package com.lilru.liftr.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R

@Composable
fun WorkoutDetailCommentsSheetContent(
    comments: List<WorkoutCommentUi>,
    commentDraft: String,
    onCommentDraftChange: (String) -> Unit,
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
                enabled = !commentBusy && commentDraft.trim().isNotEmpty()
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
                    onToggleLike = { onToggleLike(c.id) },
                    onReply = { onReply(c.id) },
                    onDelete = { onDelete(c.id) },
                    onToggleReplies = { onToggleReplies(c.id) },
                    onOpenProfile = { onOpenProfile(c.userId) },
                    modifier = Modifier.fillMaxWidth()
                )
                if (c.isExpanded && c.replies.isNotEmpty()) {
                    c.replies.forEach { reply ->
                        CommentCard(
                            comment = reply,
                            onToggleLike = { onToggleLike(reply.id) },
                            onReply = { onReply(c.id) },
                            onDelete = { onDelete(reply.id) },
                            onToggleReplies = {},
                            onOpenProfile = { onOpenProfile(reply.userId) },
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
fun CommentCard(
    comment: WorkoutCommentUi,
    onToggleLike: () -> Unit,
    onReply: () -> Unit,
    onDelete: () -> Unit,
    onToggleReplies: () -> Unit,
    onOpenProfile: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(modifier = modifier) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = comment.username?.takeIf { it.isNotBlank() } ?: comment.userId,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.clickable(onClick = onOpenProfile)
            )
            Text(
                text = comment.body,
                style = MaterialTheme.typography.bodyMedium
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
