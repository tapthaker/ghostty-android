# Contributing to Ghostty Android

Thank you for your interest in contributing to Ghostty Android! This document provides guidelines for contributing to the project.

## Code of Conduct

This project follows a simple code of conduct:
- Be respectful and considerate
- Welcome newcomers and beginners
- Focus on constructive feedback
- Assume good intentions

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Description**: Clear description of the issue
- **Steps to Reproduce**: Detailed steps to reproduce the behavior
- **Expected Behavior**: What you expected to happen
- **Actual Behavior**: What actually happened
- **Environment**:
  - Android version
  - Device model
  - App version
  - Logcat output (if applicable)

### Suggesting Features

Feature requests are welcome! Please include:

- **Use Case**: Why this feature would be useful
- **Proposed Solution**: How you envision it working
- **Alternatives**: Other approaches you've considered

### Code Contributions

1. **Fork the Repository**
   ```bash
   git clone https://github.com/yourusername/ghostty-android.git
   cd ghostty-android
   ```

2. **Create a Branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bugfix-name
   ```

3. **Make Your Changes**
   - Follow the existing code style
   - Add tests for new functionality
   - Update documentation as needed

4. **Test Your Changes**
   ```bash
   # Build native library
   ./scripts/build-native.sh

   # Run Android tests
   cd android
   ./gradlew test
   ./gradlew connectedAndroidTest
   ```

5. **Commit Your Changes**
   ```bash
   git add .
   git commit -m "feat: Add awesome new feature"
   ```

   Use conventional commit format:
   - `feat:` New feature
   - `fix:` Bug fix
   - `docs:` Documentation changes
   - `test:` Test additions/changes
   - `refactor:` Code refactoring
   - `perf:` Performance improvements
   - `chore:` Build/tooling changes

6. **Push and Create Pull Request**
   ```bash
   git push origin feature/your-feature-name
   ```

   Then create a Pull Request on GitHub.

## Development Setup

### Prerequisites

- **Android Studio**: Latest stable version
- **Android NDK**: r25 or later
- **Zig**: Latest stable (0.11+)
- **Git**: For version control
- **JDK**: 17 or later

### Building the Project

1. **Clone with Submodules**
   ```bash
   git clone --recursive https://github.com/yourusername/ghostty-android.git
   ```

2. **Build Native Library**
   ```bash
   cd ghostty-android
   ./scripts/build-native.sh
   ```

3. **Open in Android Studio**
   - Open the `android/` directory
   - Let Gradle sync
   - Build and run on device/emulator

### Project Structure

```
ghostty-android/
├── libghostty-vt/       # Ghostty submodule
├── android/             # Android app
│   ├── app/            # Main application
│   └── jni/            # JNI wrapper code
├── docs/               # Documentation
├── scripts/            # Build scripts
└── tests/              # Integration tests
```

## Code Style

### Kotlin Code

- Follow [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html)
- Use 4 spaces for indentation
- Maximum line length: 120 characters
- Use meaningful variable names
- Add KDoc comments for public APIs

Example:
```kotlin
/**
 * Parses terminal escape sequences and updates terminal state.
 *
 * @param data The raw terminal data to parse
 * @return Number of bytes successfully parsed
 */
fun parse(data: ByteArray): Int {
    // Implementation
}
```

### Zig Code

- Follow standard Zig style
- Use snake_case for functions and variables
- Use PascalCase for types
- Add doc comments for public APIs

### C/JNI Code

- Follow K&R style with 4-space indentation
- Prefix all JNI functions with `Java_`
- Always check for null pointers
- Handle exceptions properly

## Testing

### Unit Tests

Write unit tests for:
- Terminal parsing logic
- Input handling
- State management

```kotlin
@Test
fun testTerminalParsing() {
    val vt = GhosttyVT(24, 80)
    val result = vt.parse("Hello\r\n".toByteArray())
    assertEquals(7, result)
}
```

### Integration Tests

Test full workflows:
- Parse → Render pipeline
- Input → Output roundtrip
- Resize handling

### Performance Tests

Benchmark critical paths:
- Parsing throughput
- Rendering FPS
- Memory usage

## Documentation

- Update README.md for user-facing changes
- Update ARCHITECTURE.md for architectural changes
- Add/update API documentation
- Include code examples where helpful

## Pull Request Process

1. **Ensure CI Passes**: All tests must pass
2. **Update Documentation**: Keep docs in sync with code
3. **Describe Changes**: Clear PR description
4. **Link Issues**: Reference related issues
5. **Respond to Feedback**: Address review comments

## Getting Help

- **GitHub Discussions**: For questions and general discussion
- **GitHub Issues**: For bugs and feature requests
- **Code Comments**: For implementation questions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors will be recognized in:
- README.md contributors section
- Release notes
- GitHub contributors graph

## Development Resources

### Useful Links

- [Ghostty Documentation](https://ghostty.org/docs)
- [Jetpack Compose](https://developer.android.com/jetpack/compose)
- [Android NDK Guide](https://developer.android.com/ndk/guides)
- [Zig Language Reference](https://ziglang.org/documentation/master/)

### Community

- Watch the Ghostty main project for updates
- Join discussions about terminal emulation
- Share your use cases and feedback

---

Thank you for contributing to Ghostty Android!
