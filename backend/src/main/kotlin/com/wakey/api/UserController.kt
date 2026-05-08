package com.wakey.api

import com.wakey.dto.request.UserPreferencesRequest
import com.wakey.dto.response.UserResponse
import com.wakey.service.UserService
import jakarta.validation.Valid
import mu.KotlinLogging
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.*

private val logger = KotlinLogging.logger {}

@RestController
@RequestMapping("/api/v1/users")
@CrossOrigin(origins = ["*"])
class UserController(private val userService: UserService) {

    @GetMapping("/me")
    fun getCurrentUser(authentication: Authentication): ResponseEntity<UserResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val user = userService.getUserById(userId)
        return ResponseEntity.ok(
            UserResponse(
                id = user.id,
                email = user.email,
                displayName = user.displayName,
                snoozeDurationMinutes = user.snoozeDurationMinutes,
                theme = user.theme,
                createdAt = user.createdAt
            )
        )
    }

    @PutMapping("/me/preferences")
    fun updateUserPreferences(
        authentication: Authentication,
        @Valid @RequestBody request: UserPreferencesRequest
    ): ResponseEntity<UserResponse> {
        val userId = UUID.fromString(authentication.principal as String)
        val updated = userService.updateUserPreferences(userId, request)
        logger.info { "User preferences updated: $userId" }
        return ResponseEntity.ok(updated)
    }

    @DeleteMapping("/me")
    fun deleteCurrentUser(authentication: Authentication): ResponseEntity<Void> {
        val userId = UUID.fromString(authentication.principal as String)
        userService.deleteUser(userId)
        logger.info { "User account deleted: $userId" }
        return ResponseEntity.noContent().build()
    }
}
