package com.wakey.dto.request

data class RegisterRequest(
    val email: String,
    val password: String,
    val displayName: String?
)

data class LoginRequest(
    val email: String,
    val password: String
)

data class RefreshTokenRequest(
    val refreshToken: String
)

data class FcmTokenRequest(
    val fcmToken: String
)

data class UserPreferencesRequest(
    val snoozeDuration: Int? = null,
    val theme: String? = null,
    val defaultRingtone: String? = null
)
