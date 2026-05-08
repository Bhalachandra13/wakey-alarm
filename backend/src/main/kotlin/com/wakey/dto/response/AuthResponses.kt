package com.wakey.dto.response

import java.time.LocalDateTime
import java.util.*

data class AuthResponse(
    val accessToken: String,
    val refreshToken: String,
    val expiresIn: Long,
    val user: UserResponse
)

data class UserResponse(
    val id: UUID,
    val email: String,
    val displayName: String?,
    val snoozeDurationMinutes: Int,
    val theme: String,
    val createdAt: LocalDateTime
)

data class ErrorResponse(
    val code: String,
    val message: String,
    val timestamp: LocalDateTime = LocalDateTime.now()
)
