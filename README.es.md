# LPlayer

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Español**

Un reproductor de vídeo local para macOS, creado con AppKit y libmpv. Los atajos de teclado hacen que recorrer vídeos, desplazarse por ellos y controlar la reproducción sea fluido, para que puedas concentrarte en el vídeo.

## Funciones

- **Atajos de teclado.** Recorre vídeos, desplázate por ellos y ajusta la reproducción con controles ágiles y personalizables.
- **Reproducción local.** Abre archivos o carpetas, arrastra vídeos a la ventana o ábrelos desde Finder. La compilación estándar busca en segundo plano los vídeos de la misma carpeta y los subtítulos correspondientes.
- **Vistas previas en la lista.** Haz clic en un vídeo para reproducirlo o recorre la lista con el teclado para ver una vista previa en miniatura y sin sonido antes de confirmar. Hay diseños compactos y con vistas previas grandes.
- **Volumen global.** Los cambios de volumen se aplican a todos los vídeos y se conservan al cambiar de archivo y reiniciar la aplicación. El historial antiguo de un vídeo no puede sustituir el nivel actual.
- **Reanudación y reproducción privada.** Restaura el progreso, la velocidad, los subtítulos y la selección de pista de audio de cada archivo. La reproducción privada no añade historial de visualización ni permisos de acceso persistentes a archivos.
- **Trackpad y línea de tiempo.** Pellizca para ampliar hasta 5×, desplaza la imagen con dos dedos y sitúa el puntero sobre la línea de tiempo para ver una miniatura independiente.
- **Presentación nativa.** Controles de AppKit, controles de reproducción que se ocultan automáticamente, un logotipo tipográfico en Manrope y una barra lateral de atajos no modal.

La interfaz de la aplicación admite actualmente **inglés** y **chino simplificado**. Las traducciones del README que aparecen arriba son idiomas de la documentación; no añaden idiomas a la interfaz de la aplicación.

## Compilar y ejecutar

Requiere macOS 13 o posterior, Xcode Command Line Tools y Homebrew. La compilación local estándar se ha validado en Apple Silicon.

Desde la raíz del repositorio:

```sh
brew install mpv pkg-config
./scripts/build-app.sh
open dist/LPlayer.app
```

También puedes hacer doble clic en [`打开LPlayer.command`](打开LPlayer.command). El lanzador compila la aplicación cuando es necesario y la abre; vuelve a compilarla tras los cambios en el código fuente.

Al iniciar, utiliza **Open Video…**, pulsa `⌘O`, arrastra un vídeo a la ventana o prueba una de las tres películas de demostración incluidas. Puedes elegir LPlayer en el menú **Abrir con** de Finder; no cambia automáticamente el reproductor predeterminado del sistema.

Esta es una compilación de desarrollo local con firma ad hoc. No se ha publicado un instalador firmado con Developer ID y notarizado.

## Idiomas y ajustes

La aplicación se inicia en **inglés**, con independencia del idioma de macOS, y recuerda tu selección. Cambia entre inglés y chino simplificado en **Settings → General → Language** o mediante **LPlayer → Language**.

El cambio de idioma actualiza los menús, las ayudas emergentes, los controles rápidos, la lista de reproducción, la ayuda de atajos y los mensajes de error de reproducción. Los nombres de los archivos multimedia y el texto de los subtítulos conservan su contenido original. Los diálogos nativos del sistema utilizan el idioma seleccionado al iniciar la aplicación.

Los ajustes contienen las páginas **General**, **Shortcuts** y **About**. Ábrelos desde **LPlayer → Settings…**, el menú **More** de los controles de reproducción o la parte inferior de los controles rápidos. `⌘,` abre directamente la página **Shortcuts**. Los ajustes generales también incluyen el perfil de mano predeterminado y la sensibilidad del desplazamiento de la imagen.

## Controles del teclado

Estos son los perfiles predeterminados actuales. Los perfiles personalizados anteriormente conservan sus asignaciones efectivas durante las actualizaciones; restablecer los atajos de una mano adopta los nuevos valores predeterminados.

| Acción | Mano izquierda | Mano derecha |
| --- | --- | --- |
| Reproducir / pausar | `Space` | `Space` |
| Vídeo anterior / siguiente | `W` / `S` | `I` / `K` |
| Retroceder / avanzar 5 segundos | `A` / `D` | `J` / `L` |
| Retroceder / avanzar 30 segundos | `Shift+A` / `Shift+D` | `Shift+J` / `Shift+L` |
| Subir / bajar el volumen | `Shift+W` / `Shift+S` | `Shift+I` / `Shift+K` |
| Reducir / aumentar la velocidad | `Q` / `E` | `U` / `O` |
| Velocidad normal | `R` | `P` |
| Lista de reproducción | `T` | `'` (también `B`) |
| Controles rápidos | `C` | `,` |
| Ayuda de atajos | `V` | `Y` |
| Pantalla completa | `F` | `H` |
| Mostrar / ocultar subtítulos | `G` | `;` |
| Deshacer el último salto | `Z` | `M` |
| Ampliar / reducir la imagen | `3` / `2` (también `=` / `-`) | `9` / `8` (también `=` / `-`) |
| Ajustar el vídeo a la ventana | `1` / `0` | `7` / `0` |

`W/A/S/D` e `I/J/K/L` corresponden a `↑/←/↓/→`. Su comportamiento depende del modo visible:

| Modo | Arriba / abajo | Izquierda / derecha | Space / Enter |
| --- | --- | --- | --- |
| Reproducción | Vídeo anterior / siguiente | Saltar 5 segundos | Space reproduce / pausa |
| Lista de reproducción | Seleccionar y previsualizar sin sonido | Saltar 5 segundos en el vídeo actual | Reproducir el elemento seleccionado |
| Controles rápidos | Seleccionar un control | Ajustar su valor | Activar o restablecer el control |

Durante la reproducción, `Shift+↑/↓` ajusta el volumen y `Shift+←/→` salta 30 segundos, igual que las teclas de letras correspondientes. En la lista de reproducción, solo las direcciones verticales se reservan para seleccionar; las teclas horizontales saltan en el vídeo que se está reproduciendo, aunque haya otra fila seleccionada. Con Shift el salto es de 30 segundos y mantener pulsada la tecla repite el salto. Los controles rápidos conservan todas las direcciones, incluidas las combinaciones con Shift, para navegar y ajustar. Mantener pulsada una tecla de cambio de vídeo no salta varios vídeos.

Otros atajos:

- `⌘O`: abrir un vídeo o una carpeta.
- `⌘L`: mostrar u ocultar la lista de reproducción.
- `⌘[` / `⌘]`: vídeo anterior / siguiente.
- `⌘N`: activar o desactivar la reproducción privada.
- `0` o `⌘0`: ajustar la imagen a la ventana.
- `?`, `/` o `⌘/`: mostrar u ocultar la ayuda de atajos.
- `Esc`: cerrar el panel o la barra lateral activos y, después, salir de pantalla completa.

La referencia de atajos no es modal: los comandos de reproducción siguen disponibles mientras está abierta. Los diálogos de archivos y los campos de texto editables conservan la entrada de texto habitual.

### Lista de reproducción y controles rápidos

La lista de reproducción comienza cerrada. Un clic del ratón reproduce una fila de inmediato; la navegación con el teclado la selecciona e inicia una vista previa sin sonido tras una breve pausa. `Home` / `End` selecciona el primer / último elemento. Enter o Space confirma sin cerrar la navegación por la lista. Confirmar el vídeo actual lo reanuda desde su posición actual; un vídeo terminado puede comenzar de nuevo.

La lista de reproducción y los controles rápidos son mutuamente excluyentes. Los controles rápidos conservan 15 acciones: velocidad, volumen, zoom, sensibilidad del desplazamiento de la imagen, visibilidad de subtítulos, sincronización de subtítulos, pista de audio, pista de subtítulos, perfil de mano, reproducción privada, abrir archivos o carpetas, acceso a carpetas, lista de reproducción, idioma y personalización de atajos. El pie fijo **Settings…** es un elemento adicional seleccionable con el teclado.

El botón de subtítulos los muestra u oculta directamente. El botón de velocidad abre los controles rápidos en la fila de velocidad; utiliza las teclas de navegación horizontal para ajustarla en pasos de 0,1×.

### Personalizar atajos

En **Settings → Shortcuts**, busca entre las 29 acciones y registra asignaciones independientes para cada mano. Se admiten letras, números, teclas de función y combinaciones con modificadores. Pulsa Esc para cancelar la captura o Delete para borrar una asignación principal editable. Se rechazan los conflictos y los atajos reservados; la navegación fija y los atajos alternativos de menú siguen disponibles. Los cambios se aplican de inmediato y se guardan localmente.

## Volumen, historial y privacidad

El volumen es una preferencia global del reproductor compartida por todos los archivos, incluida la reproducción privada, y se conserva al reiniciar la aplicación. El campo de volumen de los marcadores antiguos se mantiene por compatibilidad de formato y ya no se restaura.

La reproducción normal conserva los 30 archivos más recientes en `~/Library/Application Support/PalmPlayer/history.json`. Restaura el progreso, la velocidad, la sincronización y visibilidad de los subtítulos, y las pistas de audio y subtítulos seleccionadas. Los archivos terminados vuelven a empezar desde el principio. El historial se escribe en segundo plano; el identificador original de la aplicación y la ubicación del historial mantienen la compatibilidad con el nombre anterior, PalmPlayer.

La compilación local estándar abre el archivo seleccionado inmediatamente y, después, busca los vídeos de la misma carpeta y los subtítulos correspondientes sin bloquear la reproducción. La búsqueda se limita a ese directorio, omite archivos ocultos y subdirectorios, y aplica un orden natural, como episodios 1, 2 y 10. Si seleccionas explícitamente varios archivos, se conserva su orden de selección. Cuando termina un vídeo, la reproducción avanza al siguiente elemento de la cola.

La reproducción privada guarda el progreso normal antes de activarse y, después, deja de leer o escribir el historial de los archivos que se abran. Esos archivos empiezan desde el principio; el historial existente se conserva. El volumen global y las preferencias de la aplicación siguen guardándose. Puedes borrar el historial de visualización desde el menú **File**.

## Trackpad y vistas previas

Pellizca sobre el vídeo para ampliar alrededor del puntero. Con la imagen ampliada, desliza dos dedos sin presionar el trackpad para moverla; el movimiento sigue a los dedos y se detiene al levantarlos. La sensibilidad se puede ajustar del 25% al 150%, con un 100% como valor predeterminado. La imagen se mantiene dentro de sus límites y cambiar de vídeo restablece el zoom y el desplazamiento.

Pulsa `=` (o `+`) para ampliar y `-` para reducir en pasos de 25 puntos porcentuales, entre el 100% y el 500%. Mantén pulsada la tecla para ajustar continuamente. Para usar una sola mano, la disposición izquierda añade `2` / `3` para reducir / ampliar y `1` para ajustar a la ventana; la derecha añade `8` / `9` y `7`. Estas teclas numéricas no necesitan modificadores y siguen la disposición activa. Cada alias está disponible mientras la acción de zoom correspondiente conserve su tecla principal predeterminada. Si un número ya está asignado a otra acción personalizada, se respeta esa asignación. Las teclas principales de zoom siguen siendo personalizables en los ajustes.

Da dos toques con dos dedos para alternar entre zoom de 2× y ajuste a la ventana, o pulsa `0` / `⌘0` para restablecer. Los gestos que comienzan sobre la lista, los controles o la barra lateral de ayuda conservan la interacción de esa superficie.

Las miniaturas de la línea de tiempo utilizan un decodificador independiente de baja resolución y una caché en memoria, sin cambiar la posición de la reproducción principal. Las vistas previas en movimiento de la lista también están aisladas y tienen el audio desactivado. Las imágenes de vista previa no se escriben en el disco.

## Prototipo HTML interactivo

Se incluye un prototipo exclusivamente de frontend en [`prototypes/lplayer`](prototypes/lplayer/README.md). Utiliza vídeos, fuentes e iconos locales, sin dependencias de npm:

```sh
python3 prototypes/lplayer/serve.py
```

Abre <http://127.0.0.1:4178/>. El prototipo tiene actualmente una interfaz en chino. Sus contextos de teclado reflejan los del reproductor nativo y se indican las funciones que requieren decodificación nativa o API de macOS. Los archivos locales se reproducen mediante URL de objeto del navegador y no se suben; los formatos compatibles con el navegador difieren de los de libmpv. El prototipo no implementa el backend nativo de historial ni de permisos de archivos.

Las tres películas de demostración incluidas son clips sin sonido creados a partir de imágenes estáticas de paisajes generadas por IA, con un movimiento lento de cámara mediante FFmpeg y subtítulos SRT; **no son grabaciones de lugares reales**. Consulta la [procedencia de las demostraciones](Resources/Demo/README.txt).

## Validación

Las comprobaciones adicionales de reproducción requieren las herramientas de línea de comandos de FFmpeg:

```sh
brew install ffmpeg
./scripts/check-core.sh
./scripts/check-viewport.sh
./scripts/make-demo.sh
./scripts/check-engine.sh
./scripts/check-gestures.sh
./scripts/check-thumbnails.sh
./scripts/check-seeking.sh production-final Sources/PalmPlayer
python3 scripts/interaction/run-controller.py
```

Las comprobaciones principales verifican asignaciones, modificadores, historial, persistencia y migración de atajos. El [banco de pruebas del controlador](scripts/interaction/README.md) ejecuta el manejador real con medios generados y almacenamiento aislado, incluido el volumen global entre archivos con historial y tras un reinicio. Los informes generados se guardan en `artifacts/`, excluido de Git; las pruebas históricas no se incluyen con el código fuente.

Las comprobaciones del motor y de gestos pueden mostrar brevemente ventanas de prueba independientes. El banco de pruebas oculto del controlador utiliza eventos locales y no demuestra el comportamiento de la entrada física del teclado, el foco en primer plano, los Spaces de pantalla completa ni los diálogos del sistema. Estas comprobaciones no sustituyen las pruebas con dispositivos y medios reales. Consulta las [notas de rendimiento (en chino)](docs/PERFORMANCE.md) para ver las mediciones previas y su alcance.

## Vista previa en sandbox y distribución

Una vista previa independiente en sandbox utiliza dependencias controladas y una identidad y un contenedor propios para la aplicación. Su plataforma objetivo documentada es Apple Silicon y macOS 15 o posterior. No se ha enviado a la Mac App Store ni ha recibido su aprobación:

```sh
./scripts/build-store-deps.sh
./scripts/build-store-app.sh --preview
./scripts/check-store-app.py
```

El sandbox reproduce inicialmente solo el archivo seleccionado. Utiliza `⌘⇧O` para conceder acceso de solo lectura a la carpeta y permitir la búsqueda de otros vídeos y subtítulos correspondientes; los permisos utilizan marcadores con ámbito de seguridad y se pueden borrar desde el menú File. El modo privado no añade permisos persistentes ni historial de visualización.

La compilación estándar incluye las bibliotecas ajenas al sistema que su ejecutable utiliza realmente, reescribe sus rutas de carga, las valida y firma la aplicación ad hoc. Las compilaciones sustituyen `dist/LPlayer.app` de forma atómica tras conservar una copia de seguridad y no reinician un reproductor en ejecución. La fuente Manrope incluida no necesita instalarse en el sistema.

Las versiones de las dependencias y los avisos de licencia están en [`Resources/licenses`](Resources/licenses/README.md). La compilación estándar basada en Homebrew incluye componentes con licencia GPL; el sandbox utiliza una configuración de dependencias diferente. Los avisos incluidos no constituyen una distribución completa del código fuente correspondiente. Consulta la [preparación de versiones (en chino)](docs/APP_STORE_RELEASE.md) y la [validación histórica del sandbox (en chino)](docs/APP_STORE_VALIDATION.md).

El renderizador utiliza actualmente la canalización OpenGL de libmpv. No se han implementado el renderizado con Metal, la búsqueda de subtítulos en línea, la calibración automática de su sincronización ni funciones de IA. No se han validado exhaustivamente la fidelidad HDR, el paso directo de audio, todos los códecs ni el consumo energético entre dispositivos.
