package com.wakey.util

import io.jsonwebtoken.Jwts
import io.jsonwebtoken.SignatureAlgorithm
import io.jsonwebtoken.security.Keys
import mu.KotlinLogging
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import java.util.*

private val logger = KotlinLogging.logger {}

@Component
class JwtUtil(
    @Value("\${jwt.secret}")
    private val jwtSecret: String,

    @Value("\${jwt.expiration.access}")
    private val accessTokenExpiration: Long,

    @Value("\${jwt.expiration.refresh}")
    private val refreshTokenExpiration: Long
) {

    private val key = Keys.hmacShaKeyFor(jwtSecret.toByteArray())

    fun generateAccessToken(userId: UUID, email: String): String {
        return Jwts.builder()
            .setSubject(userId.toString())
            .claim("email", email)
            .claim("type", "access")
            .setIssuedAt(Date())
            .setExpiration(Date(System.currentTimeMillis() + accessTokenExpiration))
            .signWith(key, SignatureAlgorithm.HS256)
            .compact()
    }

    fun generateRefreshToken(userId: UUID): String {
        return Jwts.builder()
            .setSubject(userId.toString())
            .claim("type", "refresh")
            .setIssuedAt(Date())
            .setExpiration(Date(System.currentTimeMillis() + refreshTokenExpiration))
            .signWith(key, SignatureAlgorithm.HS256)
            .compact()
    }

    fun validateToken(token: String): Boolean {
        return try {
            Jwts.parserBuilder()
                .setSigningKey(key)
                .build()
                .parseClaimsJws(token)
            true
        } catch (e: Exception) {
            logger.warn { "Invalid token: ${e.message}" }
            false
        }
    }

    fun getUserIdFromToken(token: String): UUID? {
        return try {
            val claims = Jwts.parserBuilder()
                .setSigningKey(key)
                .build()
                .parseClaimsJws(token)
                .body

            UUID.fromString(claims.subject)
        } catch (e: Exception) {
            logger.warn { "Failed to extract user ID from token: ${e.message}" }
            null
        }
    }

    fun getEmailFromToken(token: String): String? {
        return try {
            val claims = Jwts.parserBuilder()
                .setSigningKey(key)
                .build()
                .parseClaimsJws(token)
                .body

            claims.get("email", String::class.java)
        } catch (e: Exception) {
            logger.warn { "Failed to extract email from token: ${e.message}" }
            null
        }
    }

    fun isTokenExpired(token: String): Boolean {
        return try {
            val claims = Jwts.parserBuilder()
                .setSigningKey(key)
                .build()
                .parseClaimsJws(token)
                .body

            claims.expiration.before(Date())
        } catch (e: Exception) {
            true
        }
    }
}
