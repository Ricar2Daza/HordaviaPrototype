# Celulares objetivo — qué teléfonos pueden ejecutar Hordavia

El prototipo está configurado (Godot 4.7.2, `project.godot`) con:
**renderer "mobile" (Vulkan)**, física a 30 Hz, sin MSAA, compresión de texturas
ETC2/ASTC habilitada, stretch `canvas_items` + `expand`. Ese perfil es ligero:
estamos por debajo de los requisitos del género.

## Requisitos técnicos base

| Requisito | Valor |
|---|---|
| Motor | Godot 4.7.2 (mobile renderer) |
| Android | 7.0 (API 24) o superior; **arm64-v8a obligatorio** |
| iOS | iOS 13+ (A11 chip o superior), Metal |
| RAM mínima | 3 GB (2 GB posible bajando caps, ver §Ajustes por tier) |
| GPU | Vulkan 1.0+ (Adreno 5xx+, Mali-G52+, PowerVR GT7600+) |

> **Nota de compatibilidad:** si quieres cubrir celulares *sin* Vulkan (gama muy baja
> o Android 7), duplica el build con `renderer/rendering_method="gl_compatibility"`
> (OpenGL ES 3). Es el mismo contenido; móvil renderer solo cambia el pipeline.
> Decisión recomendada: lanzar SOLO Vulkan primero (es el 90 %+ del parque Android),
> y portar a `gl_compatibility` solo si el softlaunch muestra caídas reales.

## Tiers de dispositivos

### Tier 1 — Mínimo (30 fps, menu visual reducido)
- **Perfil**: Android 8–10, 3 GB RAM, SD 450/Helio P22/Exynos 7884.
- **Ejemplos reales tipo**: Galaxy A10s/A12/A05s, Redmi 8A/9A/12C, Moto E13/E22i,
  Tecno Spark 8, Infinix Hot 11.
- Con qué caps: `MAX_BULLETS ≈ 500`, `cap` enemigos ≈ 100, partículas 50 %,
  sin sombras (ya están off), resolución render 80 %.

### Tier 2 — Recomendado (60 fps estable)
- **Perfil**: Android 10–13, 4–6 GB RAM, SD 665/680/Helio G85, Mali-G52/G57.
- **Ejemplos**: Galaxy A15/A24, Redmi Note 12 / 13, Moto G54/G84, Poco M6.
- Config por defecto (prototipo actual): bullets 1500, enemigos 220.

### Tier 3 — Premium (60 fps + juice completo)
- **Perfil**: Android 11+, 6–8 GB RAM, SD 720G/732G/7 Gen/Dimensity 700+.
- **Ejemplos**: Poco X6/Note 13 Pro, Galaxy A55/S-series, Pixel 6a+, Moto Edge 40.
- Aquí todo el juice puede encenderse salvo que el profiler diga lo contrario.

### iOS
- **Mínimo**: iPhone 8 / SE 2 / X (A11–A12), iOS 13.
- **Recomendado**: iPhone XS / 11+ (A12+), iPads 7.ª gen+.
- Warning: en Apple el import exige build xcode + membresía de firmas; diferir a softlaunch.

## Presupuesto de rendimiento (meta por frame en móvil)

| Métrica | Objetivo Tier1 (30fps) | Objetivo Tier2–3 (60fps) |
|---|------------------------|--------------------------|
| Tiempo por frame | ≤ 33 ms | ≤ 16.6 ms |
| Draw calls visibles | ≤ 60 | ≤ 90 |
| Triángulos sin culling | ≤ 60 k | ≤ 120 k |
| Balas activas | ≤ 500 | ≤ 1500 |
| Enemigos activos | ≤ 100 | ≤ 220 |
| Nodos activos en escena | ≤ 800 | ≤ 1500 |
| Memoria de la app | ≤ 250 MB | ≤ 350 MB |
| APK/AAB tamaño | ≤ 120 MB | ≤ 150 MB |

Medir con el **profiler de Godot** (Monitor → temporal) más `BulletSwarm.active_count()`
y `EnemyManager.active_count()` que ya expone el prototipo.

## QA — matriz mínima de pruebas antes de invertir más

1. **1 celular Tier1** (lo más barato que puedas conseguir prestado): ¿logra 30 fps en minuto 5+?
2. **1 celular Tier2**: ¿60 fps estable, batería/heat aceptable en 15 min de run?
3. **1 iPhone mínimo** (o simulador + tester): ¿UI en notch/safe area correcta?
4. ¿Se pierde el funciona el salvado al cerrar la app desde el launcher (no por botón)?
5. ¿Las manos promedio (pulgares a la izquierda del centro + botón dash alcanzable?) pass:
   pulgares naturales no deben tapar la horda en el centro inferior.

¿Por qué funciona tan ligero? Porque el prototipo toma las decisiones del panel:
MultiMesh para todo lo repetido, cero física de colisión entre entidades, grilla
hash para consultation y cero assets pesados todavía.
