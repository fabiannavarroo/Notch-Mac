# NotchApp V1

## Direccion

Crear una app personal para macOS inspirada en la sensacion de Alcove: una isla compacta alrededor del notch, elegante, rapida y centrada en lo que esta pasando ahora mismo.

## Decisiones

- Uso: personal, no App Store por ahora.
- Aparicion: cuando haya actividad, al pasar el raton o con hotkey.
- Hotkey inicial: `Option + Space`.
- Interfaz: isla negra/glass, compacta y expandible.
- App: solo barra de menu, sin icono en Dock.
- macOS: versiones recientes primero.
- Prioridad: parecerse a la experiencia de Alcove antes que meter muchas funciones.

## Funciones V1

- Isla flotante centrada arriba, cerca del notch.
- Estado compacto con arte/titulo o placeholder.
- Estado expandido con portada, titulo, artista, progreso y controles.
- Controles de media: anterior, play/pause y siguiente.
- Menu bar extra con mostrar/ocultar, expandir, controles y salir.
- Lectura de Now Playing global mediante un helper Swift con `MediaRemote` como integracion experimental.
- Capa de eventos/notificaciones preparada para investigar reflejo de notificaciones externas.

## Riesgos Tecnicos

- `MediaRemote` es una API privada de macOS. Sirve para una app personal, pero puede romperse con actualizaciones.
- El helper Swift actual usa `/usr/bin/swift`, que desbloquea la lectura global en prototipo pero no es la arquitectura final ideal.
- macOS no ofrece una API publica limpia para leer todas las notificaciones de otras apps.
- La posicion exacta del notch depende de pantalla, safe areas y configuracion multi-monitor.

## Siguiente Bloque

- Ajustar posicion visual exacta en tu Mac.
- Comprobar si `MediaRemote` devuelve titulo/artista con Spotify, Music, Safari y YouTube.
- Decidir como tratar notificaciones externas: accesibilidad, automatizaciones, logs o integraciones por app.
- Crear pantalla de ajustes si empezamos a necesitar opciones persistentes.
