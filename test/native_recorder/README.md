# Native recorder regression harness

This harness compiles the actual `MeetingPcmSink`, `StreamingAacM4aEncoder`,
`CrashSafeWavWriter`, and `WavToM4aConverter` production Kotlin sources against
small deterministic Android media doubles. It covers first-frame encoding failure,
independent PCM preservation, short recordings, configuration buffers, delayed or
missing output EOS, timeouts, release failures, and preservation of source WAV files.

Run with Java 17+ and Kotlin compiler 2.3.20 plus its runtime dependencies:

```sh
JAVA_EXE=/path/to/java \
KOTLIN_COMPILER_CP='/path/to/compiler-and-dependencies-classpath' \
KOTLIN_STDLIB=/path/to/kotlin-stdlib.jar \
python3 test/native_recorder/run.py
```

`KOTLIN_COMPILER_CP` uses the platform classpath separator. The compiler dependencies
are the Kotlin compiler, stdlib/JDK adapters, script runtime, reflection, coroutines,
and JetBrains annotations. The harness does not download tools or modify app data.

These tests validate protocol and error handling; they do not emulate Samsung codecs,
microphone permissions, or filesystem behavior on Android. Device checks must still
cover foreground recordings of a few seconds, pause/resume, background/lock screen,
AAC failure with WAV fallback, and chat voice after meeting recording.
