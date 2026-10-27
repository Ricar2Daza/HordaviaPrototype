# Artefactos REA — Megabonk v1.0.69

Evidencia de análisis estático usada para diseñar Hordavia. **No contiene assets ni
código del juego de referencia**; solo metadatos de inventario y registros de la
herramienta. Megabonk pertenece a Ved.

Movido el 26/10/2026 desde
`C:\Users\Usuario\Downloads\Megabonk.v1.0.69-0xdeadcode\` a este proyecto.

| Archivo | Qué es | Estado |
|---|---|---|
| `dlllist.txt` | Inventario de DLLs de la build (`dlllist` de REA) | ✅ útil |
| `GameAssembly.analyze.json` | Respuesta de REA/Ghidra al intentar `read_binary_inventory_summary` | ⚠️ **falló** (`execution_failure`: “Ghidra exited before bridge startup”) |
| `analyze.stderr.txt` | stderr del intento de análisis | vacío (0 bytes) |
| `Guia_Roguelike_BulletHeaven_Godot_Movil.md` | Versión original de la guía maestra que vivía junto al binario | 📄 referencia; la copia canónica actualizada está en [`../Guia_Roguelike_BulletHeaven_Godot_Movil.md`](../Guia_Roguelike_BulletHeaven_Godot_Movil.md) |

Consecuencia: el enriquecimiento de `docs/01_Apendice_A_Sistemas_Megabonk.md` §A.10
con decompilación de Ghidra sigue pendiente; el resto del apéndice se apoya en
evidencia de inventario/strings y en pseudocódigo propio.
