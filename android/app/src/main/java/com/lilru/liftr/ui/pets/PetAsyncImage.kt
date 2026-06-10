package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import com.lilru.liftr.data.PetInstanceWire
import com.lilru.liftr.data.PetService

@Composable
fun PetAsyncImage(
    pet: PetInstanceWire,
    modifier: Modifier = Modifier,
    size: Dp = 120.dp,
    contentPadding: Dp = 0.dp
) {
    val urls = remember(pet.id, pet.imageUrl, pet.petType, pet.evolutionStage) {
        PetService.resolvedImageUrls(pet)
    }
    var index by remember(pet.id, pet.imageUrl, pet.petType, pet.evolutionStage) {
        mutableIntStateOf(0)
    }
    val model = urls.getOrNull(index)

    Box(
        modifier = modifier.size(size),
        contentAlignment = Alignment.Center
    ) {
        if (model == null) return@Box

        SubcomposeAsyncImage(
            model = model,
            contentDescription = null,
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
            contentScale = ContentScale.Fit,
            loading = {
                CircularProgressIndicator(modifier = Modifier.size(24.dp))
            },
            error = {
                if (index + 1 < urls.size) {
                    index += 1
                }
            }
        )
    }
}
