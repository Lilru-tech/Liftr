package com.lilru.liftr.ui.pets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp

@Composable
fun PetMarketSkeleton(modifier: Modifier = Modifier) {
  val skeleton = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
  LazyColumn(
    modifier = modifier.padding(horizontal = 16.dp),
    verticalArrangement = Arrangement.spacedBy(16.dp)
  ) {
    item {
      Box(
        modifier = Modifier
          .fillMaxWidth()
          .height(52.dp)
          .clip(RoundedCornerShape(12.dp))
          .background(skeleton)
      )
    }
    items(2) {
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
          modifier = Modifier
            .width(120.dp)
            .height(20.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(skeleton)
        )
        LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
          items(4) {
            Surface(
              modifier = Modifier
                .width(100.dp)
                .height(160.dp),
              shape = RoundedCornerShape(12.dp),
              tonalElevation = 1.dp
            ) {
              Column(
                modifier = Modifier.padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
              ) {
                Box(
                  modifier = Modifier
                    .size(70.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(skeleton)
                )
                Box(
                  modifier = Modifier
                    .fillMaxWidth()
                    .height(12.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(skeleton)
                )
                Box(
                  modifier = Modifier
                    .width(50.dp)
                    .height(10.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(skeleton)
                )
              }
            }
          }
        }
      }
    }
  }
}
