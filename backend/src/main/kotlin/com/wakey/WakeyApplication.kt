package com.wakey

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling

@SpringBootApplication
@EnableScheduling
class WakeyApplication

fun main(args: Array<String>) {
    runApplication<WakeyApplication>(*args)
}
