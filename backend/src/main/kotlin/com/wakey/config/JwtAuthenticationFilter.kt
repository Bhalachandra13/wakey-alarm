package com.wakey.config

import com.wakey.util.JwtUtil
import mu.KotlinLogging
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse

private val logger = KotlinLogging.logger {}

@Component
class JwtAuthenticationFilter(private val jwtUtil: JwtUtil) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain
    ) {
        try {
            val token = extractTokenFromRequest(request)

            if (token != null && jwtUtil.validateToken(token)) {
                val userId = jwtUtil.getUserIdFromToken(token)

                if (userId != null) {
                    val authentication = UsernamePasswordAuthenticationToken(
                        userId.toString(),
                        null,
                        emptyList()
                    )
                    SecurityContextHolder.getContext().authentication = authentication
                }
            }
        } catch (e: Exception) {
            logger.debug { "JWT filter error: ${e.message}" }
        }

        filterChain.doFilter(request, response)
    }

    private fun extractTokenFromRequest(request: HttpServletRequest): String? {
        val bearerToken = request.getHeader("Authorization")
        if (bearerToken?.startsWith("Bearer ") == true) {
            return bearerToken.substring(7)
        }
        return null
    }
}
