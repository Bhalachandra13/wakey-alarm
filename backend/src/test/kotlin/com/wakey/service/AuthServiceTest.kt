package com.wakey.service

import com.wakey.dto.request.LoginRequest
import com.wakey.dto.request.RegisterRequest
import com.wakey.exception.ConflictException
import com.wakey.exception.UnauthorisedException
import com.wakey.model.User
import com.wakey.repository.UserRepository
import com.wakey.util.JwtUtil
import io.mockk.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.assertThrows
import org.springframework.security.crypto.password.PasswordEncoder
import java.util.*
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

@DisplayName("AuthService Test Suite")
class AuthServiceTest {

    private val userRepository = mockk<UserRepository>()
    private val passwordEncoder = mockk<PasswordEncoder>()
    private val jwtUtil = mockk<JwtUtil>()

    private val authService = AuthService(userRepository, passwordEncoder, jwtUtil)

    @Test
    @DisplayName("register: valid request creates user and returns tokens")
    fun testRegisterSuccess() {
        val request = RegisterRequest(
            email = "test@example.com",
            password = "password123",
            displayName = "Test User"
        )

        every { userRepository.findByEmail(request.email) } returns null
        every { passwordEncoder.encode(request.password) } returns "hashed_password"
        every { userRepository.save(any()) } answers {
            val user = firstArg<User>()
            user.copy(id = UUID.randomUUID())
        }
        every { jwtUtil.generateAccessToken(any(), any()) } returns "access_token"
        every { jwtUtil.generateRefreshToken(any()) } returns "refresh_token"

        val response = authService.register(request)

        assertNotNull(response)
        assertEquals("access_token", response.accessToken)
        assertEquals("refresh_token", response.refreshToken)
        assertEquals(900, response.expiresIn)
        assertEquals("test@example.com", response.user.email)

        verify { userRepository.save(any()) }
        verify { jwtUtil.generateAccessToken(any(), "test@example.com") }
        verify { jwtUtil.generateRefreshToken(any()) }
    }

    @Test
    @DisplayName("register: existing email throws ConflictException")
    fun testRegisterExistingEmail() {
        val request = RegisterRequest(
            email = "existing@example.com",
            password = "password123",
            displayName = "Test"
        )

        every { userRepository.findByEmail(request.email) } returns User(
            email = "existing@example.com",
            passwordHash = "hash"
        )

        assertThrows<ConflictException> {
            authService.register(request)
        }

        verify(exactly = 0) { userRepository.save(any()) }
    }

    @Test
    @DisplayName("login: valid credentials returns tokens")
    fun testLoginSuccess() {
        val userId = UUID.randomUUID()
        val request = LoginRequest(
            email = "test@example.com",
            password = "password123"
        )

        val user = User(
            id = userId,
            email = "test@example.com",
            passwordHash = "hashed_password"
        )

        every { userRepository.findByEmail(request.email) } returns user
        every { passwordEncoder.matches(request.password, user.passwordHash) } returns true
        every { jwtUtil.generateAccessToken(userId, "test@example.com") } returns "access_token"
        every { jwtUtil.generateRefreshToken(userId) } returns "refresh_token"

        val response = authService.login(request)

        assertNotNull(response)
        assertEquals("access_token", response.accessToken)
        assertEquals("refresh_token", response.refreshToken)
        assertEquals("test@example.com", response.user.email)
    }

    @Test
    @DisplayName("login: invalid password throws UnauthorisedException")
    fun testLoginInvalidPassword() {
        val request = LoginRequest(
            email = "test@example.com",
            password = "wrong_password"
        )

        val user = User(
            email = "test@example.com",
            passwordHash = "hashed_password"
        )

        every { userRepository.findByEmail(request.email) } returns user
        every { passwordEncoder.matches("wrong_password", user.passwordHash) } returns false

        assertThrows<UnauthorisedException> {
            authService.login(request)
        }
    }

    @Test
    @DisplayName("login: non-existent email throws UnauthorisedException")
    fun testLoginNonExistentEmail() {
        val request = LoginRequest(
            email = "nonexistent@example.com",
            password = "password123"
        )

        every { userRepository.findByEmail(request.email) } returns null

        assertThrows<UnauthorisedException> {
            authService.login(request)
        }
    }

    @Test
    @DisplayName("refreshAccessToken: generates new tokens")
    fun testRefreshAccessToken() {
        val userId = UUID.randomUUID()
        val user = User(
            id = userId,
            email = "test@example.com",
            passwordHash = "hash"
        )

        every { userRepository.findById(userId) } returns Optional.of(user)
        every { jwtUtil.generateAccessToken(userId, "test@example.com") } returns "new_access"
        every { jwtUtil.generateRefreshToken(userId) } returns "new_refresh"

        val response = authService.refreshAccessToken(userId)

        assertNotNull(response)
        assertEquals("new_access", response.accessToken)
        assertEquals("new_refresh", response.refreshToken)
    }
}
