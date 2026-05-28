package com.lilru.liftr.data

/**
 * Single source of truth for Supabase table/view/rpc names used by Liftr clients.
 *
 * Goal: avoid typo regressions and keep Android aligned with iOS contracts.
 */
object BackendContracts {
    object Tables {
        const val ACHIEVEMENTS = "achievements"
        const val AVATARS = "avatars"
        const val BASKETBALL_SESSION_STATS = "basketball_session_stats"
        const val CARDIO_SESSIONS = "cardio_sessions"
        const val CARDIO_SESSION_STATS = "cardio_session_stats"
        const val CHALLENGE_TEMPLATES = "challenge_templates"
        const val CHALLENGE_INSTANCES = "challenge_instances"
        const val CHALLENGE_CLAIMS = "challenge_claims"
        const val COMPETITIONS = "competitions"
        const val COMPETITION_BLOCKS = "competition_blocks"
        const val COMPETITION_GOALS = "competition_goals"
        const val COMPETITION_WORKOUTS = "competition_workouts"
        const val CONTACT_MESSAGES = "contact_messages"
        const val CONVERSATIONS = "conversations"
        const val CONVERSATION_PARTICIPANTS = "conversation_participants"
        const val CONVERSATION_READS = "conversation_reads"
        const val EXERCISES = "exercises"
        const val EXERCISE_SETS = "exercise_sets"
        const val FEATURE_REQUESTS = "feature_requests"
        const val FEATURE_REQUEST_COMMENTS = "feature_request_comments"
        const val FEATURE_REQUEST_VOTES = "feature_request_votes"
        const val FOLLOWS = "follows"
        const val FOOTBALL_SESSION_STATS = "football_session_stats"
        const val HANDBALL_SESSION_STATS = "handball_session_stats"
        const val HOCKEY_SESSION_STATS = "hockey_session_stats"
        const val HYROX_SESSION_EXERCISES = "hyrox_session_exercises"
        const val HYROX_SESSION_STATS = "hyrox_session_stats"
        const val HYROX_ROUTINE_FOLDERS = "hyrox_routine_folders"
        const val HYROX_ROUTINES = "hyrox_routines"
        const val HYROX_ROUTINE_EXERCISES = "hyrox_routine_exercises"
        const val LEVEL_THRESHOLDS = "level_thresholds"
        const val MESSAGES = "messages"
        const val MESSAGE_ATTACHMENTS = "message_attachments"
        const val MESSAGE_REACTIONS = "message_reactions"
        const val NOTIFICATIONS = "notifications"
        const val NUTRITION_INGREDIENTS = "nutrition_ingredients"
        const val NUTRITION_RECIPES = "nutrition_recipes"
        const val NUTRITION_RECIPE_INGREDIENTS = "nutrition_recipe_ingredients"
        const val NUTRITION_DIARY_LOGS = "nutrition_diary_logs"
        const val BODY_WEIGHT_ENTRIES = "body_weight_entries"
        const val PROFILES = "profiles"
        const val USER_NOTIFICATION_SETTINGS = "user_notification_settings"
        const val USER_SUBSCRIPTIONS = "user_subscriptions"
        const val RACKET_SESSION_STATS = "racket_session_stats"
        const val RUGBY_SESSION_STATS = "rugby_session_stats"
        const val SKI_SESSION_STATS = "ski_session_stats"
        const val SEGMENTS = "segments"
        const val SEGMENT_EFFORTS = "segment_efforts"
        const val TERRITORY_CELLS = "territory_cells"
        const val TERRITORY_CAPTURE_EVENTS = "territory_capture_events"
        const val SPORT_SESSIONS = "sport_sessions"
        const val STRENGTH_ROUTINES = "strength_routines"
        const val STRENGTH_ROUTINE_EXERCISES = "strength_routine_exercises"
        const val STRENGTH_ROUTINE_FOLDERS = "strength_routine_folders"
        const val STRENGTH_ROUTINE_SETS = "strength_routine_sets"
        const val USER_ACHIEVEMENTS = "user_achievements"
        const val USER_FAVORITE_EXERCISES = "user_favorite_exercises"
        const val USER_FAVORITE_NUTRITION_INGREDIENTS = "user_favorite_nutrition_ingredients"
        const val USER_FAVORITE_NUTRITION_RECIPES = "user_favorite_nutrition_recipes"
        const val VOLLEYBALL_SESSION_STATS = "volleyball_session_stats"
        const val WEEKLY_GOALS = "weekly_goals"
        const val WEEKLY_GOAL_RESULTS = "weekly_goal_results"
        const val WORKOUTS = "workouts"
        const val WORKOUT_COMMENTS = "workout_comments"
        const val WORKOUT_COMMENT_LIKES = "workout_comment_likes"
        const val WORKOUT_EXERCISES = "workout_exercises"
        const val WORKOUT_LIKES = "workout_likes"
        const val WORKOUT_PARTICIPANTS = "workout_participants"
        const val WORKOUT_SCORES = "workout_scores"
        const val XP_EVENTS = "xp_events"
    }

    object Views {
        const val VW_FEATURE_REQUEST_COMMENTS = "vw_feature_request_comments"
        const val VW_FEATURE_REQUESTS = "vw_feature_requests"
        const val VW_PROFILE_COUNTS = "vw_profile_counts"
        const val VW_SPORT_SESSION_FULL = "vw_sport_session_full"
        const val VW_USER_PRS = "vw_user_prs"
        const val VW_WORKOUT_VOLUME = "vw_workout_volume"
    }

    object Rpc {
        const val ADD_WORKOUT_PARTICIPANT = "add_workout_participant"
        const val CAN_COMPARE_WORKOUT_V1 = "can_compare_workout_v1"
        const val CHECK_AND_UNLOCK_ACHIEVEMENTS_FOR = "check_and_unlock_achievements_for"
        const val CLEAR_USER_SEARCH_RECENT = "clear_user_search_recent"
        const val CREATE_CARDIO_WORKOUT_V2 = "create_cardio_workout_v2"
        const val CREATE_LINKED_STRENGTH_WORKOUT_COPY = "create_linked_strength_workout_copy"
        const val CREATE_SPORT_WORKOUT_V2 = "create_sport_workout_v2"
        const val CREATE_STRENGTH_WORKOUT = "create_strength_workout"
        const val DELETE_MY_ACCOUNT = "delete_my_account"
        const val FETCH_DUAL_LINKED_STRENGTH_WORKOUT_DATA = "fetch_dual_linked_strength_workout_data"
        const val FINISH_STRENGTH_WORKOUT_V1 = "finish_strength_workout_v1"
        const val GET_BEST_WORKOUTS_LEADERBOARD_V1 = "get_best_workouts_leaderboard_v1"
        const val GET_CALORIES_LEADERBOARD_V1 = "get_calories_leaderboard_v1"
        const val GET_CARDIO_DISTANCE_LEADERBOARD_V1 = "get_cardio_distance_leaderboard_v1"
        const val GET_DUELS_WON_LEADERBOARD_V1 = "get_duels_won_leaderboard_v1"
        const val GET_EXERCISES_USAGE = "get_exercises_usage"
        const val GET_GOAL_STATS = "get_goal_stats"
        const val GET_GOALS_COMPLETED_LEADERBOARD_V1 = "get_goals_completed_leaderboard_v1"
        const val GET_SPORT_MATCH_WINS_LEADERBOARD_V1 = "get_sport_match_wins_leaderboard_v1"
        const val GET_CARDIO_ELEVATION_LEADERBOARD_V1 = "get_cardio_elevation_leaderboard_v1"
        const val GET_CARDIO_DURATION_LEADERBOARD_V1 = "get_cardio_duration_leaderboard_v1"
        const val GET_CARDIO_BEST_PACE_LEADERBOARD_V1 = "get_cardio_best_pace_leaderboard_v1"
        const val GET_STRENGTH_TOTAL_REPS_LEADERBOARD_V1 = "get_strength_total_reps_leaderboard_v1"
        const val GET_STRENGTH_TOTAL_SETS_LEADERBOARD_V1 = "get_strength_total_sets_leaderboard_v1"
        const val GET_STRENGTH_MAX_SET_WEIGHT_LEADERBOARD_V1 = "get_strength_max_set_weight_leaderboard_v1"
        const val GET_SPORT_DURATION_LEADERBOARD_V1 = "get_sport_duration_leaderboard_v1"
        const val GET_SPORT_WIN_RATE_LEADERBOARD_V1 = "get_sport_win_rate_leaderboard_v1"
        const val GET_STRENGTH_VOLUME_LEADERBOARD_V1 = "get_strength_volume_leaderboard_v1"
        const val GET_PERIOD_TRAINING_COMPARE_V1 = "get_period_training_compare_v1"
        const val GET_LEADERBOARD_V1 = "get_leaderboard_v1"
        const val GET_LEVEL_LEADERBOARD_V1 = "get_level_leaderboard_v1"
        const val GET_WORKOUT_LIKES_RECEIVED_LEADERBOARD_V1 = "get_workout_likes_received_leaderboard_v1"
        const val GET_WORKOUT_COMMENTS_RECEIVED_LEADERBOARD_V1 = "get_workout_comments_received_leaderboard_v1"
        const val GET_GROUP_WORKOUT_SESSIONS_LEADERBOARD_V1 = "get_group_workout_sessions_leaderboard_v1"
        const val GET_ACHIEVEMENTS_UNLOCKED_PERIOD_LEADERBOARD_V1 = "get_achievements_unlocked_period_leaderboard_v1"
        const val GET_CHALLENGE_PODIUMS_PERIOD_LEADERBOARD_V1 = "get_challenge_podiums_period_leaderboard_v1"
        const val GET_HYROX_BEST_OFFICIAL_TIME_LEADERBOARD_V1 = "get_hyrox_best_official_time_leaderboard_v1"
        const val GET_FOOTBALL_GOALS_LEADERBOARD_V1 = "get_football_goals_leaderboard_v1"
        const val GET_SKI_DISTANCE_LEADERBOARD_V1 = "get_ski_distance_leaderboard_v1"
        const val GET_USER_ACHIEVEMENTS = "get_user_achievements"
        const val GET_USER_PRS = "get_user_prs"
        const val GET_USER_PREMIUM_STATUS_V1 = "get_user_premium_status_v1"
        const val GET_USER_LEVEL = "get_user_level"
        const val GET_WEEKLY_GOAL_RECOMMENDATION = "get_weekly_goal_recommendation"
        const val GET_DAILY_NUTRITION_RECOMMENDATION_V1 = "get_daily_nutrition_recommendation_v1"
        const val GET_NUTRITION_MONTH_BALANCE_V1 = "get_nutrition_month_balance_v1"
        const val GET_SMART_NUTRITION_RECOMMENDATION_V1 = "get_smart_nutrition_recommendation_v1"
        const val LIST_COMPARABLE_WORKOUTS_V1 = "list_comparable_workouts_v1"
        const val LIST_COMPARE_AVERAGE_POOL_V1 = "list_compare_average_pool_v1"
        const val PLAN_STRENGTH_SQUAD_PROGRAMS = "plan_strength_squad_programs"
        const val PRECHECK_SIGNUP = "precheck_signup"
        const val RECOMPUTE_WEEKLY_GOAL_RESULTS = "recompute_weekly_goal_results"
        const val RECORD_SEARCH = "record_search"
        const val REVIEW_COMPETITION_WORKOUT = "review_competition_workout"
        const val SUBMIT_WORKOUT_TO_COMPETITION = "submit_workout_to_competition"
        const val TRENDING_SEARCH_QUERIES_24H = "trending_search_queries_24h"
        const val UPDATE_SPORT_WORKOUT_V2 = "update_sport_workout_v2"
        const val UPSERT_BODY_WEIGHT_ENTRY = "upsert_body_weight_entry"
        const val USER_SEARCH_RECENT_LIST = "user_search_recent_list"
        const val CREATE_SEGMENT_FROM_WORKOUT_V1 = "create_segment_from_workout_v1"
        const val UPDATE_MY_SEGMENT_NAME_V1 = "update_my_segment_name_v1"
        const val DELETE_MY_SEGMENT_V1 = "delete_my_segment_v1"
        const val GET_SEGMENT_DETAIL_V1 = "get_segment_detail_v1"
        const val GET_SEGMENT_LEADERBOARD_V1 = "get_segment_leaderboard_v1"
        const val LIST_SEGMENTS_NEAR_V1 = "list_segments_near_v1"
        const val LIST_MY_SEGMENTS_V1 = "list_my_segments_v1"
        const val LIST_SEGMENTS_POPULARITY_LEADERBOARD_V1 = "list_segments_popularity_leaderboard_v1"
        const val SEARCH_SEGMENTS_V1 = "search_segments_v1"
        const val MATCH_SEGMENT_EFFORTS_FOR_WORKOUT_V1 = "match_segment_efforts_for_workout_v1"
        const val APPLY_TERRITORY_CAPTURE_V1 = "apply_territory_capture_v1"
        const val PREVIEW_TERRITORY_CAPTURE_V1 = "preview_territory_capture_v1"
        const val GET_WORKOUT_TERRITORY_DISPLAY_V1 = "get_workout_territory_display_v1"
        const val GET_TERRITORY_MAP_V1 = "get_territory_map_v1"
        const val GET_RECOMMENDED_EXPANSION_CELLS_V1 = "get_recommended_expansion_cells_v1"
        const val GET_HOME_FEED_PAGE_V1 = "get_home_feed_page_v1"
        const val GET_MY_TERRITORY_SUMMARY_V1 = "get_my_territory_summary_v1"
        const val GET_TERRITORY_SHARE_LEADERBOARD_V1 = "get_territory_share_leaderboard_v1"
        const val LIST_TERRITORY_CITY_REGIONS_V1 = "list_territory_city_regions_v1"
        const val GET_TERRITORY_CITY_SHARE_LEADERBOARD_V1 = "get_territory_city_share_leaderboard_v1"
        const val GET_TERRITORY_TOTAL_CELLS_LEADERBOARD_V1 = "get_territory_total_cells_leaderboard_v1"
        const val BACKFILL_MY_TERRITORY_CAPTURES_V1 = "backfill_my_territory_captures_v1"
        const val LIST_MY_TERRITORY_RECENT_TAKEOVERS_V1 = "list_my_territory_recent_takeovers_v1"
        const val GET_TERRITORY_SUMMARY_V1 = "get_territory_summary_v1"
        const val LIST_USER_TERRITORY_TOP_CITIES_V1 = "list_user_territory_top_cities_v1"
        const val LIST_TERRITORY_RECENT_TAKEOVERS_V1 = "list_territory_recent_takeovers_v1"
        const val LIST_WORKOUT_TERRITORY_TAKEOVERS_V1 = "list_workout_territory_takeovers_v1"
        const val BACKFILL_TERRITORY_MUNICIPALITY_ASSIGNMENTS_V1 = "backfill_territory_municipality_assignments_v1"
        const val LIST_ACTIVE_CHALLENGES_V1 = "list_active_challenges_v1"
        const val GET_CHALLENGE_INSTANCE_DETAIL_V1 = "get_challenge_instance_detail_v1"
        const val GET_CHALLENGE_INSTANCE_LEADERBOARD_V1 = "get_challenge_instance_leaderboard_v1"
        const val GET_CHALLENGE_MY_PROGRESS_V1 = "get_challenge_my_progress_v1"
        const val GET_CONVERSATIONS_OVERVIEW = "get_conversations_overview"
        const val GET_MESSAGES = "get_messages"
        const val START_DIRECT_CONVERSATION = "start_direct_conversation"
        const val SEND_MESSAGE = "send_message"
        const val START_WORKOUT_V1 = "start_workout_v1"
        const val MARK_CONVERSATION_READ = "mark_conversation_read"
        const val CLEAR_CONVERSATION = "clear_conversation"
        const val SET_CONVERSATION_MUTED = "set_conversation_muted"
        const val TOGGLE_MESSAGE_REACTION = "toggle_message_reaction"
        const val EDIT_MESSAGE = "edit_message"
        const val DELETE_MESSAGE = "delete_message"
        const val CLONE_SHARED_INGREDIENT = "clone_shared_ingredient"
        const val CLONE_SHARED_RECIPE = "clone_shared_recipe"
    }

    object ProfileColumns {
        const val BASE_CALORIES_TARGET = "base_calories_target"
        const val BASE_CALORIES_TARGET_IS_MANUAL = "base_calories_target_is_manual"
    }

    object NutritionMetabolism {
        const val FALLBACK_KCAL_FEMALE = 1500
        const val FALLBACK_KCAL_MALE = 1900
        const val FALLBACK_KCAL_NEUTRAL = 1700
        const val MIN_KCAL = 800
        const val MAX_KCAL = 6000
        const val IMPUTED_AGE_YEARS = 30
        const val DEFAULT_HEIGHT_MALE_CM = 175.0
        const val DEFAULT_HEIGHT_FEMALE_CM = 162.0
        const val DEFAULT_WEIGHT_MALE_KG = 75.0
        const val DEFAULT_WEIGHT_FEMALE_KG = 60.0
        const val MULTIPLIER_LOW = 1.2
        const val MULTIPLIER_MODERATE = 1.375
        const val MULTIPLIER_ACTIVE = 1.55
        const val MULTIPLIER_VERY_ACTIVE = 1.725
        const val WEIGHT_FACTOR = 10.0
        const val HEIGHT_FACTOR = 6.25
        const val AGE_FACTOR = 5.0
        const val MALE_OFFSET = 5.0
        const val FEMALE_OFFSET = -161.0
        const val UNISEX_OFFSET = -80.0
    }

    object NutritionColumns {
        const val ID = "id"
        const val USER_ID = "user_id"
        const val NAME = "name"
        const val DESCRIPTION = "description"
        const val LOG_DATE = "log_date"
        const val MEAL_SLOT = "meal_slot"
        const val INGREDIENT_ID = "ingredient_id"
        const val RECIPE_ID = "recipe_id"
        const val QUANTITY_G = "quantity_g"
        const val CALORIES_PER_100G = "calories_per_100g"
        const val PROTEIN_PER_100G = "protein_per_100g"
        const val CARBS_PER_100G = "carbs_per_100g"
        const val FAT_PER_100G = "fat_per_100g"
        const val SATURATED_FAT_PER_100G = "saturated_fat_per_100g"
        const val SUGARS_PER_100G = "sugars_per_100g"
        const val FIBER_PER_100G = "fiber_per_100g"
        const val SODIUM_MG_PER_100G = "sodium_mg_per_100g"
        const val IS_PUBLIC = "is_public"
        const val WEIGHT_G = "weight_g"
        const val CREATED_AT = "created_at"
    }

    object NutritionRpcKeys {
        const val BASE_CALORIES_TARGET = "base_calories_target"
        const val TOTAL_CALORIES_CONSUMED = "total_calories_consumed"
        const val TOTAL_CALORIES_BURNED_ACTIVE = "total_calories_burned_active"
        const val REMAINING_CALORIES = "remaining_calories"
        const val NET_CALORIES_BALANCE = "net_calories_balance"
        const val TOTAL_PROTEIN_G_CONSUMED = "total_protein_g_consumed"
        const val TOTAL_CARBS_G_CONSUMED = "total_carbs_g_consumed"
        const val TOTAL_FAT_G_CONSUMED = "total_fat_g_consumed"
        const val TOTAL_SATURATED_FAT_G_CONSUMED = "total_saturated_fat_g_consumed"
        const val TOTAL_SUGARS_G_CONSUMED = "total_sugars_g_consumed"
        const val TOTAL_FIBER_G_CONSUMED = "total_fiber_g_consumed"
        const val TOTAL_SODIUM_MG_CONSUMED = "total_sodium_mg_consumed"
        const val RECOMMENDATION_TEXT = "recommendation_text"
        const val ALERTS = "alerts"
        const val AVG_DAILY_CONSUMED_KCAL = "avg_daily_consumed_kcal"
        const val AVG_DAILY_BURNED_KCAL = "avg_daily_burned_kcal"
        const val AVG_DAILY_ENERGY_OUT = "avg_daily_energy_out"
        const val AVG_DAILY_REMAINING_BUDGET = "avg_daily_remaining_budget"
    }

    object NutritionDisplayTargets {
        const val CALORIES_KCAL = NutritionMetabolism.FALLBACK_KCAL_NEUTRAL.toDouble()
        const val PROTEIN_G = 150.0
        const val CARBS_G = 250.0
        const val FAT_G = 70.0
        const val SATURATED_FAT_G = 20.0
        const val SUGARS_G = 50.0
        const val FIBER_G = 28.0
        const val SODIUM_MG = 2300.0
    }

    object NutritionMealSlots {
        const val BREAKFAST = "Breakfast"
        const val LUNCH = "Lunch"
        const val DINNER = "Dinner"
        const val SNACK = "Snack"
    }

    object NutritionIngredientScopes {
        const val PUBLIC_OR_OWN_FILTER = "is_public.eq.true,user_id.eq.%s"
    }

    object NutritionRecipeScopes {
        const val SYSTEM_OR_OWN_FILTER = "user_id.is.null,user_id.eq.%s"
    }

    /** Supabase Edge Functions (invoke con JWT de sesión), alineado con [Liftr/ProfileView.swift]. */
    object EdgeFunctions {
        const val DELETE_AUTH_USER = "delete-auth-user"
        const val PROCESS_BILLING_WEBHOOK = "process-billing-webhook"
        const val PROCESS_APPLE_APP_STORE_NOTIFICATION = "process-apple-app-store-notification"
        const val RESOLVE_TERRITORY_MUNICIPALITY = "resolve-territory-municipality"
    }
}
