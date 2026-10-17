<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Devuelve el Launchpad original a macOS 26+ (también compatible con macOS 15), con portapapeles, flujos de trabajo, atajos de apps y control de ventanas.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Sitio web</a><br>
  <a href="#wechat-donate">☕ Apoyar con WeChat</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.de.md">Deutsch</a> ·
  Español ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a>
</p>

---

## Instalación

### Opción 1: descargar el DMG

[Descarga la última versión](https://github.com/umindhub/AppPad/releases/latest), abre el DMG y arrastra AppPad a la carpeta Aplicaciones.

### Opción 2: Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## Funciones

### Launchpad
- Recreación fiel del Launchpad clásico de macOS; la disposición por defecto sigue el orden del sistema
- Se abre juntando cuatro dedos, desde la barra de menús o haciendo clic en AppPad en el Dock (otro clic lo cierra)
- Carpetas, arrastrar para reordenar o crear carpetas; mantén pulsado un icono o la tecla ⌥ para entrar en modo edición
- Desinstalación limpia integrada: elimina la app junto con sus archivos residuales
- Búsqueda en cuadrícula, indicador de página (puntos / números), controles Liquid Glass (macOS 26+)
- Fondos: blanco / gris claro / gris oscuro / fondo de pantalla / color personalizado, con ajustes separados para el aspecto claro y oscuro

### Portapapeles
- Textos e imágenes se guardan de forma permanente
- Cualquier elemento copiado se puede guardar
- `⌘1`–`⌘0` para pegar rápido, filtro por app de origen, sintaxis de búsqueda `NombreApp::`, vista previa en vivo

### Flujos de trabajo & AI MCP
- `⌘Space` abre el panel de flujos de trabajo: apps y flujos ordenados juntos según su uso
- Los flujos ejecutan scripts de shell, AppleScript, Atajos o solicitudes HTTP, con argumentos (p. ej. `time 10`)
- Integrados: Vaciar papelera, Configurar temporizador, Configurar alarma, Ajustar volumen, Salir de todas las apps…
- Los permisos declarados se aplican con un sandbox real (Permitir una vez / No permitir / Permitir siempre)
- Importa y comparte flujos como archivos JSON o enlaces
- Servidor MCP integrado: los asistentes de IA compatibles con MCP pueden llamar y controlar tus flujos directamente
- La IA puede leer por MCP las reglas para escribir flujos y crear nuevos flujos por ti
- Los flujos que ejecuta la IA pasan por las mismas solicitudes de permiso y el mismo sandbox que los tuyos

### Calculadora
- Escribe una expresión directamente en el campo de búsqueda del panel de flujos de trabajo para calcular (admite notación científica)

### Atajos de apps
- Asigna un atajo de teclado global a cualquier app

### Control de ventanas
- Ajustar a la izquierda / derecha (½ → ⅓ → ⅔), maximizar, restaurar, mover a otra pantalla; todos los atajos son personalizables

### Otros
- Abrir al iniciar sesión
- `⌘⇧J` / `⌘⇧K` cambia con una animación entre Launchpad, portapapeles y flujos de trabajo
- 10 idiomas: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Requisitos

- macOS 15 o posterior
- Xcode 27 (para compilar desde el código fuente)

## Compilación

1. Abre `AppPad.xcodeproj`
2. Elige un esquema: `AppPad Dev`, `AppPad Beta` o `AppPad`
3. Configura tu propio equipo de firma y luego compila y ejecuta

Las dependencias se resuelven con Swift Package Manager.

## Licencia

AppPad usa una licencia dividida:

| Parte | Licencia |
| --- | --- |
| Código fuente de la app AppPad (todo lo que no aparece abajo) | [AGPL-3.0](LICENSE) |
| Flujos integrados (`AppPad/Workflow/BuiltinWorkflows.swift`, `*.shortcut`) | [MIT](LICENSE-MIT) |
| Especificación del formato de flujos de trabajo | [MIT](LICENSE-MIT) |
| Flujos de terceros en el Workflow Market | [MIT](LICENSE-MIT), © sus autores |

- **AGPL-3.0**: puedes usar, modificar y redistribuir AppPad, pero cualquier obra derivada que se distribuya u ofrezca a través de una red debe publicarse bajo AGPL-3.0 con el código fuente completo.
- **Licencia comercial**: para un uso cerrado o propietario, contacta con el autor a través del [sitio web](https://apppad.youmindhub.com) para obtener una licencia comercial.
- **MIT para los flujos de trabajo**: cualquiera puede escribir, compartir o vender flujos libremente e implementar el formato en otras herramientas, sin obligaciones de la AGPL.
- Los flujos que creas son tuyos. Los flujos enviados al Workflow Market deben tener licencia MIT.
- El nombre «AppPad» y su icono no están cubiertos por estas licencias; los forks deben usar otro nombre y otro icono.

## Contribuir

Se aceptan issues y pull requests. Al enviar una contribución aceptas que se publique bajo la licencia de la parte que modificas y concedes al mantenedor el derecho de distribuirla también bajo la licencia comercial.

## Agradecimientos

- [GRDB.swift](https://github.com/groue/GRDB.swift) — licencia MIT
- [Sparkle](https://github.com/sparkle-project/Sparkle) — licencia MIT

<a id="wechat-donate"></a>

## Apoya AppPad

AppPad es gratuito y de código abierto. Si hace que tu Mac sea un poco más agradable de usar, puedes invitarme a un café por WeChat: cualquier cantidad se agradece, y una estrella en GitHub también ayuda mucho. ¡Gracias!

<p align="center">
  <img src="docs/images/wechat-donate.png" width="300" alt="WeChat">
  <br>
  <sub>Escanea con WeChat</sub>
</p>

---

© 2026 YouMindHub
