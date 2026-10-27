# Export Android — Hordavia

APKs compilados el **26/10/2026** con Godot **4.7.2**:

| APK | Tamaño | Plantilla | Uso |
|---|---|---|---|
| `build/Hordavia.apk` | 25.5 MiB | Release | **Final**, firmada con keystore propio (`CN=Hordavia`) |
| `build/Hordavia-debug.apk` | 27.2 MiB | Debug | Pruebas con logcat/depuración |

| Dato | Valor |
|---|---|
| Paquete | `com.hordavia.prototype` |
| App label | Hordavia |
| Versión | `0.1.0` (versionCode 1) |
| Arquitectura | `arm64-v8a` (solo ARM64) |
| Android mínimo | 24 (Android 7.0) |
| Target SDK | 36 |
| Firma | `Hordavia.apk`: release `CN=Hordavia`; debug: `CN=Godot` |
| Renderer | `mobile` (Vulkan) + ETC2/ASTC |
| Alineación | 16 KB verificada con `zipalign -c -P 16` |

Los hashes SHA-256 de ambos APK están en `build/SHA256SUMS.txt`.

## Herramientas instaladas

| Herramienta | Ruta / versión |
|---|---|
| Android SDK | `C:\Users\Usuario\Tools\android-sdk` |
| Command-line tools | 22.0 (`cmdline-tools\latest`) |
| Platform | `platforms\android-36` |
| Build-Tools | `36.0.0` y `35.0.0` |
| Platform-Tools | `37.0.1` (`adb.exe`) |
| JDK | Temurin 21 — `C:\Users\Usuario\Tools\jdk-21` |
| Godot | 4.7.2 + export templates 4.7.2 |

Variables de usuario: `ANDROID_HOME`, `ANDROID_SDK_ROOT` y
`...\platform-tools` agregado al `PATH`.

## Configuración del editor

`Editor → Editor Settings → Export → Android`:

- **Android SDK Path**: `C:/Users/Usuario/Tools/android-sdk`
- **Java SDK Path**: `C:/Users/Usuario/Tools/jdk-21`
- **Debug Keystore**: `C:/Users/Usuario/AppData/Roaming/Godot/keystores/debug.keystore`
  (password `android`, alias `androiddebugkey`)

> Si el editor estaba abierto, ciérralo y vuelve a abrirlo después de cambiar las rutas:
> Godot guarda sus ajustes al salir y puede sobrescribir el archivo.

## Preset `Android`

`export_presets.cfg`:

- `package/unique_name="com.hordavia.prototype"`
- `package/name="Hordavia"` y `version/name="0.1.0"`
- `architectures/arm64-v8a=true` (las demás en `false`)
- `package/signed=true`
- `package/show_as_launcher_app=true` (icono visible en el cajón de apps)
- `screen/immersive_mode=true`
- `exclude_filter="build/*"` (evita meter el APK anterior en el paquete)
- Gradle desactivado: usa la plantilla Android precompilada de Godot.

> Edita `export_presets.cfg` con el editor **cerrado**: si está abierto, conserva en
> memoria los valores viejos y puede sobrescribirlos al guardar.

## Compilar por consola

```powershell
$godot = 'C:\Users\Usuario\Downloads\Godot_v4.7.2-stable_win64.exe'
$proj  = 'C:\Users\Usuario\Documents\proyecto\HordaviaPrototype'
$apk   = Join-Path $proj 'build\Hordavia-debug.apk'

& $godot --headless --path $proj --export-debug "Android" $apk
```

Release final firmada con el keystore propio:

```powershell
$rel   = Join-Path $proj 'build\Hordavia-unsigned.apk'
$final = Join-Path $proj 'build\Hordavia.apk'
$ks    = 'C:\Users\Usuario\Tools\hordavia-release.keystore'
$cred  = Get-Content 'C:\Users\Usuario\Tools\hordavia-release-keystore.txt'
$pass  = ($cred | Where-Object { $_ -like 'Store password:*' }) -replace '^Store password: ',''

& $godot --headless --path $proj --export-release "Android" $rel
& 'C:\Users\Usuario\Tools\android-sdk\build-tools\36.0.0\apksigner.bat' sign `
  --ks $ks --ks-pass "pass:$pass" --ks-key-alias hordavia --out $final $rel
Remove-Item $rel
```

Godot avisa “no se pudo encontrar el almacén de claves de lanzamiento” y deja el APK
release **sin firmar**; el segundo comando lo firma con el keystore real. El certificado
del APK final es `CN=Hordavia` (guardado en `C:\Users\Usuario\Tools\`).

El icono del proyecto es `assets/icon.png` (original, generado para Hordavia).
El APK queda firmado y verificado por `apksigner` al final del export.

## Instalar en el teléfono

Con depuración USB activa:

```powershell
$adb = 'C:\Users\Usuario\Tools\android-sdk\platform-tools\adb.exe'
& $adb devices
& $adb install -r `
  'C:\Users\Usuario\Documents\proyecto\HordaviaPrototype\build\Hordavia.apk'
```

Si cambias entre debug y la versión final, Android puede rechazar la instalación por firma
distinta (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`):

```powershell
& $adb uninstall com.hordavia.prototype
```

Abrir la app (también aparece el icono **Hordavia** en el cajón de apps):

```powershell
& $adb shell am start -n com.hordavia.prototype/com.godot.game.GodotAppLauncher
# alternativa:
& $adb shell monkey -p com.hordavia.prototype -c android.intent.category.LAUNCHER 1
```

Logs del motor:

```powershell
& $adb logcat -s godot:V
```

También puedes copiar el APK al teléfono y abrirlo con “Instalar apps desconocidas”
permitido para el explorador de archivos. Al día de este documento **no había ningún
dispositivo conectado** (`adb devices` vacío), así que falta la prueba en hardware real.

## Probar con el GSI Android 17

El GSI **no se usa para compilar el APK**: es una imagen de sistema para arrancar Android
17 en un teléfono ARM64 compatible con Project Treble. El APK ya está compilado y es
independiente de la versión de Android (funciona de Android 7 en adelante).

Requisitos: teléfono **ARM64**, bootloader desbloqueable, Treble, `adb`/`fastboot`, y
una copia del firmware original para volver. **Desbloquear borra todos los datos.**

```powershell
$adb = 'C:\Users\Usuario\Tools\android-sdk\platform-tools\adb.exe'
$fastboot = 'C:\Users\Usuario\Tools\android-sdk\platform-tools\fastboot.exe'
$gsi = 'C:\Users\Usuario\Downloads\gsi_gms_arm64-exp-CP2A.260605.012-15430684-b7b01227'

& $adb reboot bootloader
& $fastboot devices

# Solo la primera vez: confirma en el teléfono (borra datos y puede anular garantía)
& $fastboot flashing unlock

# Desactiva verificación para que el GSI pueda arrancar
& $fastboot --disable-verity --disable-verification flash vbmeta "$gsi\vbmeta.img"

# fastbootd permite escribir la partición system dinámica
& $fastboot reboot fastboot
& $fastboot flash system "$gsi\system.img"

# Borra userdata (obligatorio al cambiar de sistema)
& $fastboot -w
& $fastboot reboot
```

El primer arranque puede tardar 5–15 minutos. Si `flash system` dice “not enough space”,
el teléfono necesita borrar/redimensionar la partición lógica `product` (varía por modelo;
no lo hagas a ciegas). Si el teléfono no arranca, vuelve a flashear el firmware original
con las herramientas del fabricante.

Cuando Android 17 arranque: activa **Opciones de desarrollador → Depuración USB**, conecta
el cable, acepta la huella RSA y ejecuta la sección “Instalar en el teléfono”. Para medir
FPS usa `Hordavia.apk`; para ver errores usa `Hordavia-debug.apk` + logcat.

> En un PC x86_64 no puedes usar este GSI ARM64 en el emulador estándar de Android.
> Necesitas un teléfono ARM64 real (o un host ARM64).

## Release / Google Play (AAB pendiente)

`Hordavia.apk` ya está firmada con un keystore release propio y sirve para instalar en
cualquier teléfono ARM64 (no es una build debug). El keystore está en
`C:\Users\Usuario\Tools\hordavia-release.keystore` y las credenciales en
`...\hordavia-release-keystore.txt`; **haz backup de ambos**. Sin ellos no podrás
actualizar una instalación existente.

Para publicar en Play falta generar el **AAB** (mismo keystore):

1. Cargar el keystore en `Proyecto → Exportar → Android → Opciones → Keystore de release`.
2. Cambiar `gradle_build/export_format=1` (AAB) o marcar “Exportar AAB” en el editor.
3. Exportar y probar en un teléfono real de cada tier (ver `03_DISPOSITIVOS_OBJETIVO.md`).

## Errores que ya no deben aparecer

- “Se requiere una ruta válida para el SDK de Java” → `java_sdk_path` vacío.
- “No se encontró el directorio 'platform-tools' / 'build-tools'” → SDK incompleto.
- “No se pudo encontrar apksigner” → build-tools ausente o ruta mal escrita.
- “No project icon specified” → faltaba `application/config/icon`; ya está `assets/icon.png`.
