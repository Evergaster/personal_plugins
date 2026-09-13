# Nothing Buds

Plugin para [Noctalia](https://docs.noctalia.dev/noctalia/) que controla audifonos
Nothing/CMF (Nothing Ear, Ear(a), CMF Buds Pro, etc.) a traves del CLI
[openNothing](https://github.com/evergaster/openNothing) y muestra su bateria en la barra.

## Requisitos

- [openNothing](https://github.com/evergaster/openNothing) instalado y disponible en `PATH`.
- Audifonos Nothing/CMF conectados por Bluetooth (SPP/RFCOMM).
- Noctalia v5+ con soporte de `plugin_api = 24`.

## Instalacion

1. Clona `personal_plugins` donde Noctalia lea su catalogo de plugins, o copia la carpeta
   `opennothing/` a tu directorio de plugins.
2. Agrega la entrada al `catalog.toml` (ver `catalog.toml` del repo) o instala via el
   catalogo de la shell.
3. En Settings -> Plugins configura el plugin: MAC, canal RFCOMM, modelo y comando.
4. Agrega el widget "buds" del plugin `evergaster/opennothing` a tu barra.

## Uso

- **Widget**: muestra la bateria izquierda/derecha (rojo si baja del umbral). Clic abre el panel.
- **Panel**: bateria (izq/der/estuche), ANC, graves (on/off + nivel 0-10), baja latencia,
  audio espacial (+ seguimiento de cabeza), ecualizador y boton de actualizar.

El plugin lee el estado con `opennothing status` y escribe con
`opennothing anc|low-latency|bass-boost|spatial-audio|eq`. Las escrituras se serializan:
nunca se lanzan dos comandos simultaneos contra el dispositivo.

## Configuracion

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `command` | `opennothing` | Ejecutable del CLI. |
| `mac` | `2C:BE:EE:70:76:30` | MAC de los audifonos. |
| `channel` | `15` | Canal RFCOMM (SPP). |
| `model` | `B172` | ID de modelo esperado. |
| `timeout` | `5.0` | Timeout Bluetooth (s). |
| `poll_interval_ms` | `60000` | Intervalo de consulta de estado. |
| `scripted` | `false` | Modo demo sin Bluetooth (`opennothing --scripted`). |
| `show_percent` | `true` | Mostrar porcentajes en la barra. |
| `low_battery_threshold` | `20` | Umbral de bateria baja (%). |

## Diagnostico

- Prueba el CLI antes que el plugin: `opennothing status`.
- `--scripted` permite probar el plugin sin hardware (valida parseo y UI).
- Si el widget muestra "Sin conexion", revisa que el canal/MAC sean correctos y el
  dispositivo este emparejado. El error del CLI se muestra en el panel.

## Licencia

MIT.