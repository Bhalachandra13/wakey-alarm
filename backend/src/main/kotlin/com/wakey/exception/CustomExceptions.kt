package com.wakey.exception

class ResourceNotFoundException(message: String) : RuntimeException(message)

class UnauthorisedException(message: String) : RuntimeException(message)

class ValidationException(message: String) : RuntimeException(message)

class ConflictException(message: String) : RuntimeException(message)

class InternalServerException(message: String) : RuntimeException(message)
