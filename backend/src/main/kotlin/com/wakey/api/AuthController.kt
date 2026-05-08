package com.wakey.api

import com.wakey.dto.request.FcmTokenRequest
import com.wakey.dto.request.LoginRequest
import com.wakey.dto.request.RegisterRequest
import com.wakey.service.AuthService
import com.wakey.service.UserService
import jakarta.validation.Valid
import mu.KotlinLogging
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.*

private val logger = KotlinLogging.logger {}

@RestController
@RequestMapping("/api/v1/auth")
@CrossOrigin(origins = ["*"])
class AuthController(
    private val authService: AuthService,
    private val userService: UserService
) {

    @PostMapping("/register")
    fun register(@Valid @RequestBody request: RegisterRequest) =
        ResponseEntity.status(HttpStatus.CREATED).body(authService.register(request))

    @PostMapping("/login")
    fun login(@Valid @RequestBody request: LoginRequest) =
        ResponseEntity.ok(authService.login(request))

    @PostMapping("/refresh")
    fun refreshToken(authentication: Authentication): ResponseEntity<*> {
        val userId = UUID.fromString(authentication.principal as String)
        return ResponseEntity.ok(authService.refreshAccessToken(userId))
    }

    @PostMapping("/logout")
    fun logout(authentication: Authentication): ResponseEntity<Map<String, String>> {
        logger.info { "User logged out: ${authentication.principal}" }
        return ResponseEntity.ok(mapOf("message" to "Logged out successfully"))
    }

    @PutMapping("/fcm-token")
    fun updateFcmToken(
        authentication: Authentication,
        @Valid @RequestBody request: FcmTokenRequest
    ) = ResponseEntity.ok().apply {
        val userId = UUID.fromString(authentication.principal as String)
        userService.updateFcmToken(userId, request.fcmToken)
        logger.debug { "FCM token updated for user: $userId" }
    }.build()
}
