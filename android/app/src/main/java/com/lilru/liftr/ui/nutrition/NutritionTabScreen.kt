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
import androidx.compose.foundation.layout.navigationBarsPadding
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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.material3.Switch
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.domain.NutritionMealPlanInviteUi
import com.lilru.liftr.domain.NutritionMealPlanItemUi
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
        if (newValue == SheetValue.Hidden && ui.logCart.isNotEmpty()) false else true
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
            var fabMenuExpanded by remember { mutableStateOf(false) }
            Box {
                IconButton(onClick = { fabMenuExpanded = true }) {
                    Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.nutrition_add_food))
                }
                DropdownMenu(expanded = fabMenuExpanded, onDismissRequest = { fabMenuExpanded = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.nutrition_add_food)) },
                        onClick = {
                            fabMenuExpanded = false
                            vm.openAddFood(plan = false)
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.nutrition_plan_food)) },
                        onClick = {
                            fabMenuExpanded = false
                            vm.openAddFood(plan = true)
                        }
                    )
                }
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
            if (ui.pendingInvites.isNotEmpty()) {
                item {
                    Text(
                        stringResource(R.string.nutrition_meal_invitations),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                items(ui.pendingInvites, key = { it.targetId }) { invite ->
                    NutritionMealPlanInviteCard(
                        invite = invite,
                        onAccept = { vm.acceptMealPlanInvite(invite.targetId) },
                        onDecline = { vm.rejectMealPlanInvite(invite.targetId) }
                    )
                }
            }
            if (ui.plannedItems.isNotEmpty()) {
                item {
                    Text(
                        stringResource(R.string.nutrition_planned_meals),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                items(ui.plannedItems, key = { it.targetId }) { item ->
                    val userId = supabase.auth.currentUserOrNull()?.id.orEmpty()
                    NutritionMealPlanItemCard(
                        item = item,
                        viewingUserId = userId,
                        onClick = { vm.setOverlay(NutritionOverlay.EditPlannedMeal(item)) },
                        onDecline = { vm.rejectMealPlanInvite(item.targetId) },
                        onMarkEaten = { vm.completePlannedMeal(item.targetId) }
                    )
                }
            }
            vm.mealSlotOrder.forEach { slot ->
                item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text(slot, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        IconButton(onClick = { vm.openAddFood(mealSlot = slot, plan = false) }) {
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
                    is NutritionOverlay.EditPlannedMeal -> NutritionEditPlannedMealSheet(ui, vm, overlay.item)
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
                        filtered.toDoubleOrNull()?.let { onChange(it.coerceAtMost(2000.0)) }
                    },
                    modifier = Modifier
                        .weight(1f)
                        .onFocusChanged { focusState ->
                            if (!focusState.isFocused) {
                                val parsed = gramsText.toDoubleOrNull()
                                if (parsed == null || parsed <= 0.0) {
                                    gramsText = grams.roundToInt().toString()
                                } else {
                                    onChange(parsed.coerceIn(5.0, 2000.0))
                                }
                            }
                        },
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

@Composable
private fun NutritionLogCatalogRowMenu(
    canManage: Boolean,
    editLabelRes: Int,
    onShare: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(
                Icons.Filled.MoreVert,
                contentDescription = stringResource(R.string.nutrition_more_actions)
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.nutrition_share_via_chat)) },
                onClick = {
                    expanded = false
                    onShare()
                }
            )
            if (canManage) {
                DropdownMenuItem(
                    text = { Text(stringResource(editLabelRes)) },
                    onClick = {
                        expanded = false
                        onEdit()
                    }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.nutrition_delete), color = MaterialTheme.colorScheme.error) },
                    onClick = {
                        expanded = false
                        onDelete()
                    }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NutritionLogFoodSheet(supabase: SupabaseClient, ui: NutritionUiState, vm: NutritionViewModel) {
    val hasCart = ui.logCart.isNotEmpty()
    val currentUserId = remember(supabase) { supabase.auth.currentUserOrNull()?.id }
    var pendingDeleteIngredientId by remember { mutableStateOf<String?>(null) }
    var pendingDeleteRecipeId by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val panelTheme = remember(context) { LiftrPreferences.backgroundTheme(context) }
    val panelBottomPadding = if (hasCart) 420.dp else 16.dp
    var shareIngredientSnap by remember { mutableStateOf<SharedIngredientSnapshot?>(null) }
    var shareRecipeSnap by remember { mutableStateOf<SharedRecipeSnapshot?>(null) }
    val shareSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val shareScope = rememberCoroutineScope()

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            contentPadding = PaddingValues(bottom = panelBottomPadding),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text(
                    stringResource(if (ui.addFoodIsPlan) R.string.nutrition_plan_food else R.string.nutrition_add_food),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold
                )
            }
            if (ui.addFoodIsPlan) {
                item {
                    Text(stringResource(R.string.nutrition_plan_date), style = MaterialTheme.typography.labelMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        FilledTonalButton(onClick = { vm.setPlanDate(ui.planDate.minusDays(1)) }) { Text("−") }
                        Text(ui.planDate.format(DateTimeFormatter.ISO_LOCAL_DATE), fontWeight = FontWeight.Medium)
                        FilledTonalButton(onClick = { vm.setPlanDate(ui.planDate.plusDays(1)) }) { Text("+") }
                    }
                }
                item {
                    Text(
                        stringResource(R.string.nutrition_participants_header),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f))
                    ) {
                        Column(Modifier.padding(12.dp)) {
                            if (ui.selectedPlanPartners.isEmpty()) {
                                Text(
                                    stringResource(R.string.nutrition_no_participants),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            } else {
                                ui.selectedPlanPartners.forEach { profile ->
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = 4.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(
                                            text = profile.username?.let { "@$it" } ?: "User",
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            modifier = Modifier.weight(1f)
                                        )
                                        TextButton(onClick = { vm.removePlanPartner(profile.userId) }) {
                                            Text(stringResource(R.string.nutrition_remove_participant))
                                        }
                                    }
                                }
                            }
                            TextButton(onClick = { vm.setShowPlanParticipantsPicker(true) }) {
                                Text(stringResource(R.string.nutrition_add_participants))
                            }
                        }
                    }
                }
            }
            item {
                Text(
                    stringResource(R.string.nutrition_cart_tap_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
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
                    val inCart = NutritionLogCartLogic.cartContainsIngredient(ui.logCart, row.id)
                    val isFav = ui.favoriteIngredientIds.contains(row.id)
                    val canManage = currentUserId != null && row.userId == currentUserId
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(
                            onClick = { vm.toggleCartIngredient(row.id) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(row.name, fontWeight = if (inCart) FontWeight.Bold else FontWeight.Normal)
                                    Text(stringResource(R.string.nutrition_ingredient_kcal_per_100g, row.caloriesPer100g.roundToInt()))
                                }
                                if (inCart) {
                                    Icon(
                                        Icons.Filled.CheckCircle,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.padding(start = 8.dp)
                                    )
                                }
                            }
                        }
                        NutritionLogCatalogRowMenu(
                            canManage = canManage,
                            editLabelRes = R.string.nutrition_edit_ingredient,
                            onShare = {
                                shareIngredientSnap = SharedIngredientSnapshot(
                                    name = row.name,
                                    caloriesPer100g = row.caloriesPer100g,
                                    proteinPer100g = row.proteinPer100g,
                                    carbsPer100g = row.carbsPer100g,
                                    fatPer100g = row.fatPer100g,
                                    saturatedFatPer100g = row.saturatedFatPer100g,
                                    sugarsPer100g = row.sugarsPer100g,
                                    fiberPer100g = row.fiberPer100g,
                                    sodiumMgPer100g = row.sodiumMgPer100g
                                )
                            },
                            onEdit = { vm.openEditIngredient(row.id) },
                            onDelete = { pendingDeleteIngredientId = row.id }
                        )
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
                    val inCart = NutritionLogCartLogic.cartContainsRecipe(ui.logCart, row.id)
                    val isFav = ui.favoriteRecipeIds.contains(row.id)
                    val canManage = currentUserId != null && row.userId == currentUserId
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(
                            onClick = { vm.toggleCartRecipe(row.id) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Text(row.name, fontWeight = if (inCart) FontWeight.Bold else FontWeight.Normal, modifier = Modifier.weight(1f))
                                if (inCart) {
                                    Icon(
                                        Icons.Filled.CheckCircle,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.padding(start = 8.dp)
                                    )
                                }
                            }
                        }
                        NutritionLogCatalogRowMenu(
                            canManage = canManage,
                            editLabelRes = R.string.nutrition_edit_recipe,
                            onShare = {
                                val cartLines = ui.logCart.find { it.recipeId == row.id }?.recipeLines
                                if (!cartLines.isNullOrEmpty()) {
                                    shareRecipeSnap = recipeShareSnapshot(row, cartLines)
                                } else {
                                    shareScope.launch {
                                        runCatching { vm.fetchRecipeLinesForShare(row.id) }
                                            .onSuccess { lines ->
                                                if (lines.isNotEmpty()) {
                                                    shareRecipeSnap = recipeShareSnapshot(row, lines)
                                                }
                                            }
                                    }
                                }
                            },
                            onEdit = { vm.openEditRecipe(row.id) },
                            onDelete = { pendingDeleteRecipeId = row.id }
                        )
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
            visible = hasCart,
            enter = slideInVertically { it },
            exit = slideOutVertically { it },
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            NutritionLogFoodCartPanel(
                themeId = panelTheme,
                cart = ui.logCart,
                mealSlot = ui.addMealSlot,
                saving = ui.saving,
                isPlan = ui.addFoodIsPlan,
                currentUserId = currentUserId,
                planAssignees = remember(currentUserId, ui.selectedPlanPartners) {
                    val chips = ui.selectedPlanPartners.map { profile ->
                        NutritionPlanAssigneeChip(
                            userId = profile.userId,
                            label = profile.username?.let { "@$it" } ?: "User"
                        )
                    }.toMutableList()
                    val selfId = currentUserId
                    if (selfId != null && chips.none { it.userId == selfId }) {
                        chips.add(0, NutritionPlanAssigneeChip(selfId, "You"))
                    }
                    chips
                },
                onClearCart = { vm.clearLogCart() },
                onMealSlot = { vm.setAddMealSlot(it) },
                onUpdateGrams = { localId, grams -> vm.updateCartItemGrams(localId, grams) },
                onUpdatePerUserGrams = { localId, userId, grams -> vm.updateCartPerUserGrams(localId, userId, grams) },
                onRemoveItem = { vm.removeCartItem(it) },
                onToggleAssignee = { localId, userId -> vm.toggleCartAssignee(localId, userId) },
                onSave = { vm.saveDiaryCart() }
            )
        }
    }

    if (ui.addFoodIsPlan && ui.showPlanParticipantsPicker) {
        var pickerSelection by remember { mutableStateOf(setOf<String>()) }
        var pickerQuery by remember { mutableStateOf("") }
        val alreadySelected = remember(ui.selectedPlanPartners) {
            ui.selectedPlanPartners.map { it.userId }.toSet()
        }
        val filtered = remember(ui.followingForPlan, pickerQuery) {
            val q = pickerQuery.trim().lowercase()
            val base = ui.followingForPlan
            if (q.isEmpty()) base else base.filter {
                (it.username ?: it.userId).lowercase().contains(q)
            }
        }
        ModalBottomSheet(onDismissRequest = { vm.setShowPlanParticipantsPicker(false) }) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = { vm.setShowPlanParticipantsPicker(false) }) {
                        Text(stringResource(R.string.add_participants_sheet_cancel))
                    }
                    TextButton(
                        onClick = {
                            val picked = ui.followingForPlan.filter {
                                it.userId in pickerSelection && it.userId !in alreadySelected
                            }
                            vm.addPlanPartners(picked)
                            pickerSelection = emptySet()
                        },
                        enabled = pickerSelection.isNotEmpty()
                    ) {
                        Text(stringResource(R.string.add_participants_sheet_confirm))
                    }
                }
                OutlinedTextField(
                    value = pickerQuery,
                    onValueChange = { pickerQuery = it },
                    placeholder = { Text(stringResource(R.string.add_participants_search_placeholder)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                if (ui.followingForPlan.isEmpty()) {
                    Text(
                        stringResource(R.string.nutrition_follow_to_invite),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 12.dp)
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 400.dp)
                            .padding(top = 8.dp)
                    ) {
                        items(filtered, key = { it.userId }) { profile ->
                            val enabled = profile.userId !in alreadySelected
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = profile.username?.let { "@$it" } ?: "User",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.weight(1f)
                                )
                                Switch(
                                    checked = profile.userId in pickerSelection || profile.userId in alreadySelected,
                                    onCheckedChange = { on ->
                                        if (!enabled) return@Switch
                                        pickerSelection = if (on) {
                                            pickerSelection + profile.userId
                                        } else {
                                            pickerSelection - profile.userId
                                        }
                                    },
                                    enabled = enabled
                                )
                            }
                        }
                    }
                }
            }
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

    pendingDeleteRecipeId?.let { recipeId ->
        AlertDialog(
            onDismissRequest = { pendingDeleteRecipeId = null },
            title = { Text(stringResource(R.string.nutrition_delete_recipe)) },
            text = { Text(stringResource(R.string.nutrition_delete_recipe_confirm)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingDeleteRecipeId = null
                        vm.deleteSelectedRecipe(recipeId)
                    }
                ) {
                    Text(stringResource(R.string.nutrition_delete_recipe), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDeleteRecipeId = null }) {
                    Text(stringResource(android.R.string.cancel))
                }
            }
        )
    }

    pendingDeleteIngredientId?.let { ingredientId ->
        AlertDialog(
            onDismissRequest = { pendingDeleteIngredientId = null },
            title = { Text(stringResource(R.string.nutrition_delete_ingredient)) },
            text = { Text(stringResource(R.string.nutrition_delete_ingredient_confirm)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingDeleteIngredientId = null
                        vm.deleteSelectedIngredient(ingredientId)
                    }
                ) {
                    Text(stringResource(R.string.nutrition_delete_ingredient), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDeleteIngredientId = null }) {
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

private fun recipeShareSnapshot(
    row: NutritionRecipeWire,
    lines: List<NutritionRecipeLineDraft>
): SharedRecipeSnapshot {
    val profile = rollupProfilePer100g(lines)
    return SharedRecipeSnapshot(
        name = row.name,
        description = row.description,
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

@Composable
private fun NutritionMealPlanInviteCard(
    invite: NutritionMealPlanInviteUi,
    onAccept: () -> Unit,
    onDecline: () -> Unit
) {
    val plannedForLabel = runCatching {
        val date = java.time.LocalDate.parse(invite.planDate)
        val formatted = date.format(java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM))
        stringResource(R.string.nutrition_invite_planned_for, formatted)
    }.getOrElse { stringResource(R.string.nutrition_invite_planned_for, invite.planDate) }
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(invite.foodName, fontWeight = FontWeight.SemiBold)
            Text(
                plannedForLabel,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                "${invite.mealSlot} · ${invite.quantityG.roundToInt()} g · ${invite.caloriesKcal.roundToInt()} kcal",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            invite.creatorUsername?.let {
                Text("From @$it", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onDecline) { Text(stringResource(R.string.nutrition_decline)) }
                Button(onClick = onAccept) { Text(stringResource(R.string.nutrition_accept)) }
            }
        }
    }
}

@Composable
private fun NutritionMealPlanItemCard(
    item: NutritionMealPlanItemUi,
    viewingUserId: String,
    onClick: () -> Unit,
    onDecline: () -> Unit,
    onMarkEaten: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors()
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(item.foodName, fontWeight = FontWeight.SemiBold)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
            }
            Text(
                "${item.mealSlot} · ${item.quantityG.roundToInt()} g · ${item.caloriesKcal.roundToInt()} kcal",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            item.partnerLabel?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            item.partnerStatusLabel?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (item.canDecline(viewingUserId) || item.canMarkEaten(viewingUserId)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (item.canDecline(viewingUserId)) {
                        TextButton(onClick = onDecline) { Text(stringResource(R.string.nutrition_decline)) }
                    }
                    if (item.canMarkEaten(viewingUserId)) {
                        Button(onClick = onMarkEaten) { Text(stringResource(R.string.nutrition_mark_eaten)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun NutritionLogFoodCartPanel(
    themeId: String,
    cart: List<NutritionLogCartItem>,
    mealSlot: String,
    saving: Boolean,
    isPlan: Boolean,
    currentUserId: String?,
    planAssignees: List<NutritionPlanAssigneeChip>,
    onClearCart: () -> Unit,
    onMealSlot: (String) -> Unit,
    onUpdateGrams: (String, Double) -> Unit,
    onUpdatePerUserGrams: (String, String, Double) -> Unit,
    onRemoveItem: (String) -> Unit,
    onToggleAssignee: (String, String) -> Unit,
    onSave: () -> Unit
) {
    val totalKcal = NutritionLogCartLogic.totalKcal(cart)
    val canSave = NutritionLogCartLogic.canSave(cart, saving)

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
            .liftrAppBackgroundGradientOpaque(themeId)
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.nutrition_cart_items_count, cart.size),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                if (totalKcal > 0) {
                    Text(
                        stringResource(R.string.nutrition_cart_total_kcal, totalKcal),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            IconButton(onClick = onClearCart, modifier = Modifier.size(40.dp), enabled = !saving) {
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
                .heightIn(max = 220.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(if (cart.size > 1) 14.dp else 8.dp)
        ) {
            cart.forEach { item ->
                val groupsCartLines = cart.size > 1
                if (item.loadingComposition) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text(item.displayName, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                        CircularProgressIndicator(Modifier.size(24.dp))
                        IconButton(onClick = { onRemoveItem(item.localId) }) {
                            Icon(Icons.Filled.Delete, contentDescription = null)
                        }
                    }
                } else {
                    val lineKcal = NutritionLogCartLogic.lineKcal(item)?.roundToInt()
                    val selectedAssignees = if (isPlan) {
                        planAssignees.filter { chip ->
                            item.assignedUserIds.contains(chip.userId) ||
                                (item.assignedUserIds.isEmpty() && chip.userId == currentUserId)
                        }
                    } else {
                        emptyList()
                    }
                    val multiAssigneePlan = isPlan && selectedAssignees.size > 1
                    Column(
                        modifier = if (groupsCartLines) {
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
                                .padding(12.dp)
                        } else {
                            Modifier.fillMaxWidth()
                        },
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(item.displayName, fontWeight = FontWeight.Medium)
                                if (!multiAssigneePlan && lineKcal != null) {
                                    Text(
                                        stringResource(R.string.nutrition_cart_line_kcal, lineKcal),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                            IconButton(onClick = { onRemoveItem(item.localId) }) {
                                Icon(Icons.Filled.Delete, contentDescription = null)
                            }
                        }
                        if (!multiAssigneePlan) {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.35f)
                                ),
                                shape = RoundedCornerShape(12.dp)
                            ) {
                                Column(Modifier.padding(12.dp)) {
                                    NutritionGramsPicker(item.grams, { onUpdateGrams(item.localId, it) }, lineKcal)
                                }
                            }
                        }
                        if (isPlan && planAssignees.isNotEmpty()) {
                            Text(
                                stringResource(R.string.nutrition_cart_for_label),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                planAssignees.forEach { profile ->
                                    val selected = item.assignedUserIds.contains(profile.userId) ||
                                        (item.assignedUserIds.isEmpty() && profile.userId == currentUserId)
                                    FilterChip(
                                        selected = selected,
                                        onClick = { onToggleAssignee(item.localId, profile.userId) },
                                        label = { Text(profile.label) }
                                    )
                                }
                            }
                            if (selectedAssignees.size > 1) {
                                Text(
                                    stringResource(R.string.nutrition_cart_amount_per_person),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                selectedAssignees.forEach { profile ->
                                    val userGrams = NutritionLogCartLogic.gramsForUser(item, profile.userId)
                                    val userKcal = lineKcal?.let { userGrams / item.grams.coerceAtLeast(1.0) * it }?.roundToInt()
                                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(profile.label, style = MaterialTheme.typography.labelSmall)
                                        NutritionGramsPicker(
                                            userGrams,
                                            { onUpdatePerUserGrams(item.localId, profile.userId, it) },
                                            userKcal
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Button(onClick = onSave, modifier = Modifier.fillMaxWidth(), enabled = canSave) {
            if (saving) {
                CircularProgressIndicator(Modifier.size(22.dp))
            } else {
                Text(
                    if (isPlan) {
                        stringResource(R.string.nutrition_plan_n_meals, cart.size)
                    } else {
                        stringResource(R.string.nutrition_add_n_to_diary, cart.size)
                    }
                )
            }
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
                        filtered.toDoubleOrNull()?.let { onWeightChange(it.coerceAtMost(2000.0)) }
                    },
                    modifier = Modifier
                        .weight(1f)
                        .onFocusChanged { focusState ->
                            if (!focusState.isFocused) {
                                val parsed = weightText.toDoubleOrNull()
                                if (parsed == null || parsed <= 0.0) {
                                    weightText = weightG.roundToInt().toString()
                                } else {
                                    onWeightChange(parsed.coerceIn(5.0, 2000.0))
                                }
                            }
                        },
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

@Composable
private fun NutritionEditPlannedMealSheet(ui: NutritionUiState, vm: NutritionViewModel, item: NutritionMealPlanItemUi) {
    Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(item.foodName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
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
        Button(onClick = { vm.savePlannedMeal(item.targetId) }, modifier = Modifier.fillMaxWidth(), enabled = !ui.saving) {
            Text(stringResource(R.string.nutrition_save_changes))
        }
        TextButton(
            onClick = {
                vm.rejectMealPlanInvite(item.targetId)
                vm.dismissOverlay()
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.nutrition_decline), color = MaterialTheme.colorScheme.error)
        }
    }
}

private val mealSlots = listOf(
    BackendContracts.NutritionMealSlots.BREAKFAST,
    BackendContracts.NutritionMealSlots.LUNCH,
    BackendContracts.NutritionMealSlots.DINNER,
    BackendContracts.NutritionMealSlots.SNACK
)
