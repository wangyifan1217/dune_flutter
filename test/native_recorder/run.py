"""Compile the production Kotlin audio classes against deterministic media doubles.

Requires JAVA_EXE and KOTLIN_COMPILER_CP (compiler + its dependencies).
This checks codec protocol/error handling; it does not replace Android device tests.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
here = Path(__file__).resolve().parent
java = os.environ.get('JAVA_EXE', 'java')
compiler = os.environ['KOTLIN_COMPILER_CP']
stdlib = os.environ['KOTLIN_STDLIB']
source = root / 'android/app/src/main/kotlin/nova/dunes/dunes_app'
files = [*(here / 'fakes').glob('*.kt'), here / 'RecorderHarness.kt',
         *(source / name for name in ['StreamingAacM4aEncoder.kt', 'WavToM4aConverter.kt', 'CrashSafeWavWriter.kt', 'MeetingPcmSink.kt'])]
with tempfile.TemporaryDirectory(prefix='meeting-kotlin-') as output:
    subprocess.run([java, '-cp', compiler, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                    '-no-stdlib', '-no-reflect', '-nowarn', '-classpath', stdlib,
                    '-d', output, *map(str, files)], check=True)
    subprocess.run([java, '-cp', os.pathsep.join([output, stdlib]),
                    'nova.dunes.dunes_app.RecorderHarnessKt'], check=True, timeout=45)
