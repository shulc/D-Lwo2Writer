/// Minimal LWO2 (LightWave object) writer for D.
///
/// Public import surface: `import lwo2;` brings in the dependency-free writer
/// (`lwo2.writer`). The assimp adapter lives in `lwo2.assimp` and must be
/// imported explicitly — it is only built in the `full` dub configuration.
module lwo2;

public import lwo2.writer;
