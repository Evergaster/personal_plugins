# Nothing

Bloques de escritorio para [Noctalia](https://docs.noctalia.dev/noctalia/) con el
lenguaje visual de Nothing OS. No es una tarjeta unica: son cuatro bloques
independientes y tu montas el lienzo con los que quieras, cada uno donde y del
tamano que quieras.

| Bloque | Entrada | Que dibuja |
| --- | --- | --- |
| Reloj | `evergaster/nothing:clock` | Matriz de puntos NDot y la fecha corta debajo. |
| Calendario | `evergaster/nothing:calendar` | El mes en curso, con hoy marcado en rojo. |
| Clima | `evergaster/nothing:weather` | Estado actual y los tres dias siguientes. |
| Bateria | `evergaster/nothing:battery` | Periferico elegido, nivel en puntos y porcentaje. |

## Requisitos

- Noctalia v5+ con soporte de `plugin_api = 26` (usa `noctalia.getSetting`
  para leer `[location]`).
- `busctl` (systemd) y `upower` para la bateria.
- Conexion a internet para el clima (Open-Meteo, sin API key).

## Instalacion

1. Copia la carpeta `nothing/` a tu directorio de plugins, o anade este repo
   como fuente en **Settings -> Plugins -> Add source**.
2. Activa el plugin `evergaster/nothing`.
3. Anade los bloques que quieras: **Desktop widgets -> Add widget**, y elige el
   tipo (`evergaster/nothing:clock`, `:calendar`, `:weather` o `:battery`).
   Cuantos mas anadas, mas de uno por tipo si te apetece.
4. Colocalos y rotalos en el editor de widgets de escritorio. Para el tamano
   del contenido, cada bloque tiene su propio ajuste `scale`.

## Uso

- **Reloj**: se repinta cada segundo; los segundos son opcionales.
- **Calendario**: el mes actual completo, con el dia de hoy con un anillo en el
  color de acento. El primer dia de la semana es configurable.
- **Clima**: temperatura y estado actuales mas los tres dias siguientes. Si hay
  ciudad conocida, aparece bajo el estado.
- **Bateria**: nombre, icono y 10 puntos de nivel; se pinta en rojo por debajo
  del umbral. Al hacer clic se abre el selector de dispositivos.

## Ajustes

Compartido por los cuatro bloques, en **Settings -> Plugins** (engranaje del
plugin):

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `accent` | `#D71921` | Color de acento (el rojo de Nothing). |

Cada bloque tiene ademas los suyos, en el inspector del widget de escritorio:

| Clave | Bloque | Defecto | Descripcion |
| --- | --- | --- | --- |
| `scale` | los cuatro | `100` | Tamano del bloque en por ciento. |
| `hour_format` | reloj | `24` | Reloj de 24 o 12 horas. |
| `show_seconds` | reloj | `false` | Anade los segundos. |
| `week_start` | calendario | `monday` | Primer dia de la semana. |
| `temperature_unit` | clima | `metric` | Celsius o Fahrenheit. |
| `latitude` / `longitude` | clima | vacio | Coordenadas manuales. |
| `city` | clima | vacio | Nombre a geocodificar si no hay coordenadas. |
| `weather_refresh_minutes` | clima | `30` | Cada cuanto se consulta Open-Meteo. |
| `device` | bateria | vacio | MAC o parte del nombre del dispositivo. |
| `device_poll_seconds` | bateria | `120` | Cada cuanto se relee la bateria. |
| `low_battery_threshold` | bateria | `20` | Umbral de rojo. |

## De donde salen los datos

- **Clima**: Open-Meteo. Coordenadas en este orden: `latitude`/`longitude` del
  bloque, `[location]` de Noctalia (`latitude`/`longitude`, o `address`), y si
  no hay nada, se geocodifica `city` (o el `address` de Noctalia) con la API de
  geocodificacion de Open-Meteo.
- **Bateria**: una llamada a BlueZ (`busctl` sobre `org.bluez`) y, para lo que
  no pasa por Bluetooth, `upower`. Los dos listados se cruzan por MAC para no
  duplicar el mismo aparato. Muchos audifonos solo publican un porcentaje
  global por BlueZ y no las cifras izquierda/derecha por separado (eso requiere
  el protocolo SPP del fabricante).

## Precedencia del dispositivo

El ajuste `device` gana al arrancar; el selector de la tarjeta lo sustituye en
caliente y el cambio se guarda en el directorio de datos del plugin. Si dejas
`device` vacio, el selector es la unica fuente. Vacio en ambos significa
"automatico": el primer periferico conectado que informe bateria.

## Diagnostico

- Comprueba a mano: `busctl --system --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects`
  y `upower -e`.
- Si el clima no aparece, revisa que `[location]` este configurado en Noctalia o
  rellena `latitude`/`longitude`/`city` en los ajustes del bloque.
- Autocomprobacion de la logica pura (calendario, reticula, escala, codigos WMO
  y que no falte ninguna traduccion): `lua5.4 nothing/test.luau`

## Licencia

MIT.
