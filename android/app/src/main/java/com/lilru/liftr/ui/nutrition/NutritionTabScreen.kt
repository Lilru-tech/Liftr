package com.lilru.liftr.ui.nutrition

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.lilru.liftr.nutrition.NutritionLabelOCR
import com.lilru.liftr.nutrition.NutritionLabelParser
import com.lilru.liftr.ui.AppSnackbar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.chat.ShareIngredientToChatSheetContent
import com.lilru.liftr.ui.chat.ShareRecipeToChatSheetContent
import com.lilru.liftr.ui.chat.SharedIngredientSnapshot
import com.lilru.liftr.ui.chat.SharedRecipeIngredientSnapshot
import com.lilru.liftr.ui.chat.SharedRecipeProfilePer100gSnapshot
import com.lilru.liftr.ui.chat.SharedRecipeSnapshot
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradientOpaque
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NutritionTabScreen(
    supabase: SupabaseClient,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val vm: NutritionViewModel = viewModel(factory = NutritionViewModelFactory(supabase))
    val ui by vm.uiState.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { newValue ->
        if (newValue == SheetValue.Hidden && ui.addFoodHasSelection) false else true
    })
    var showInsightsHub by rememberSaveable { mutableStateOf(false) }

    if (showInsightsHub) {
        NutritionInsightsHubScreen(
            vm = vm,
            onBack = { showInsightsHub = false },
            modifier = modifier
        )
        return
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        floatingActionButton = {
            IconButton(onClick = { vm.openAddFood() }) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.nutrition_add_food))
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                NutritionCalendarCard(
                    month = ui.month,
                    selectedDate = ui.selectedDate,
                    dayBalance = ui.monthDayBalance,
                    onPrevMonth = { vm.shiftMonth(-1) },
                    onNextMonth = { vm.shiftMonth(1) },
                    onToday = { vm.goToday() },
                    onSelectDay = { vm.setSelectedDate(it) }
                )
            }
            item { NutritionSummaryCard(ui = ui, vm = vm) }
            if (ui.error != null) {
                item {
                    Text(ui.error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
            item {
                Text(
                    ui.selectedDate.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
            vm.mealSlotOrder.forEach { slot ->
                item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text(slot, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        IconButton(onClick = { vm.openAddFood(mealSlot = slot) }) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                        }
                    }
                }
                val mealItems = ui.diaryByMeal[slot].orEmpty()
                if (mealItems.isEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.nutrition_meal_empty),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    items(mealItems, key = { it.id }) { row ->
                        NutritionDiaryRowCard(row = row, onClick = { vm.setOverlay(NutritionOverlay.EditLog(row)) })
                    }
                }
            }
            item {
                NutritionInsightsEntryCard(onClick = { showInsightsHub = true })
            }
        }
    }

    if (ui.overlay !is NutritionOverlay.None) {
        val sheetTheme = remember { LiftrPreferences.backgroundTheme(context) }
        ModalBottomSheet(onDismissRequest = { vm.dismissOverlay() }, sheetState = sheetState) {
            Box(Modifier.liftrAppBackgroundGradientOpaque(sheetTheme)) {
                when (val overlay = ui.overlay) {
                    NutritionOverlay.AddFood -> NutritionLogFoodSheet(supabase, ui, vm)
                    NutritionOverlay.CreateIngredient -> NutritionIngredientEditorSheet(ui, vm, isEdit = false)
                    NutritionOverlay.CreateRecipe -> NutritionCreateRecipeSheet(ui, vm)
                    is NutritionOverlay.EditLog -> NutritionEditLogSheet(ui, vm, overlay.item)
                    NutritionOverlay.None -> Unit
                }
            }
        }
    }
}

@Composable
private fun NutritionMaterialField(value: String, onValueChange: (String) -> Unit, label: String, modifier: Modifier = Modifier) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true,
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        )
    )
}

@Composable
private fun NutritionGramsPicker(grams: Double, onChange: (Double) -> Unit, kcalPreview: Int?) {
    var gramsText by remember(grams) { mutableStateOf(grams.roundToInt().toString()) }
    LaunchedEffect(grams) {
        val t = grams.roundToInt().toString()
        if (gramsText != t) gramsText = t
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(stringResource(R.string.nutrition_grams), fontWeight = FontWeight.SemiBold)
                if (kcalPreview != null) {
                    Text(stringResource(R.string.nutrition_kcal_format, kcalPreview), color = MaterialTheme.colorScheme.primary)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { onChange((grams - 5).coerceAtLeast(5.0)) }) { Text("−") }
                OutlinedTextField(
                    value = gramsText,
                    onValueChange = { raw ->
                        val filtered = raw.filter { it.isDigit() }
                        gramsText = filtered
                        filtered.toDoubleOrNull()?.let { onChange(it.coerceIn(5.0, 2000.0)) }
                    },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    label = { Text("g") }
                )
                IconButton(onClick = { onChange((grams + 5).coerceAtMost(2000.0)) }) { Text("+") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(50.0, 100.0, 150.0, 200.0, 250.0).forEach { p ->
                    FilterChip(selected = grams == p, onClick = { onChange(p) }, label = { Text("${p.toInt()} g") })
                }
            }
        }
    }
}

@Composable
private fun NutritionSummaryCard(ui: NutritionUiState, vm: NutritionViewModel) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.nutrition_daily_balance), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (ui.loading && ui.recommendation == null) {
                CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
            } else if (ui.recommendation != null) {
                val rec = ui.recommendation!!
                NutritionMacroDashboard(recommendation = rec)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.nutrition_target_base), style = MaterialTheme.typography.labelSmall)
                        Text(stringResource(R.string.nutrition_kcal_format, rec.baseCaloriesTarget.roundToInt()), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    }
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.nutrition_activity_burned), style = MaterialTheme.typography.labelSmall)
                        Text(stringResource(R.string.nutrition_kcal_format, rec.burned.roundToInt()), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    }
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.nutrition_consumed), style = MaterialTheme.typography.labelSmall)
                        Text(stringResource(R.string.nutrition_kcal_format, rec.consumed.roundToInt()), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    }
                }
                NutritionCalorieBudgetStatusRow(remainingKcal = rec.remaining)
                NutritionMicroNutrientsSection(
                    recommendation = rec,
                    expanded = ui.microExpanded,
                    onToggle = { vm.toggleMicroExpanded() }
                )
            } else {
                Text(stringResource(R.string.nutrition_summary_empty), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NutritionDiaryRowCard(row: NutritionDiaryItemUi, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.38f))
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(row.name, fontWeight = FontWeight.Medium)
            Text(
                stringResource(R.string.nutrition_row_subtitle, row.quantityG.roundToInt(), row.caloriesKcal.roundToInt()),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NutritionLogFoodSheet(supabase: SupabaseClient, ui: NutritionUiState, vm: NutritionViewModel) {
    val hasSelection = ui.selectedIngredientId != null || ui.selectedRecipeId != null
    val selectedIngredient = ui.ingredientResults.find { it.id == ui.selectedIngredientId }
    val selectedRecipe = ui.recipeResults.find { it.id == ui.selectedRecipeId }
    val currentUserId = remember(supabase) { supabase.auth.currentUserOrNull()?.id }
    val canManageSelectedRecipe = selectedRecipe != null &&
        currentUserId != null &&
        selectedRecipe.userId == currentUserId
    val canManageSelectedIngredient = selectedIngredient != null &&
        currentUserId != null &&
        selectedIngredient.userId == currentUserId
    var showDeleteRecipeConfirm by remember { mutableStateOf(false) }
    var showDeleteIngredientConfirm by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val panelTheme = remember(context) { LiftrPreferences.backgroundTheme(context) }
    val panelBottomPadding = if (hasSelection) 380.dp else 16.dp
    var shareIngredientSnap by remember { mutableStateOf<SharedIngredientSnapshot?>(null) }
    var shareRecipeSnap by remember { mutableStateOf<SharedRecipeSnapshot?>(null) }
    val shareSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            contentPadding = PaddingValues(bottom = panelBottomPadding),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text(stringResource(R.string.nutrition_add_food), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { vm.setLogFoodNestedOverlay(NutritionLogNestedOverlay.CreateIngredient) }) {
                        Text(stringResource(R.string.nutrition_new_ingredient))
                    }
                    TextButton(onClick = { vm.setLogFoodNestedOverlay(NutritionLogNestedOverlay.CreateRecipe) }) {
                        Text(stringResource(R.string.nutrition_new_recipe))
                    }
                }
            }
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SegmentedButton(selected = ui.addModeIngredient, onClick = { vm.setAddModeIngredient(true) }, shape = SegmentedButtonDefaults.itemShape(0, 2)) {
                        Text(stringResource(R.string.nutrition_mode_ingredient))
                    }
                    SegmentedButton(selected = !ui.addModeIngredient, onClick = { vm.setAddModeIngredient(false) }, shape = SegmentedButtonDefaults.itemShape(1, 2)) {
                        Text(stringResource(R.string.nutrition_mode_recipe))
                    }
                }
            }
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = ui.addListScope == NutritionListScope.ALL,
                        onClick = { vm.setAddListScope(NutritionListScope.ALL) },
                        shape = SegmentedButtonDefaults.itemShape(0, 3)
                    ) { Text(stringResource(R.string.nutrition_scope_all)) }
                    SegmentedButton(
                        selected = ui.addListScope == NutritionListScope.MINE,
                        onClick = { vm.setAddListScope(NutritionListScope.MINE) },
                        shape = SegmentedButtonDefaults.itemShape(1, 3)
                    ) { Text(stringResource(R.string.nutrition_scope_mine)) }
                    SegmentedButton(
                        selected = ui.addListScope == NutritionListScope.FAVORITES,
                        onClick = { vm.setAddListScope(NutritionListScope.FAVORITES) },
                        shape = SegmentedButtonDefaults.itemShape(2, 3)
                    ) { Text(stringResource(R.string.nutrition_scope_favorites)) }
                }
            }
            item {
                NutritionMaterialField(ui.addSearchQuery, vm::setAddSearchQuery, stringResource(R.string.nutrition_search))
            }
            if (ui.searchLoading) {
                item { CircularProgressIndicator() }
            }
            if (ui.addModeIngredient) {
                itemsIndexed(
                    ui.ingredientResults,
                    key = { _, row -> row.id }
                ) { index, row ->
                    val sel = ui.selectedIngredientId == row.id
                    val isFav = ui.favoriteIngredientIds.contains(row.id)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(
                            onClick = { vm.selectIngredient(row.id) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Column(Modifier.fillMaxWidth()) {
                                Text(row.name, fontWeight = if (sel) FontWeight.Bold else FontWeight.Normal)
                                Text(stringResource(R.string.nutrition_ingredient_kcal_per_100g, row.caloriesPer100g.roundToInt()))
                            }
                        }
                        IconButton(onClick = { vm.toggleFavoriteIngredient(row.id) }) {
                            Icon(
                                imageVector = if (isFav) Icons.Filled.Star else Icons.Outlined.Star,
                                contentDescription = stringResource(R.string.nutrition_favorite_content_description),
                                tint = if (isFav) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (index >= ui.ingredientResults.size - 5) {
                        LaunchedEffect(ui.ingredientResults.size, ui.ingredientCanLoadMore) {
                            vm.loadMoreAddCatalogIngredients()
                        }
                    }
                }
                if (ui.ingredientLoadingMore) {
                    item {
                        CircularProgressIndicator(Modifier.padding(vertical = 8.dp))
                    }
                }
            } else {
                items(ui.recipeResults, key = { it.id }) { row ->
                    val sel = ui.selectedRecipeId == row.id
                    val isFav = ui.favoriteRecipeIds.contains(row.id)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(
                            onClick = { vm.selectRecipe(row.id) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(row.name, fontWeight = if (sel) FontWeight.Bold else FontWeight.Normal)
                        }
                        IconButton(onClick = { vm.toggleFavoriteRecipe(row.id) }) {
                            Icon(
                                imageVector = if (isFav) Icons.Filled.Star else Icons.Outlined.Star,
                                contentDescription = stringResource(R.string.nutrition_favorite_content_description),
                                tint = if (isFav) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
                if (!ui.searchLoading && ui.recipeResults.isEmpty()) {
                    item {
                        val hint = when (ui.addListScope) {
                            NutritionListScope.MINE -> stringResource(R.string.nutrition_mine_recipes_empty)
                            NutritionListScope.FAVORITES -> stringResource(R.string.nutrition_favorites_recipes_empty)
                            NutritionListScope.ALL -> stringResource(R.string.nutrition_recipes_empty)
                        }
                        Text(hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (!ui.searchLoading && ui.addModeIngredient && ui.ingredientResults.isEmpty()) {
                item {
                    val hint = when (ui.addListScope) {
                        NutritionListScope.MINE -> stringResource(R.string.nutrition_mine_ingredients_empty)
                        NutritionListScope.FAVORITES -> stringResource(R.string.nutrition_favorites_ingredients_empty)
                        NutritionListScope.ALL -> {
                            if (ui.addSearchQuery.isBlank()) {
                                stringResource(R.string.nutrition_search_empty_catalog)
                            } else {
                                stringResource(R.string.nutrition_search_no_match, ui.addSearchQuery)
                            }
                        }
                    }
                    Text(hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        AnimatedVisibility(
            visible = hasSelection,
            enter = slideInVertically { it },
            exit = slideOutVertically { it },
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            NutritionLogFoodBottomPanel(
                themeId = panelTheme,
                title = selectedIngredient?.name ?: selectedRecipe?.name.orEmpty(),
                ingredient = selectedIngredient,
                recipe = selectedRecipe,
                recipeLines = ui.selectedRecipeLines,
                loadingRecipeComposition = ui.loadingRecipeComposition,
                mealSlot = ui.addMealSlot,
                grams = ui.addGrams,
                saving = ui.saving,
                canManageIngredient = canManageSelectedIngredient,
                canManageRecipe = canManageSelectedRecipe,
                onEditIngredient = { selectedIngredient?.id?.let { vm.openEditIngredient(it) } },
                onDeleteIngredient = { selectedIngredient?.id?.let { showDeleteIngredientConfirm = true } },
                onEditRecipe = { selectedRecipe?.id?.let { vm.openEditRecipe(it) } },
                onDeleteRecipe = { selectedRecipe?.id?.let { showDeleteRecipeConfirm = true } },
                onDismiss = { vm.clearLogSelection() },
                onMealSlot = { vm.setAddMealSlot(it) },
                onGrams = { vm.setAddGramsPreset(it) },
                onShareViaChat = {
                    val ing = selectedIngredient
                    val rec = selectedRecipe
                    val lines = ui.selectedRecipeLines
                    if (ing != null) {
                        shareIngredientSnap = SharedIngredientSnapshot(
                            name = ing.name,
                            caloriesPer100g = ing.caloriesPer100g,
                            proteinPer100g = ing.proteinPer100g,
                            carbsPer100g = ing.carbsPer100g,
                            fatPer100g = ing.fatPer100g,
                            saturatedFatPer100g = ing.saturatedFatPer100g,
                            sugarsPer100g = ing.sugarsPer100g,
                            fiberPer100g = ing.fiberPer100g,
                            sodiumMgPer100g = ing.sodiumMgPer100g
                        )
                    } else if (rec != null && lines.isNotEmpty() && !ui.loadingRecipeComposition) {
                        val profile = rollupProfilePer100g(lines)
                        shareRecipeSnap = SharedRecipeSnapshot(
                            name = rec.name,
                            description = rec.description,
                            ingredients = lines.map { line ->
                                SharedRecipeIngredientSnapshot(
                                    name = line.ingredient.name,
                                    weightG = line.weightG,
                                    caloriesPer100g = line.ingredient.caloriesPer100g,
                                    proteinPer100g = line.ingredient.proteinPer100g,
                                    carbsPer100g = line.ingredient.carbsPer100g,
                                    fatPer100g = line.ingredient.fatPer100g,
                                    saturatedFatPer100g = line.ingredient.saturatedFatPer100g,
                                    sugarsPer100g = line.ingredient.sugarsPer100g,
                                    fiberPer100g = line.ingredient.fiberPer100g,
                                    sodiumMgPer100g = line.ingredient.sodiumMgPer100g
                                )
                            },
                            profilePer100g = SharedRecipeProfilePer100gSnapshot(
                                calories = profile.calories,
                                protein = profile.protein,
                                carbs = profile.carbs,
                                fat = profile.fat,
                                saturatedFat = profile.saturatedFat,
                                sugars = profile.sugars,
                                fiber = profile.fiber,
                                sodiumMg = profile.sodiumMg
                            )
                        )
                    }
                },
                onSave = { vm.saveDiaryEntry() }
            )
        }
    }

    if (shareIngredientSnap != null || shareRecipeSnap != null) {
        ModalBottomSheet(
            onDismissRequest = {
                shareIngredientSnap = null
                shareRecipeSnap = null
            },
            sheetState = shareSheetState
        ) {
            shareIngredientSnap?.let { snap ->
                ShareIngredientToChatSheetContent(
                    supabase = supabase,
                    snapshot = snap,
                    onDone = {
                        shareIngredientSnap = null
                        shareRecipeSnap = null
                    }
                )
            }
            shareRecipeSnap?.let { snap ->
                ShareRecipeToChatSheetContent(
                    supabase = supabase,
                    snapshot = snap,
                    onDone = {
                        shareIngredientSnap = null
                        shareRecipeSnap = null
                    }
                )
            }
        }
    }

    if (showDeleteRecipeConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteRecipeConfirm = false },
            title = { Text(stringResource(R.string.nutrition_delete_recipe)) },
            text = { Text(stringResource(R.string.nutrition_delete_recipe_confirm)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteRecipeConfirm = false
                        selectedRecipe?.id?.let { vm.deleteSelectedRecipe(it) }
                    }
                ) {
                    Text(stringResource(R.string.nutrition_delete_recipe), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteRecipeConfirm = false }) {
                    Text(stringResource(android.R.string.cancel))
                }
            }
        )
    }

    if (showDeleteIngredientConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteIngredientConfirm = false },
            title = { Text(stringResource(R.string.nutrition_delete_ingredient)) },
            text = { Text(stringResource(R.string.nutrition_delete_ingredient_confirm)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteIngredientConfirm = false
                        selectedIngredient?.id?.let { vm.deleteSelectedIngredient(it) }
                    }
                ) {
                    Text(stringResource(R.string.nutrition_delete_ingredient), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteIngredientConfirm = false }) {
                    Text(stringResource(android.R.string.cancel))
                }
            }
        )
    }

    when (ui.logFoodNestedOverlay) {
        NutritionLogNestedOverlay.CreateIngredient -> {
            val nestedState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ModalBottomSheet(onDismissRequest = { vm.dismissLogFoodNestedOverlay() }, sheetState = nestedState) {
                NutritionIngredientEditorSheet(ui, vm, isEdit = false, onClose = { vm.dismissLogFoodNestedOverlay() })
            }
        }
        NutritionLogNestedOverlay.EditIngredient -> {
            val nestedState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ModalBottomSheet(onDismissRequest = { vm.dismissLogFoodNestedOverlay() }, sheetState = nestedState) {
                NutritionIngredientEditorSheet(ui, vm, isEdit = true, onClose = { vm.dismissLogFoodNestedOverlay() })
            }
        }
        NutritionLogNestedOverlay.CreateRecipe -> {
            val nestedState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ModalBottomSheet(onDismissRequest = { vm.dismissLogFoodNestedOverlay() }, sheetState = nestedState) {
                NutritionRecipeEditorSheet(ui, vm, isEdit = false, onClose = { vm.dismissLogFoodNestedOverlay() })
            }
        }
        NutritionLogNestedOverlay.EditRecipe -> {
            val nestedState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ModalBottomSheet(onDismissRequest = { vm.dismissLogFoodNestedOverlay() }, sheetState = nestedState) {
                NutritionRecipeEditorSheet(ui, vm, isEdit = true, onClose = { vm.dismissLogFoodNestedOverlay() })
            }
        }
        NutritionLogNestedOverlay.None -> Unit
    }
}

@Composable
private fun NutritionLogFoodBottomPanel(
    themeId: String,
    title: String,
    ingredient: NutritionIngredientWire?,
    recipe: NutritionRecipeWire?,
    recipeLines: List<NutritionRecipeLineDraft>,
    loadingRecipeComposition: Boolean,
    mealSlot: String,
    grams: Double,
    saving: Boolean,
    canManageIngredient: Boolean,
    canManageRecipe: Boolean,
    onEditIngredient: () -> Unit,
    onDeleteIngredient: () -> Unit,
    onEditRecipe: () -> Unit,
    onDeleteRecipe: () -> Unit,
    onDismiss: () -> Unit,
    onMealSlot: (String) -> Unit,
    onGrams: (Double) -> Unit,
    onShareViaChat: () -> Unit,
    onSave: () -> Unit
) {
    val kcalPreview = when {
        ingredient != null -> (grams * ingredient.caloriesPer100g / 100.0).roundToInt()
        recipeLines.isNotEmpty() -> {
            val profile = rollupProfilePer100g(recipeLines)
            (grams * profile.calories / 100.0).roundToInt()
        }
        else -> null
    }
    val canSave = !saving && (ingredient != null || (recipeLines.isNotEmpty() && !loadingRecipeComposition))

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
            .liftrAppBackgroundGradientOpaque(themeId)
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f).padding(end = 8.dp)
            )
            if (canManageIngredient) {
                TextButton(onClick = onEditIngredient, enabled = !saving) {
                    Text(stringResource(R.string.nutrition_edit_ingredient))
                }
                TextButton(onClick = onDeleteIngredient, enabled = !saving) {
                    Text(
                        stringResource(R.string.nutrition_delete),
                        color = MaterialTheme.colorScheme.error
                    )
                }
            } else if (canManageRecipe) {
                TextButton(onClick = onEditRecipe, enabled = !saving) {
                    Text(stringResource(R.string.nutrition_edit_recipe))
                }
                TextButton(onClick = onDeleteRecipe, enabled = !saving) {
                    Text(
                        stringResource(R.string.nutrition_delete),
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
            IconButton(onClick = onDismiss, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.nutrition_close))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            mealSlots.forEach { slot ->
                FilterChip(selected = mealSlot == slot, onClick = { onMealSlot(slot) }, label = { Text(slot) })
            }
        }
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = 200.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (ingredient != null) {
                NutritionFactsCard(title = stringResource(R.string.nutrition_facts_title), profile = ingredient.toProfilePer100g())
            } else if (loadingRecipeComposition) {
                CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
            } else if (recipeLines.isNotEmpty()) {
                val desc = recipe?.description?.trim().orEmpty()
                if (desc.isNotEmpty()) {
                    var descExpanded by remember { mutableStateOf(false) }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        TextButton(onClick = { descExpanded = !descExpanded }) {
                            Text(stringResource(R.string.nutrition_description))
                        }
                        if (descExpanded) {
                            Text(desc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                recipeLines.forEach { line ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("✓", color = MaterialTheme.colorScheme.tertiary)
                        Text("${line.weightG.roundToInt()}g ${line.ingredient.name}", style = MaterialTheme.typography.bodySmall)
                    }
                }
                NutritionFactsCard(title = recipe?.name ?: title, profile = rollupProfilePer100g(recipeLines))
            }
        }
        NutritionGramsPicker(grams, onGrams, kcalPreview)
        Button(
            onClick = onShareViaChat,
            modifier = Modifier.fillMaxWidth(),
            enabled = !saving && (ingredient != null || (recipeLines.isNotEmpty() && !loadingRecipeComposition))
        ) {
            Text("Share via Chat")
        }
        Button(onClick = onSave, modifier = Modifier.fillMaxWidth(), enabled = canSave) {
            Text(stringResource(R.string.nutrition_add_to_diary))
        }
    }
}

@Composable
private fun NutritionRecipeLineEditor(
    name: String,
    weightG: Double,
    onWeightChange: (Double) -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(name, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                IconButton(onClick = onDelete) {
                    Icon(Icons.Filled.Delete, contentDescription = null)
                }
            }
            var weightText by remember(weightG) { mutableStateOf(weightG.roundToInt().toString()) }
            LaunchedEffect(weightG) {
                val t = weightG.roundToInt().toString()
                if (weightText != t) weightText = t
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { onWeightChange((weightG - 5).coerceAtLeast(5.0)) }) { Text("−") }
                OutlinedTextField(
                    value = weightText,
                    onValueChange = { raw ->
                        val filtered = raw.filter { it.isDigit() }
                        weightText = filtered
                        filtered.toDoubleOrNull()?.let { onWeightChange(it.coerceIn(5.0, 2000.0)) }
                    },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    label = { Text("g") }
                )
                IconButton(onClick = { onWeightChange((weightG + 5).coerceAtMost(2000.0)) }) { Text("+") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(5.0, 10.0, 50.0, 100.0, 150.0, 200.0, 250.0).forEach { preset ->
                    FilterChip(
                        selected = weightG == preset,
                        onClick = { onWeightChange(preset) },
                        label = { Text("${preset.toInt()} g") }
                    )
                }
            }
        }
    }
}

@Composable
private fun NutritionIngredientEditorSheet(
    ui: NutritionUiState,
    vm: NutritionViewModel,
    isEdit: Boolean,
    onClose: (() -> Unit)? = null
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showSourceChooser by rememberSaveable { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var isScanning by remember { mutableStateOf(false) }
    val scanFailedMessage = stringResource(R.string.nutrition_scan_failed)
    val titleRes = if (isEdit) R.string.nutrition_edit_ingredient_title else R.string.nutrition_new_ingredient
    val saveLabelRes = if (isEdit) R.string.nutrition_save_ingredient_changes else R.string.nutrition_save_ingredient

    val ingredientForm = remember(
        ui.createCalories,
        ui.createProtein,
        ui.createCarbs,
        ui.createFat,
        ui.createSaturatedFat,
        ui.createSugars,
        ui.createFiber,
        ui.createSodiumMg
    ) {
        ui.ingredientFormState()
    }
    val previewProfile = remember(ingredientForm) { ingredientForm.toProfilePer100g() }

    fun processBitmap(bitmap: Bitmap?) {
        if (bitmap == null) return
        scope.launch {
            isScanning = true
            try {
                val parsed = withContext(Dispatchers.Default) {
                    val recognition = NutritionLabelOCR.recognize(bitmap)
                    NutritionLabelParser.parse(recognition)
                }
                withContext(Dispatchers.Main.immediate) {
                    vm.applyScannedNutritionProfile(parsed)
                }
            } catch (_: Exception) {
                AppSnackbar.showError(scanFailedMessage)
            } finally {
                isScanning = false
            }
        }
    }

    fun loadBitmapFromUri(uri: Uri): Bitmap? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val source = ImageDecoder.createSource(context.contentResolver, uri)
                ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                    decoder.isMutableRequired = false
                }
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
            }
        } catch (_: Exception) {
            null
        }
    }

    val takePictureLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicturePreview()
    ) { bitmap -> processBitmap(bitmap) }

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            takePictureLauncher.launch(null)
        } else {
            AppSnackbar.showError(scanFailedMessage)
        }
    }

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        uri?.let { processBitmap(loadBitmapFromUri(it)) }
    }

    if (showSourceChooser) {
        AlertDialog(
            onDismissRequest = { showSourceChooser = false },
            title = { Text(stringResource(R.string.nutrition_scan_label)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(
                        onClick = {
                            showSourceChooser = false
                            when {
                                ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                                    PackageManager.PERMISSION_GRANTED -> takePictureLauncher.launch(null)
                                else -> cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                            }
                        }
                    ) { Text(stringResource(R.string.nutrition_scan_source_camera)) }
                    TextButton(
                        onClick = {
                            showSourceChooser = false
                            galleryLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        }
                    ) { Text(stringResource(R.string.nutrition_scan_source_gallery)) }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showSourceChooser = false }) {
                    Text(stringResource(R.string.nutrition_scan_source_cancel))
                }
            }
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.nutrition_delete_ingredient)) },
            text = { Text(stringResource(R.string.nutrition_delete_ingredient_confirm)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirm = false
                        vm.deleteIngredient()
                    }
                ) {
                    Text(stringResource(R.string.nutrition_delete_ingredient), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(android.R.string.cancel))
                }
            }
        )
    }

    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(titleRes), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        NutritionMaterialField(ui.createName, { vm.setCreateField(name = it) }, "Name")
        if (!isEdit) {
            FilledTonalButton(
                onClick = { showSourceChooser = true },
                modifier = Modifier.fillMaxWidth(),
                enabled = !isScanning
            ) {
                Icon(Icons.Default.PhotoCamera, contentDescription = null, modifier = Modifier.size(20.dp))
                Text(
                    stringResource(R.string.nutrition_scan_label),
                    modifier = Modifier.padding(start = 8.dp)
                )
                if (isScanning) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .padding(start = 12.dp)
                            .size(20.dp),
                        strokeWidth = 2.dp
                    )
                }
            }
        }
        NutritionMaterialField(ingredientForm.calories, { vm.setCreateField(calories = it) }, "Calories / 100g")
        NutritionMaterialField(ingredientForm.protein, { vm.setCreateField(protein = it) }, "Protein / 100g")
        NutritionMaterialField(ingredientForm.carbs, { vm.setCreateField(carbs = it) }, "Carbs / 100g")
        NutritionMaterialField(ingredientForm.fat, { vm.setCreateField(fat = it) }, "Fat / 100g")
        NutritionMaterialField(ingredientForm.saturatedFat, { vm.setCreateField(saturatedFat = it) }, "Sat. fat / 100g")
        NutritionMaterialField(ingredientForm.sugars, { vm.setCreateField(sugars = it) }, "Sugars / 100g")
        NutritionMaterialField(ingredientForm.fiber, { vm.setCreateField(fiber = it) }, "Fiber / 100g")
        NutritionMaterialField(ingredientForm.sodiumMg, { vm.setCreateField(sodiumMg = it) }, "Sodium / 100g (mg)")
        NutritionFactsCard(
            title = ui.createName.ifBlank { "Preview" },
            profile = previewProfile
        )
        if (isEdit) {
            TextButton(
                onClick = { showDeleteConfirm = true },
                modifier = Modifier.fillMaxWidth(),
                enabled = !ui.saving
            ) {
                Text(
                    stringResource(R.string.nutrition_delete_ingredient),
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
        Button(
            onClick = { vm.saveIngredient(onClose) },
            modifier = Modifier.fillMaxWidth(),
            enabled = !ui.saving && ui.createName.isNotBlank()
        ) { Text(stringResource(saveLabelRes)) }
        if (onClose != null) {
            TextButton(onClick = onClose, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.nutrition_close))
            }
        }
    }
}

@Composable
private fun NutritionCreateIngredientSheet(
    ui: NutritionUiState,
    vm: NutritionViewModel
) {
    NutritionIngredientEditorSheet(ui, vm, isEdit = false)
}

@Composable
private fun NutritionRecipeEditorSheet(
    ui: NutritionUiState,
    vm: NutritionViewModel,
    isEdit: Boolean,
    onClose: (() -> Unit)? = null
) {
    var showDeleteConfirm by remember { mutableStateOf(false) }
    val titleRes = if (isEdit) R.string.nutrition_edit_recipe else R.string.nutrition_new_recipe
    val saveLabelRes = if (isEdit) R.string.nutrition_save_recipe_changes else R.string.nutrition_save_recipe

    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(titleRes), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Text(
            stringResource(R.string.nutrition_recipe_build_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (ui.recipeEditorLoading) {
            CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
        }
        NutritionMaterialField(ui.recipeName, vm::setRecipeName, "Recipe name")
        NutritionMaterialField(ui.recipeDescription, vm::setRecipeDescription, stringResource(R.string.nutrition_description))
        Text(
            stringResource(
                R.string.nutrition_recipe_ingredients_count,
                ui.recipeLines.size
            ),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        if (ui.recipeLines.isNotEmpty()) {
            NutritionFactsCard(
                title = ui.recipeName.ifBlank { "Recipe preview" },
                profile = rollupProfilePer100g(ui.recipeLines)
            )
        }
        ui.recipeLines.forEachIndexed { index, line ->
            NutritionRecipeLineEditor(
                name = line.ingredient.name,
                weightG = line.weightG,
                onWeightChange = { vm.updateRecipeLineWeight(index, it) },
                onDelete = { vm.removeRecipeLine(index) }
            )
        }
        NutritionMaterialField(ui.recipePickQuery, vm::setRecipePickQuery, "Search ingredient")
        ui.recipePickResults.forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { vm.selectRecipePick(row.id) }, modifier = Modifier.weight(1f)) {
                    Text(
                        row.name,
                        fontWeight = if (ui.recipePickIngredientId == row.id) FontWeight.Bold else FontWeight.Normal
                    )
                }
                TextButton(onClick = { vm.addRecipeLineFromIngredient(row.id) }) {
                    Text(stringResource(R.string.nutrition_add_ingredient_quick))
                }
            }
        }
        if (ui.recipePickIngredientId != null) {
            ui.recipePickResults.find { it.id == ui.recipePickIngredientId }?.let { pick ->
                NutritionFactsCard(title = pick.name, profile = pick.toProfilePer100g())
            }
            NutritionGramsPicker(ui.recipePickGrams, vm::setRecipePickGrams, null)
            Button(onClick = { vm.addRecipeLine() }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.nutrition_add_to_recipe))
            }
        }
        if (isEdit) {
            TextButton(
                onClick = { showDeleteConfirm = true },
                modifier = Modifier.fillMaxWidth(),
                enabled = !ui.saving && !ui.recipeEditorLoading
            ) {
                Text(
                    stringResource(R.string.nutrition_delete_recipe),
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
        Button(
            onClick = { vm.saveRecipe() },
            modifier = Modifier.fillMaxWidth(),
            enabled = !ui.saving && !ui.recipeEditorLoading && ui.recipeLines.isNotEmpty() && ui.recipeName.isNotBlank()
        ) {
            Text(stringResource(saveLabelRes))
        }
        if (onClose != null) {
            TextButton(onClick = onClose, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.nutrition_close))
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.nutrition_delete_recipe)) },
            text = { Text(stringResource(R.string.nutrition_delete_recipe_confirm)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirm = false
                        vm.deleteRecipe()
                    }
                ) {
                    Text(stringResource(R.string.nutrition_delete_recipe), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(android.R.string.cancel))
                }
            }
        )
    }
}

@Composable
private fun NutritionCreateRecipeSheet(
    ui: NutritionUiState,
    vm: NutritionViewModel,
    onClose: (() -> Unit)? = null
) {
    NutritionRecipeEditorSheet(ui, vm, isEdit = false, onClose = onClose)
}

@Composable
private fun NutritionEditLogSheet(ui: NutritionUiState, vm: NutritionViewModel, item: NutritionDiaryItemUi) {
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(item.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            mealSlots.forEach { slot ->
                FilterChip(selected = ui.editMealSlot == slot, onClick = { vm.setEditMealSlot(slot) }, label = { Text(slot) })
            }
        }
        NutritionGramsPicker(
            ui.editGrams,
            { vm.setEditGrams(it) },
            (item.caloriesKcal * ui.editGrams / item.quantityG.coerceAtLeast(1.0)).roundToInt()
        )
        Button(onClick = { vm.saveEditLog(item.id) }, modifier = Modifier.fillMaxWidth()) { Text("Save changes") }
        TextButton(onClick = { vm.deleteEditLog(item.id) }, modifier = Modifier.fillMaxWidth()) {
            Text("Delete from diary", color = MaterialTheme.colorScheme.error)
        }
    }
}

private val mealSlots = listOf(
    BackendContracts.NutritionMealSlots.BREAKFAST,
    BackendContracts.NutritionMealSlots.LUNCH,
    BackendContracts.NutritionMealSlots.DINNER,
    BackendContracts.NutritionMealSlots.SNACK
)
