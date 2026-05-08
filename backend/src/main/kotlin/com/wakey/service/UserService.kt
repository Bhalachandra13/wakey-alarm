package com.wakey.service

import com.wakey.dto.request.UserPreferencesRequest
import com.wakey.dto.response.UserResponse
import com.wakey.exception.ResourceNotFoundException
import com.wakey.model.User
import com.wakey.repository.UserRepository
import mu.KotlinLogging
import org.springframework.stereotype.Service
import java.util.*

private val logger = KotlinLogging.logger {}

@Service
class UserService(
    private val userRepository: UserRepository
) {

    fun getUserById(userId: UUID): User {
        return userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User not found with ID: $userId") }
    }

    fun getUserByEmail(email: String): User? {
        return userRepository.findByEmail(email)
    }

    fun createUser(user: User): User {
        return userRepository.save(user)
    }

    fun updateUserPreferences(userId: UUID, request: UserPreferencesRequest): UserResponse {
        val user = getUserById(userId)

        request.snoozeDuration?.let {
            if (it in 1..30) {
                // Note: in real app, we'd update user properties
                // user.snoozeDurationMinutes = it
                logger.debug { "Updating snooze duration for user $userId to $it" }
            }
        }

        request.theme?.let {
            // user.theme = it
            logger.debug { "Updating theme for user $userId to $it" }
        }

        userRepository.save(user)
        return user.toResponse()
    }

    fun deleteUser(userId: UUID) {
        if (!userRepository.existsById(userId)) {
            throw ResourceNotFoundException("User not found with ID: $userId")
        }
        userRepository.deleteById(userId)
        logger.info { "User deleted: $userId" }
    }

    fun updateFcmToken(userId: UUID, fcmToken: String): User {
        val user = getUserById(userId)
        user.fcmToken = fcmToken
        return userRepository.save(user)
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
