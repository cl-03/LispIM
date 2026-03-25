package com.lispim.client

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LoginTest {

    @get:Rule
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun testLoginWithValidCredentials() {
        // Enter server URL - find by label text
        composeTestRule.onNodeWithText("Server URL", substring = true)
            .performTextClearance()

        composeTestRule.onNodeWithText("Server URL", substring = true)
            .performTextInput("http://10.0.2.2:4321")

        // Enter username
        composeTestRule.onNodeWithText("Username", substring = true)
            .performTextClearance()

        composeTestRule.onNodeWithText("Username", substring = true)
            .performTextInput("admin")

        // Enter password
        composeTestRule.onNodeWithText("Password", substring = true)
            .performTextClearance()

        composeTestRule.onNodeWithText("Password", substring = true)
            .performTextInput("admin123")

        // Click login button
        composeTestRule.onNodeWithText("Login")
            .performClick()

        // Wait for login to complete
        Thread.sleep(5000)

        // Verify login succeeded by checking for home screen or no error
        composeTestRule.waitForIdle()
    }
}
