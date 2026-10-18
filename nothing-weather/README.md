# Nothing Weather

Bloque de escritorio estilo Nothing: el clima actual y los tres dias siguientes, via Open-Meteo (sin API key).

Forma parte de la familia Nothing, que va un plugin por bloque para que cada uno
tenga su nombre en el selector: `nothing-clock`, `nothing-calendar`,
`nothing-weather` y `nothing-battery`. Se instalan por separado y puedes poner
solo los que quieras.

## Requisitos

Conexion a internet para el clima (Open-Meteo, sin API key).

## Instalacion

1. Copia la carpeta `nothing-weather/` a tu directorio de plugins, o anade este repo como
   fuente en **Settings -> Plugins -> Add source**.
2. Activa el plugin `evergaster/nothing-weather`.
3. Anade el bloque: **Desktop widgets -> Add widget**, tipo `evergaster/nothing-weather:weather`.
4. Colocalo y rotalo en el editor de widgets de escritorio. El tamano del
   contenido lo lleva su ajuste `scale`.

## Uso

- **Clima**: estado y temperatura actuales mas los tres dias siguientes. Si hay ciudad conocida, aparece bajo el estado.

## Ajustes

Compartido en **Settings -> Plugins** (engranaje del plugin):

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `accent` | `#D71921` | Color de acento (el rojo de Nothing). |

Propios del bloque, en el inspector del widget de escritorio:

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `scale` | 100 | Tamano del bloque en por ciento. |
| `temperature_unit` | `metric` | Celsius o Fahrenheit. |
| `latitude` / `longitude` | vacio | Coordenadas manuales. |
| `city` | vacio | Nombre a geocodificar si no hay coordenadas. |
| `weather_refresh_minutes` | `30` | Cada cuanto se consulta Open-Meteo. |

## De donde salen los datos

Open-Meteo. Las coordenadas se buscan en este orden: `latitude`/`longitude` del
bloque, `[location]` de Noctalia (sus `latitude`/`longitude` o su `address`), y
si no hay nada, se geocodifica `city` (o el `address` de Noctalia) con la API de
geocodificacion de Open-Meteo.

Si el clima no aparece, revisa que `[location]` este configurado en Noctalia o
rellena `latitude`/`longitude`/`city` en los ajustes del bloque.

## Nota de mantenimiento

Los modulos de `lib/` estan copiados en los plugins Nothing hermanos, porque
Noctalia no comparte codigo entre plugins. Si tocas uno, toca las copias: el test
de cada plugin compara su copia con la de los hermanos y avisa si se separan.

Autocomprobacion: `lua5.4 nothing-weather/test.luau` desde la raiz del repo.

## Licencia

MIT.
