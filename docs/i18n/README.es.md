<p align="center">
  <img src="../images/icon.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Devuelve el Launchpad original a macOS 26+ (también compatible con macOS 15), con portapapeles, flujos de trabajo, atajos de apps y control de ventanas.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Sitio web</a> · <a href="CHANGELOG.es.md">Registro de cambios</a>
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
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
- `⌘⇧K` / `⌘⇧J` cambia con una animación entre Launchpad, flujos de trabajo y portapapeles
- 10 idiomas: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Requisitos

- macOS 15 o posterior

## Licencia

AppPad es software comercial propietario. © 2026 YouMindHub. Todos los derechos reservados. Este repositorio solo contiene las versiones publicadas y la documentación; el código fuente no es público.

| Parte | Licencia |
| --- | --- |
| App AppPad | Propietaria, todos los derechos reservados |
| Flujos integrados | Parte de AppPad, propietarios, todos los derechos reservados |
| Especificación del formato de flujos de trabajo | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.es), © YouMindHub |
| Flujos de terceros en el Workflow Market | © sus autores, con la licencia que elija cada autor |

- Los flujos que creas son tuyos. Tú decides cómo licenciarlos, compartirlos o venderlos.
- Al enviar un flujo al Workflow Market, concedes a YouMindHub un derecho no exclusivo para alojarlo y distribuirlo a través de AppPad. Los derechos de autor siguen siendo tuyos.
- La especificación del formato está bajo licencia CC BY 4.0: puedes copiarla, adaptarla y redistribuirla siempre que cites a AppPad.
- Los flujos integrados no pueden extraerse ni redistribuirse por separado de AppPad.
- El nombre «AppPad» y su icono no están cubiertos por ninguna de las licencias anteriores.

## Agradecimientos

- [GRDB.swift](https://github.com/groue/GRDB.swift) — licencia MIT
- [Sparkle](https://github.com/sparkle-project/Sparkle) — licencia MIT

---

© 2026 YouMindHub
