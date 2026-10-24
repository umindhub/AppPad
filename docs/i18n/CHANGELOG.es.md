# Registro de cambios

<p align="center">
  <a href="../../CHANGELOG.md">English</a> ·
  <a href="CHANGELOG.zh-CN.md">简体中文</a> ·
  <a href="CHANGELOG.zh-TW.md">繁體中文</a> ·
  <a href="CHANGELOG.ja.md">日本語</a> ·
  <a href="CHANGELOG.ko.md">한국어</a> ·
  <a href="CHANGELOG.de.md">Deutsch</a> ·
  Español ·
  <a href="CHANGELOG.fr.md">Français</a> ·
  <a href="CHANGELOG.it.md">Italiano</a> ·
  <a href="CHANGELOG.nl.md">Nederlands</a>
</p>

Todos los cambios importantes de AppPad se documentan en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) y el proyecto sigue el [versionado semántico](https://semver.org/).

> Este documento es una traducción de [CHANGELOG.md](../../CHANGELOG.md). En caso de discrepancia, prevalece la versión en inglés.

## v1.3.8

### Added

#### Flujos de trabajo
- Botón Ejecutar (⌘S) en el panel de flujos de trabajo: ejecuta el flujo seleccionado, mantiene el panel abierto y muestra el resultado en «Última ejecución».
- Ahora los flujos de trabajo integrados se pueden ver (solo lectura) en Ajustes.

### Changed
- Flujos de trabajo: al ejecutar sin un argumento obligatorio, la indicación se marca con un icono de aviso y una breve sacudida.

### Fixed
- Launchpad: corregido que la disposición se borrara cuando una actualización o reinstalación con .pkg tardaba mucho.

## v1.3.7

### Changed
- Clips guardados: El campo de nombre ahora llega hasta la fecha y el contenido se alinea con el nombre; en Editar contenido, el título y el nombre se alinean con el texto.

### Fixed
- Ajustes: La ventana de Ajustes ahora pasa al frente al abrirse desde Launchpad, Flujos de trabajo, Portapapeles o la barra de menús.
- Clips guardados: ⌘Q y Salir de AppPad ahora funcionan con Editar contenido o una confirmación abiertos.

## v1.3.6

### Added

#### Ajustes
- Nuevo interruptor «Mostrar flechas para cambiar de panel» en General: muestra u oculta las flechas ← / → junto a los títulos de Portapapeles y Flujos de trabajo. ⌘⇧K / ⌘⇧J siguen cambiando de panel.
- Nuevo interruptor «Mostrar indicaciones de atajos» en General: muestra u oculta la línea de atajos bajo los títulos de Portapapeles y Flujos de trabajo. Si está desactivado, el título queda en la misma línea que el campo de búsqueda.
- Ambos están activados por omisión.

## v1.3.5

### Added

#### Launchpad
- Atajo de teclado opcional para abrir Launchpad (⌥Espacio por omisión, desactivado por omisión): púlsalo de nuevo para cerrarlo. Actívalo y cámbialo en Ajustes › AppPad › Abrir con atajo; cuando está activado, también aparece en el menú de la barra de menús.

#### Guía de bienvenida
- La página de juntar los dedos ahora permite activar el atajo de Launchpad y elegir una esquina activa para Launchpad.

### Changed
- Copia de seguridad: las copias de los atajos ahora incluyen el atajo de Launchpad.

## v1.3.4

### Added

#### Launchpad
- Paso rápido de páginas (Ajustes › General, desactivado por omisión): un deslizamiento corto con dos dedos pasa de página, y un solo deslizamiento puede avanzar varias páginas. Los deslizamientos hacia arriba/abajo también siguen a los dedos.
- Con el paso rápido de páginas activado, mantén pulsados y arrastra los puntos de página para desplazar las páginas de forma continua; al soltar se ajusta a la página más cercana. También funciona dentro de las carpetas.

### Changed
- Launchpad: Puedes arrastrar el siguiente icono mientras el anterior aún vuela a su sitio (por ejemplo, a una carpeta), sin esperar a que termine la animación.

## v1.3.3

### Added

#### Esquinas activas
- Nuevas esquinas activas en Ajustes › AppPad: cada esquina de la pantalla puede abrir AppPad, Flujos de trabajo o el Portapapeles, o ejecutar una acción de macOS (Mission Control, Ventanas de aplicaciones, Escritorio, Centro de notificaciones, Nota rápida, salvapantallas, reposo de la pantalla, Bloquear pantalla).
- Mantén pulsadas ⌘, ⌥, ⌃ o ⇧ (o varias) al elegir una acción para que esa esquina solo funcione con esas teclas pulsadas, igual que en macOS.

### Note
- El centro de notificaciones y la nota rápida necesitan permiso de accesibilidad.
- Si una esquina también está configurada en las esquinas activas de macOS, se ejecutan ambas; AppPad muestra un aviso con acceso directo a Ajustes del Sistema.

## v1.3.2

### Added

#### Flujos de trabajo
- Nueva acción integrada «Rellenar comando en Terminal»: abre Terminal en la carpeta elegida con un comando ya escrito. No se ejecuta nada hasta que pulses Retorno. `{{input}}` se sustituye por el argumento.

### Changed
- Flujos de trabajo: «Instalar Homebrew» ahora solo escribe el comando de instalación oficial en Terminal; pulsa Retorno para iniciarlo.
- Flujos de trabajo: antes de que un script controle otra app, AppPad pide permiso a macOS, por lo que la app aparece en Privacidad y seguridad › Automatización. Si se deniega el acceso, el flujo se detiene con un mensaje claro.
- Asistentes de IA: la IA puede escribir flujos que rellenan comandos en Terminal; instalar Homebrew mediante IA también solo escribe el comando.

### Note
- Si Terminal pregunta si quieres terminar un proceso en ejecución al cerrar la ventana, añade `zsh` a los procesos ignorados en los ajustes de Terminal (Perfiles › Shell › Preguntar antes de cerrar).

## v1.3.1

### Added

#### Flujos de trabajo
- Nuevo flujo de trabajo integrado «Buscar en App Store»: escribe `mas` o `appstore` seguido de palabras clave para abrir los resultados directamente en la App Store.

### Fixed
- Panel de flujos de trabajo: ⌘1–⌘0 sobre un flujo que acepta un argumento ahora lo selecciona y escribe su nombre, listo para el argumento, en lugar de no hacer nada.

## v1.3.0

### Fixed
- Portapapeles: los resultados de la calculadora copiados en AppPad ahora muestran el icono de AppPad como app de origen en lugar de un marcador vacío.

## v1.2.9

### Added

#### Flujos de trabajo
- Cada flujo de trabajo muestra su origen: Integrado (verde), Mío (azul, escrito por ti o guardado por un asistente de IA) o De terceros (naranja, con el sitio web de procedencia o «Archivo importado»).
- El panel de flujos de trabajo marca las filas de terceros con un icono naranja; la vista previa muestra el enlace completo y cuándo se importó.
- Las solicitudes de permiso muestran el origen del flujo de trabajo; las confirmaciones de ejecución lo muestran en los de terceros.

### Changed
- Flujos de trabajo: Cambiar los pasos o permisos de un flujo integrado o de terceros lo marca como «Editado»; uno de terceros sigue siendo de terceros tras editarlo.
- Flujos de trabajo: Si un flujo de trabajo se reemplaza por otro de un origen distinto, AppPad vuelve a pedir sus permisos.

### Fixed
- Flujos de trabajo: Los flujos importados podían reemplazar a los integrados reutilizando su ID; ahora se omiten.
- Copia de seguridad: Al restaurar ya no se sobrescriben los flujos integrados; solo se restauran su estado activado/desactivado y su atajo del panel.

### Note
- Los flujos de trabajo no integrados añadidos antes de esta versión aparecen como «Mío», porque no se registró su origen.

## v1.2.8

### Added

#### Asistentes de IA
- Los asistentes de IA pueden buscar, instalar y desinstalar apps con Homebrew. Solo se instalan apps del catálogo oficial de Homebrew notarizadas por Apple (herramientas de línea de comandos solo desde dentro de la app), y cada app se vuelve a comprobar tras instalarla.
- Cada instalación y desinstalación pide antes tu confirmación. Puedes desactivarlo en Ajustes › Asistentes de IA; entonces un aviso enumera los riesgos.
- Si falta Homebrew, AppPad ofrece abrir Terminal con el comando de instalación oficial.

#### Flujos de trabajo
- Nuevo flujo de trabajo integrado “Instalar Homebrew”.

### Changed
- Asistentes de IA: Las confirmaciones iniciadas por la IA (instalar, desinstalar, guardar flujos, ejecutar, permisos) ahora aparecen delante sin traer al frente las demás ventanas de AppPad.

### Note
- Las apps desinstaladas con Homebrew se eliminan directamente, no van a la papelera.
- No se admiten fórmulas ni taps de terceros. Homebrew solo se detecta en /opt/homebrew y /usr/local.

## v1.2.7

### Added

#### Barra de menús
- «Buscar actualizaciones…» ahora tiene el atajo ⌘U.

### Fixed
- Barra de menús: Los atajos globales (Flujos de trabajo, Portapapeles, atajos de apps y de ventanas) pulsados con el menú abierto ahora lo cierran y se ejecutan al instante, en lugar de esperar a que se cierre el menú.
- Barra de menús: Abrir Ajustes con ⌘, desde el menú con Flujos de trabajo o Portapapeles abiertos ya no vuelve transparente el fondo del panel por un momento.

## v1.2.6

### Fixed
- Launchpad: Cambiar el número de filas o columnas de la cuadrícula ya no reorganiza todas las páginas. Al ampliar la cuadrícula, solo las páginas que estaban llenas toman iconos del principio de la página siguiente y las que no lo estaban se quedan como están; al reducirla, los iconos que ya no caben pasan al principio de la página siguiente.

## v1.2.5

### Changed
- Launchpad: Las apps que aún se están descargando del App Store muestran ahora su icono con un 70 % de opacidad, para reconocerlas mejor.

### Fixed
- Launchpad: Al terminar una descarga del App Store aparecía brevemente un recuadro vacío con borde discontinuo antes del icono de la app. Ahora el icono cambia directamente.
- Launchpad: Las apps recién instaladas con Homebrew o arrastradas a Aplicaciones ya no muestran primero el icono genérico de app.

## v1.2.4

### Added

#### Asistentes de IA (MCP)
- Configura Claude Desktop con un clic: los botones «Añadir a Claude Desktop» y «Quitar de Claude Desktop» muestran el estado actual (Añadido / No añadido / No instalado). Solo se cambia la entrada de AppPad en claude_desktop_config.json; tus otros servidores MCP se quedan como están.
- Si AppPad se ha movido después de añadirlo, el estado lo indica y «Añadir a Claude Desktop» actualiza la ruta.

#### Flujos de trabajo
- Nuevos flujos de trabajo integrados «Añadir AppPad a Claude Desktop» y «Quitar AppPad de Claude Desktop». Escribe «claude» o «mcp» en el panel de flujos de trabajo para encontrarlos.

#### Guía de bienvenida
- La página de IA incluye ahora los mismos botones para añadir y quitar Claude Desktop.

### Note
- Reinicia Claude Desktop después de añadir o quitar AppPad para que el cambio surta efecto.
- Si Claude Desktop no está instalado, no se añade nada y AppPad te lo indica.
- Antes de cada cambio se guarda una copia del archivo anterior junto a él como claude_desktop_config.json.apppad-backup.

## v1.2.3

### Fixed
- Portapapeles: Los elementos guardados ahora se ordenan por uso más reciente, igual que el historial. Un elemento sube al principio al pegarlo o copiarlo, en lugar de quedarse en el orden en que se guardó.

## v1.2.2

### Changed
- Panel de flujos de trabajo: «Última ejecución» en la vista previa ahora muestra un icono de estado con el mismo estilo que la comprobación del argumento, un tono más claro: ✓ verde si se completó, ✕ rojo si falló y – gris si se canceló, con el color de texto a juego, para ver el último resultado de un vistazo.
- Panel de flujos de trabajo: Una ejecución cancelada ya no se muestra en rojo como un error.

## v1.2.1

### Changed
- Launchpad: Se ha mejorado el arrastre entre apps y carpetas.

### Fixed
- Ajustes: Se corrigió un problema por el que la ventana de Ajustes se superponía con otras ventanas al abrirse.

## v1.2.0

### Changed
- Launchpad: Al hacer clic en una app, Launchpad ahora se cierra con la misma animación de zoom y desvanecimiento que al hacer clic en un espacio vacío, en lugar de desaparecer de golpe.

## v1.1.9

### Añadido
- Launchpad: los iconos de las apps ahora muestran los mismos globos rojos que el Dock (mensajes sin leer, actualizaciones). Las carpetas muestran la suma de los globos de sus apps, o un punto rojo cuando las apps que contienen solo tienen globos de texto.
- Ajustes › General: nuevo interruptor “Mostrar globos de las apps”, activado por defecto. Los globos se leen del Dock y requieren el permiso de Accesibilidad; sin él, el interruptor muestra un aviso con un botón para abrir Ajustes del Sistema.

## v1.1.8

### Cambiado
- Apariencia: se han refinado la forma de los botones y el color de los interruptores.
- Atajos: se ha mejorado el rendimiento de la lista de atajos.
- Clips guardados: se ha cambiado la forma de gestionar los elementos duplicados del portapapeles.

### Corregido
- Se ha corregido un problema al ajustar el ancho del lado izquierdo.

## v1.1.7

### Cambiado
- Apariencia: todos los interruptores son ahora verdes y todos los botones comparten la misma forma de píldora.
- Desinstalación: se ha refinado la página de confirmación de borrado.

## v1.1.6

### Añadido

#### Guía de bienvenida
- En el primer inicio, AppPad abre ahora una guía de bienvenida en lugar del Launchpad: un breve recorrido por las funciones, seguido de algunos pasos de configuración. Todos los pasos se pueden omitir, y Esc o ⌘W cierra la guía.
- Juntar cuatro dedos: actívalo o desactívalo, consulta qué gestos de macOS hay que desactivar y en qué orden, y abre los ajustes del trackpad con un clic.
- Portapapeles: activa o desactiva el historial, consulta sus atajos y las teclas más útiles (⌘1–⌘0, ⌘S, ⌘↩), y descubre cómo, al hacer clic en el icono de una app, solo se muestra lo copiado desde esa app.
- ⌘Space para los flujos de trabajo: desactiva el atajo de Spotlight con un clic. El cambio se aplica al instante, sin cerrar sesión, y se puede deshacer en la misma página. Si no se puede cambiar automáticamente, la guía te dirige a los ajustes de Teclado.
- Atajos de apps: pruébalo asignando ⌃⌘J a Safari con un clic y luego añade más en Ajustes › Atajos de apps.
- La IA escribe flujos de trabajo: activa Asistentes de IA (MCP), copia la configuración para Claude Code u otros clientes y prueba los prompts de ejemplo. Cada flujo que escribe la IA sigue necesitando tu aprobación.
- Permisos e inicio: concede el permiso de Accesibilidad (necesario para pegar y para el control de ventanas) y activa la apertura al iniciar sesión, con el estado en vivo de cada uno.
- La última página muestra los atajos de Launchpad, Portapapeles, elementos guardados y flujos de trabajo; “Abrir AppPad” lleva directamente al Launchpad.
- Desliza dos dedos a la izquierda o a la derecha, o haz clic o arrastra sobre los puntos inferiores, para moverte entre páginas.
- Vuelve a abrir la guía cuando quieras desde Ajustes › Acerca de › Mostrar la guía de bienvenida….

### Cambiado
- La guía de bienvenida sustituye a los avisos independientes y de una sola vez sobre el gesto de juntar dedos y Spotlight. Si ya habías visto esos avisos, la guía no se abre por sí sola.
- Las actualizaciones automáticas esperan a que se cierre la guía de bienvenida.

## v1.1.5

### Cambiado
- Launchpad: haz clic en el nombre de una carpeta para cambiarlo en cualquier momento, no solo en modo edición.

### Corregido
- Launchpad: el nombre de una carpeta ya no se desplaza a la izquierda después de renombrarla con ↩.

## v1.1.4

### Corregido
- Corregido: las apps recién instaladas (p. ej. con Homebrew) podían mostrar un icono en blanco hasta reiniciar AppPad.

## v1.1.3

### Añadido
- Launchpad: las apps que se están descargando del App Store aparecen enseguida, atenuadas y con una barra de progreso, y pasan a mostrarse con normalidad una vez instaladas.
- Launchpad: al eliminar una app aparece una barra de progreso bajo su icono; el icono desaparece cuando termina.

### Cambiado
- Desinstalación: los ajustes y datos de la app en los contenedores del sandbox se conservan, como al eliminarla desde el Finder, de modo que al reinstalarla se recuperan.

### Corregido
- Desinstalación: las apps del App Store y otras apps propiedad del sistema se pueden volver a eliminar (el Finder pide tu contraseña o Touch ID). Los restos en `/Library` se eliminan de la misma manera.
- Desinstalación: los widgets y extensiones de la app que aún se están ejecutando ya no impiden eliminarla.

## v1.1.2

### Cambiado
- Launchpad: abrir y cerrar una carpeta con un clic ahora es más fiable.

## v1.1.1

### Cambiado
- Actualizaciones: el aviso de actualización ahora hace una cuenta atrás y se cierra solo cuando se acaba el tiempo.

## v1.1.0

### Cambiado
- Launchpad: abrir y cerrar una carpeta es ahora más fluido y responde mejor, con menos trabajo por fotograma durante la animación.

## v1.0.9

### Añadido

#### Launchpad
- La búsqueda ahora encuentra carpetas por su nombre, incluidos el pinyin y las iniciales, igual que las apps.
- Busca varias cosas a la vez con `|` o `||`; p. ej. `WeChat | Social` muestra la app y la carpeta juntas, para que puedas soltar la app directamente en la carpeta.

### Cambiado
- AppPad ahora es compatible con macOS 15 Sequoia y posterior (antes, macOS 26 Tahoe o posterior). Los controles Liquid Glass siguen disponibles en macOS 26 y posterior.

## v1.0.8

### Añadido

#### Launchpad
- Al desinstalar una app instalada con Homebrew (`brew install --cask`), ahora también se elimina de Homebrew: después de mover la app y sus restos a la Papelera, AppPad ejecuta `brew uninstall --cask` para su cask. Sin Homebrew, o con apps que no son un cask, nada cambia.
- Si Homebrew no puede terminar por sí solo (por ejemplo, cuando el cask necesita una contraseña de administrador), AppPad muestra el comando que hay que ejecutar en Terminal, con un botón para copiarlo.

#### Flujos de trabajo
- En el panel de flujos de trabajo, el resultado de un argumento escrito empieza ahora con una marca de verificación verde cuando es válido y con una cruz roja cuando no lo es.

### Cambiado
- Al pasar del Launchpad al panel de Portapapeles o de flujos de trabajo, la sombra del panel aparece ahora gradualmente durante la transformación en lugar de después.
- Las sombras de los paneles las dibuja AppPad y quedan fuera del panel. Con un fondo translúcido, los paneles de Portapapeles y de flujos de trabajo se ven ahora exactamente como el Launchpad, con el mismo desenfoque y transparencia y sin oscurecimiento adicional.
- Panel de flujos de trabajo: un resultado de argumento válido se muestra en el color de texto normal en lugar de en verde; uno no válido sigue en rojo.
- Elegir Launchpad, Portapapeles o Flujos de trabajo en el menú de la barra de menús mientras hay otro panel abierto ahora cambia de la misma manera que ⌘⇧J / ⌘⇧K.

### Corregido
- Al cambiar entre los paneles de Portapapeles y de flujos de trabajo con ⌘⇧J / ⌘⇧K podía producirse un parpadeo momentáneo.
- Abrir un panel desde la barra de menús mientras había otro abierto mostraba el escritorio durante un instante.

## v1.0.7

### Añadido

#### Asistentes de IA (MCP)
- Claude, Cursor y otros clientes MCP pueden listar y ejecutar tus flujos de trabajo, pasando un argumento igual que en el panel de flujos de trabajo. Los resultados vuelven a la IA en lugar de mostrarse como notificaciones.
- Los asistentes de IA también pueden escribir flujos de trabajo por ti. Cada flujo nuevo o modificado se muestra completo, scripts incluidos, y solo se guarda después de que hagas clic en Instalar.
- Las ejecuciones usan las mismas confirmaciones y solicitudes de permiso que el panel de flujos de trabajo. Los flujos desactivados permanecen ocultos.
- Nueva pestaña Asistentes de IA (MCP) en Ajustes, debajo de Flujos de trabajo: activada por defecto, muestra el estado de la conexión e incluye configuraciones listas para copiar para Claude Desktop, Cursor y Claude Code.
- Si AppPad no se está ejecutando, el cliente de IA lo inicia en segundo plano sin abrir el Launchpad.

## v1.0.6

### Añadido

#### Launchpad
- La búsqueda conserva las carpetas: una app dentro de una carpeta aparece ahora como su carpeta. Ábrela con un clic o ↩; la app coincidente se resalta, y otro ↩ la abre.
- Los resultados de búsqueda se pueden arrastrar: arrastra una app fuera del panel al Dock o al Finder.
- Crea carpetas mientras buscas: suelta una app lentamente sobre otro resultado para crear una carpeta nueva, o sobre una carpeta para añadirla. Las apps que se arrastran fuera de una carpeta abierta desde los resultados se pueden soltar de la misma manera. Mantén la app en el borde del panel para pasar a la página de resultados siguiente o anterior.

### Cambiado
- Cuando en una carpeta queda una sola app, esa app ahora sale de la carpeta creciendo lentamente en lugar de aparecer de golpe.
- Durante la búsqueda, la carpeta abierta, la página de resultados y la selección se mantienen cuando cambia la disposición (reordenar dentro de una carpeta, renombrar, desinstalar), y los resultados conservan su orden después de una fusión en lugar de reordenarse.

### Corregido
- Hacer clic durante una animación al soltar (por ejemplo, sobre una carpeta que aún se está formando) podía cerrar el Launchpad.

## v1.0.5

### Añadido

#### Actualizaciones automáticas
- AppPad ahora se mantiene actualizado por sí solo. Cada día a las 4:00 comprueba si hay una nueva versión, la descarga en segundo plano y la instala en cuanto no hay ningún panel abierto; después se reinicia discretamente sin abrir el Launchpad.
- ¿Se perdió la comprobación porque el Mac estaba en reposo o apagado? AppPad la recupera poco después de reactivarse y lo reintenta cada 30 minutos si la red no está lista.
- Nueva sección Actualizaciones en Ajustes › Acerca de: activa o desactiva las actualizaciones automáticas (activadas por defecto), elige la hora de comprobación, consulta cuándo se hizo la última y comprueba ahora.
- “Buscar actualizaciones…” en el menú de la barra de menús.
- Si hay una actualización esperando mientras estás en Ajustes, “Reiniciar para actualizar” la instala en el momento.
- Las actualizaciones se verifican con una firma EdDSA antes de instalarse.

### Cambiado
- Ajustes › Acerca de incluye Sparkle en los agradecimientos.

### Nota
- Las versiones anteriores a la 1.0.5 no pueden actualizarse solas: instala la 1.0.5 una vez desde el DMG o con `brew upgrade --cask apppad`; las versiones posteriores llegan automáticamente.

## v1.0.4

### Añadido
- Clips guardados: ahora se puede editar tanto el nombre como el contenido de los elementos de texto. Haz clic en el texto para abrir el editor; ⌘↩ guarda, Esc cancela. Se rechaza cualquier edición que duplique otro elemento.

### Cambiado
- Clips guardados: el botón Copiar se convierte brevemente en una marca de verificación verde tras copiar con éxito; la fila mantiene su altura.

### Corregido
- Clips guardados: copiar un elemento ya no cambia su app de origen a AppPad. La copia cuenta ahora como un uso, igual que pegar desde el panel de Portapapeles, y mueve el elemento al principio del historial.

## v1.0.3

### Añadido

#### Portapapeles
- Nueva pestaña “Clips guardados” en Ajustes para explorar, buscar y gestionar la biblioteca guardada: icono de la app de origen, nombre, vista previa de dos líneas y fecha de cada elemento, con botones Copiar y Eliminar.
- Los elementos guardados pueden tener nombre. Los nombres se pueden buscar tanto en Ajustes como en el panel de Portapapeles, y los elementos con nombre lo muestran en negrita en la lista.
- ⌘↩ sobre cualquier elemento del portapapeles lo abre en Ajustes › Clips guardados con el campo de nombre listo para escribir; los elementos no guardados se guardan primero. También disponible desde el menú contextual (“Editar en Clips guardados”).

#### Copia de seguridad y restauración
- Las copias de seguridad incluyen ahora los nombres de los elementos. Las copias antiguas se restauran como antes; al fusionar, se conserva el nombre que ya esté definido en este Mac.

### Cambiado
- Portapapeles: un elemento se elimina con ⌘⇧⌫ (antes ⌘⌫), así que ⌘⌫ en el campo de búsqueda vuelve a borrar hasta el principio de la línea.
- Portapapeles: “Mostrar en el Finder” pasa de ⌘↩ a ⌘⇧↩.

## v1.0.2

### Añadido

#### Flujos de trabajo
- Nueva opción “Preguntar antes de ejecutar” en el editor de flujos: aparece una confirmación antes de que se ejecute el flujo, tanto si se inicia desde el panel de flujos de trabajo como desde Ajustes.
- En el panel de flujos de trabajo, la confirmación se abre dentro del panel: ↩ ejecuta, Esc cancela y las demás teclas se ignoran. Mantener ↩ pulsado o pulsarlo repetidamente nunca confirma.
- El formato de flujos de trabajo incorpora un campo opcional `"confirm": true`; los archivos existentes sin él se ejecutan como antes.

### Cambiado
- El flujo integrado “Salir de todas las apps” (v1.4) ahora pide confirmación, de modo que Tab o ↩ en el panel de flujos de trabajo ya no pueden cerrar todas las apps por accidente.

## v1.0.1

### Añadido

#### Copia de seguridad y restauración
- Nueva pestaña Copia de seguridad en Ajustes: exporta a un único archivo `.apppadbackup` y restáuralo en este u otro Mac.
- Elige qué incluir: atajos de apps (además de los atajos de flujos de trabajo, Portapapeles y ventanas), la disposición del Launchpad con el tamaño de su cuadrícula, los flujos instalados (con iconos, atajos del panel y estado activado/desactivado), el historial del portapapeles y la biblioteca guardada.
- La restauración muestra el contenido de la copia antes de cambiar nada; elige qué partes restaurar y si fusionarlas con lo existente o reemplazarlo.
- La fusión añade lo que falta: las versiones más recientes de los flujos sustituyen a las antiguas, y los elementos del portapapeles se comparan por contenido, así que nada se duplica.
- La disposición del Launchpad siempre se reemplaza; las apps que no están instaladas en este Mac se omiten, y las que no están en la copia se añaden al final.
- Los secretos del llavero y los permisos “Permitir siempre” nunca se escriben en una copia de seguridad; los flujos restaurados vuelven a pedir permiso en su primera ejecución.

## v1.0.0

Primera versión pública. Requiere macOS 26 Tahoe o posterior (Universal: Apple Silicon + Intel).

### Añadido

#### Launchpad
- El Launchpad clásico vuelve a macOS 26+, con la disposición por defecto de siempre (las apps del sistema menos usadas, agrupadas en una carpeta “Otros”).
- Se abre juntando cuatro dedos, desde la barra de menús o haciendo clic en AppPad en el Dock (otro clic lo cierra). Un clic cancela la animación del gesto en cualquier momento.
- Paso de página deslizando dos dedos; indicador de página con puntos o números, que se puede tocar y recorrer arrastrando con una lente Liquid Glass.
- Búsqueda instantánea, igual que en el Launchpad de macOS 15; resultados ordenados según la frecuencia y lo reciente de tu uso de cada app.
- Modo edición manteniendo pulsado un icono o la tecla ⌥ Option: arrastra para reordenar y suelta apps unas sobre otras para crear carpetas. Las carpetas pueden ocupar varias páginas.
- Desinstalación limpia integrada: elimina una app desde el modo edición y AppPad borra también sus archivos residuales.
- El tamaño de la ventana se adapta a la pantalla, con porcentajes separados de ancho y alto; a tamaño completo puede cubrir la barra de menús y evita la muesca.
- Se abre en la pantalla donde está el ratón (opcional) y permanece en el Espacio donde se abrió, como el Launchpad original.

#### Portapapeles
- Historial del portapapeles para texto e imágenes, guardado de forma permanente; las imágenes se conservan aunque se borre el archivo original.
- Biblioteca guardada para los elementos más usados: activa “Guardados” junto al campo de búsqueda; los elementos guardados aparecen primero en la búsqueda.
- Se abre con ⌘. (biblioteca guardada: ⌘⌥.), pega con ⌘1–⌘0 y muestra un panel de vista previa a la derecha.
- Icono de la app de origen en cada elemento, filtros para tus apps más usadas y sintaxis de búsqueda `AppName::`.
- ⌘↩ muestra en el Finder la carpeta de origen de una imagen.
- Limpia el historial por antigüedad (última hora, día, semana… más de un año) sin tocar la biblioteca guardada.

#### Flujos de trabajo
- Panel de flujos de trabajo (⌘Space) que ejecuta Atajos de Apple, AppleScript y scripts de shell, y abre apps desde la misma búsqueda.
- Argumentos: escríbelos después del primer espacio, p. ej. `Set-Timer 10:00`. Tab completa el elemento seleccionado.
- Flujos integrados: Vaciar papelera, Configurar temporizador, Configurar alarma, Ajustar volumen, Silenciar, Salir de todas las apps y una calculadora con notación científica.
- Sistema de permisos con un sandbox real para los flujos de shell y AppleScript: Permitir una vez / No permitir / Permitir siempre.
- Importa flujos desde archivos JSON o enlaces, con identificadores únicos, revisiones y nombres en varios idiomas.
- Notificaciones de éxito y de error para cada flujo.
- Las apps y los flujos comparten una misma clasificación por uso.

#### Control de ventanas
- ⌃⌥← / ⌃⌥→ ajusta a la izquierda / derecha, alternando ½ → ⅓ → ⅔.
- ⌃⌥↩ maximiza, ⌃⌥⌫ restaura, ⌃⌥⌘↑ / ⌃⌥⌘↓ mueve a la pantalla anterior / siguiente.
- Todos los atajos son personalizables.

#### Atajos de apps
- Atajos de teclado globales para abrir cualquier app, con una lista de apps de la A a la Z y detección de conflictos.

#### Apariencia y General
- Campo de búsqueda, indicador de página y pestañas de ajustes con Liquid Glass.
- Tema: Automático / Claro / Oscuro.
- Fondos: blanco, gris claro, gris oscuro, fondo de pantalla o color personalizado, cada uno con su propia transparencia y desenfoque para los temas claro y oscuro. Los paneles de Portapapeles y de flujos de trabajo pueden seguir el fondo del Launchpad.
- ⌘⇧J / ⌘⇧K cambia entre Launchpad, Portapapeles y Flujos de trabajo con una animación de transformación fluida.
- Solo en la barra de menús (sin icono en el Dock salvo que lo fijes), apertura al iniciar sesión.
- Cambio opcional a la fuente de entrada ABC al abrir cada panel.
- Comportamiento configurable de Esc (cerrar de inmediato o borrar primero la búsqueda).
- Traducido a 10 idiomas: English, Deutsch, Español, Français, Italiano, 日本語, 한국어, Nederlands, 简体中文, 繁體中文.

#### Distribución
- Firmado con Developer ID y notarizado por Apple.
- Instálalo con Homebrew: `brew tap umindhub/tap && brew trust umindhub/tap && brew install --cask apppad`.
- Código fuente bajo AGPL-3.0. Los flujos integrados, el formato de flujos de trabajo y los flujos de terceros, bajo MIT.
