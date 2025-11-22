package com.ghostty.android

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.viewinterop.AndroidView
import com.ghostty.android.renderer.GhosttyGLSurfaceView
import com.ghostty.android.terminal.GhosttyBridge
import com.ghostty.android.terminal.TerminalSession
import com.ghostty.android.testing.TestRunner
import com.ghostty.android.testing.TestSuite
import com.ghostty.android.ui.InputToolbar
import com.ghostty.android.ui.theme.GhosttyTheme

class MainActivity : ComponentActivity() {

    private lateinit var ghosttyBridge: GhosttyBridge
    private lateinit var terminalSession: TerminalSession
    private var glSurfaceView: GhosttyGLSurfaceView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on while terminal is active
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Initialize Ghostty bridge
        ghosttyBridge = GhosttyBridge.getInstance()
        // TODO: Enable when JNI key encoder is implemented
        // ghosttyBridge.createKeyEncoder()
        // Create terminal session
        terminalSession = TerminalSession()
        // TestRunner will be created when GL surface view is initialized
        var testId = intent.getStringExtra("TEST_ID")
        if (testId == null) {
            testId = "basic_colors_fg"
        }

        android.util.Log.i("MainActivity", "onCreate: testId=$testId")

        enableEdgeToEdge()

        setContent {
            // Use remember and mutableStateOf so the Composable recomposes when testRunner is initialized
            val testRunnerState = remember { mutableStateOf<TestRunner?>(null) }

            GhosttyTheme {
                    TestModeScreen(
                        testRunner = testRunnerState.value,
                        onExitTestMode = {},
                        onGLSurfaceViewCreated = { view ->
                            glSurfaceView = view
                            // Initialize test runner with the renderer from the GL surface view
                            if (testRunnerState.value == null) {
                                testRunnerState.value = TestRunner(view.getRenderer(), applicationContext)
                            }
                        },
                        testId = testId,
                    )
                }
            }
        }

    override fun onPause() {
        super.onPause()
        // Pause the GL rendering thread
        glSurfaceView?.onPauseView()
    }

    override fun onResume() {
        super.onResume()
        // Resume the GL rendering thread
        glSurfaceView?.onResumeView()
    }

    override fun onDestroy() {
        super.onDestroy()
        terminalSession.stop()
        ghosttyBridge.cleanup()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TerminalScreen(
    session: TerminalSession,
    onKeyPress: (String) -> Unit,
    onEnterTestMode: () -> Unit,
    onGLSurfaceViewCreated: (GhosttyGLSurfaceView) -> Unit
) {
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Ghostty Terminal") },
                actions = {
                    // Test mode toggle button (debug only)
                    IconButton(onClick = onEnterTestMode) {
                        Text("TEST", style = MaterialTheme.typography.labelSmall)
                    }
                }
            )
        },
        bottomBar = {
            InputToolbar(
                onKeyPress = onKeyPress,
                onShowKeyboard = {
                    keyboardController?.show()
                }
            )
        }
    ) { paddingValues ->
        // Use AndroidView to embed the native OpenGL surface view
        AndroidView(
            factory = { context ->
                GhosttyGLSurfaceView(context).also { view ->
                    // Notify the activity that the view has been created
                    onGLSurfaceViewCreated(view)

                    // Set up terminal size (will be calculated based on view size)
                    // For now, use default terminal size
                    view.setTerminalSize(80, 24)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TestModeScreen(
    testRunner: TestRunner?,
    onExitTestMode: () -> Unit,
    onGLSurfaceViewCreated: (GhosttyGLSurfaceView) -> Unit,
    testId: String?,
    onTestsStarted: () -> Unit = {}
) {
    android.util.Log.i("TestModeScreen", "Compose: testRunner=$testRunner, testId=$testId")

    val isRunning by testRunner?.isRunning?.collectAsState() ?: remember { mutableStateOf(false) }
    val testResults by testRunner?.testResults?.collectAsState() ?: remember { mutableStateOf(emptyList()) }
    val currentTest by testRunner?.currentTest?.collectAsState() ?: remember { mutableStateOf(null) }
    val currentTestIndex by testRunner?.currentTestIndexFlow?.collectAsState() ?: remember { mutableStateOf(0) }
    val totalTests by testRunner?.totalTests?.collectAsState() ?: remember { mutableStateOf(0) }

    // Initialize tests when both testRunner and testId are available
    if (testRunner != null && testId != null) {
        LaunchedEffect(testId, testRunner) {
            android.util.Log.i("TestModeScreen", "LaunchedEffect: initializing tests testId=$testId")
            testRunner.initializeTestById(testId)
            onTestsStarted()
        }
    } else {
        android.util.Log.w("TestModeScreen", "Waiting for initialization: testRunner=$testRunner, testId=$testId")
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Visual Regression Tests") },
                actions = {
                    IconButton(onClick = onExitTestMode, enabled = !isRunning) {
                        Text("EXIT", style = MaterialTheme.typography.labelSmall)
                    }
                }
            )
        },
        bottomBar = {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding(),
                tonalElevation = 3.dp
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Test progress indicator
                    if (totalTests > 0) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Text(
                                text = "Test ${currentTestIndex + 1} of $totalTests",
                                style = MaterialTheme.typography.titleSmall
                            )
                        }
                    }

                    // Navigation buttons
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Button(
                            onClick = { testRunner?.previousTest() },
                            enabled = !isRunning && testRunner?.hasPreviousTest() == true,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Previous")
                        }
                        Button(
                            onClick = { testRunner?.nextTest() },
                            enabled = !isRunning && testRunner?.hasNextTest() == true,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Next")
                        }
                    }
                }
            }
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Terminal view (takes most of the space)
            Box(modifier = Modifier.weight(1f)) {
                AndroidView(
                    factory = { context ->
                        GhosttyGLSurfaceView(context).also { view ->
                            onGLSurfaceViewCreated(view)
                            view.setTerminalSize(80, 24)
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )

                // Overlay showing current test
                currentTest?.let { test ->
                    Surface(
                        modifier = Modifier
                            .align(androidx.compose.ui.Alignment.TopEnd)
                            .padding(16.dp),
                        color = MaterialTheme.colorScheme.primaryContainer,
                        shape = MaterialTheme.shapes.small
                    ) {
                        Text(
                            text = "Running: ${test.id}",
                            modifier = Modifier.padding(8.dp),
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }

            // Test results summary
            Surface(
                modifier = Modifier.fillMaxWidth(),
                tonalElevation = 2.dp
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Results: ${testResults.size} tests",
                        style = MaterialTheme.typography.titleSmall
                    )
                    if (testResults.isNotEmpty()) {
                        val passed = testResults.count { it.status == com.ghostty.android.testing.TestStatus.PASSED }
                        val failed = testResults.count { it.status == com.ghostty.android.testing.TestStatus.FAILED }
                        Text(
                            text = "Passed: $passed, Failed: $failed",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (failed > 0) MaterialTheme.colorScheme.error
                                   else MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }
        }
    }
}
