# Third-party components

Dissect is independent software by Green Shoe Garage. No NSA endorsement or
affiliation is implied. Dissect's original source and sample inputs use the
included MIT license. Third-party components retain their own licenses.

The compiled Apple Silicon app includes the following distributions. Their
license files, copyright notices and bundled source are preserved in
`Dissect.app/Contents/Resources/Runtime`. Versions and archive SHA256 values
are pinned in `scripts/bundle-runtime.sh`.

| Component | Version | Source and license locations |
|---|---|---|
| Ghidra | 12.2 | https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.2_build ; Runtime/ghidra/LICENSE, NOTICE, licenses/, GPL/, bom.json |
| PyGhidra | 3.2.0 | Ghidra/Features/PyGhidra/pypkg; wheel notices and installed dist-info |
| JPype1 | 1.5.2 | https://github.com/jpype-project/jpype ; installed dist-info/licenses, Apache 2.0 |
| CPython standalone | 3.13.18 / 20261110 | https://github.com/astral-sh/python-build-standalone/releases/tag/20261110 ; Runtime/python/licenses and Python license files |
| Amazon Corretto JDK | 25.0.5.0.10 | https://github.com/corretto/corretto-25 ; Runtime/java.jdk/Contents/Home/legal (OpenJDK GPLv2 with Classpath Exception and third-party notices) |

The Ghidra distribution includes the source for native components rebuilt by
its official `support/gradle` build. It is retained in the redistributed app.
No Apple SDK, Xcode, or Swift compiler is redistributed. macOS system frameworks
are dynamically linked. Vendor runtime binaries are ad-hoc signed for this
preview; that does not change their copyright or licensing.

The source repository itself contains no downloaded engine/runtime archives.
The app icon and C sample fixtures are original Dissect assets.
