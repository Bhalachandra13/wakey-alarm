package com.wakey.service

import com.wakey.dto.request.LoginRequest
import com.wakey.dto.request.RegisterRequest
import com.wakey.dto.response.AuthResponse
import com.wakey.dto.response.UserResponse
import com.wakey.exception.ConflictException
import com.wakey.exception.UnauthorisedException
import com.wakey.model.User
import com.wakey.repository.UserRepository
import com.wakey.util.JwtUtil
import mu.KotlinLogging
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import java.util.*

private val logger = KotlinLogging.logger {}

@Service
class AuthService(
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder,
    private val jwtUtil: JwtUtil
) {

    fun register(request: RegisterRequest): AuthResponse {
        // Check if email already exists
        if (userRepository.findByEmail(request.email) != null) {
            throw ConflictException("Email already registered: ${request.email}")
        }

        // Create new user
        val passwordHash = passwordEncoder.encode(request.password)
        val user = User(
            email = request.email,
            passwordHash = passwordHash,
            displayName = request.displayName
        )

        val savedUser = userRepository.save(user)
        logger.info { "New user registered: ${savedUser.email}" }

        // Generate tokens
        val accessToken = jwtUtil.generateAccessToken(savedUser.id, savedUser.email)
        val refreshToken = jwtUtil.generateRefreshToken(savedUser.id)

        return AuthResponse(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresIn = 900, // 15 minutes
            user = savedUser.toResponse()
        )
    }

    fun login(request: LoginRequest): AuthResponse {
        val user = userRepository.findByEmail(request.email)
            ?: throw UnauthorisedException("Invalid email or password")

        if (!passwordEncoder.matches(request.password, user.passwordHash)) {
            throw UnauthorisedException("Invalid email or password")
        }

        logger.info { "User logged in: ${user.email}" }

        // Generate tokens
        val accessToken = jwtUtil.generateAccessToken(user.id, user.email)
        val refreshToken = jwtUtil.generateRefreshToken(user.id)

        return AuthResponse(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresIn = 900, // 15 minutes
            user = user.toResponse()
        )
    }

    fun refreshAccessToken(userId: UUID): AuthResponse {
        val user = userRepository.findById(userId)
            .orElseThrow { UnauthorisedException("User not found") }

        val accessToken = jwtUtil.generateAccessToken(user.id, user.email)
        val refreshToken = jwtUtil.generateRefreshToken(user.id)

        logger.debug { "Access token refreshed for user: ${user.email}" }

        return AuthResponse(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresIn = 900,
            user = user.toResponse()
        )
    }

    private fun User.toResponse() = UserResponse(
        id = this.id,
        email = this.email,
        displayName = this.displayName,
        snoozeDurationMinutes = this.snoozeDurationMinutes,
        theme = this.theme,
        createdAt = this.createdAt
    )
}
