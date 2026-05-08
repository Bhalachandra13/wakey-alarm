package com.wakey.exception

import com.wakey.dto.response.ErrorResponse
import mu.KotlinLogging
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.access.AccessDeniedException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.context.request.WebRequest

private val logger = KotlinLogging.logger {}

@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException::class)
    fun handleResourceNotFound(
        e: ResourceNotFoundException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        logger.warn { "Resource not found: ${e.message}" }
        return ResponseEntity(
            ErrorResponse("NOT_FOUND", e.message ?: "Resource not found"),
            HttpStatus.NOT_FOUND
        )
    }

    @ExceptionHandler(UnauthorisedException::class)
    fun handleUnauthorised(
        e: UnauthorisedException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        logger.warn { "Unauthorized: ${e.message}" }
        return ResponseEntity(
            ErrorResponse("UNAUTHORIZED", e.message ?: "Unauthorized"),
            HttpStatus.UNAUTHORIZED
        )
    }

    @ExceptionHandler(ValidationException::class)
    fun handleValidation(
        e: ValidationException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        logger.warn { "Validation error: ${e.message}" }
        return ResponseEntity(
            ErrorResponse("VALIDATION_ERROR", e.message ?: "Validation failed"),
            HttpStatus.BAD_REQUEST
        )
    }

    @ExceptionHandler(ConflictException::class)
    fun handleConflict(
        e: ConflictException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        logger.warn { "Conflict: ${e.message}" }
        return ResponseEntity(
            ErrorResponse("CONFLICT", e.message ?: "Resource already exists"),
            HttpStatus.CONFLICT
        )
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleMethodArgumentNotValid(
        e: MethodArgumentNotValidException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        val fieldError = e.bindingResult.fieldErrors.firstOrNull()
        val message = fieldError?.defaultMessage ?: "Invalid request parameters"
        logger.warn { "Validation error: $message" }
        return ResponseEntity(
            ErrorResponse("VALIDATION_ERROR", message),
            HttpStatus.BAD_REQUEST
        )
    }

    @ExceptionHandler(AccessDeniedException::class)
    fun handleAccessDenied(
        e: AccessDeniedException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        logger.warn { "Access denied: ${e.message}" }
        return ResponseEntity(
            ErrorResponse("FORBIDDEN", "You don't have permission to access this resource"),
            HttpStatus.FORBIDDEN
        )
    }

    @ExceptionHandler(Exception::class)
    fun handleGenericException(
        e: Exception,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        logger.error(e) { "Unexpected error: ${e.message}" }
        return ResponseEntity(
            ErrorResponse("INTERNAL_ERROR", "An unexpected error occurred"),
            HttpStatus.INTERNAL_SERVER_ERROR
        )
    }
}
