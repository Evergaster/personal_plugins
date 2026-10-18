# Nothing Clock

Reloj de escritorio estilo Nothing: matriz de puntos NDot y la fecha corta.

Forma parte de la familia Nothing, que va un plugin por bloque para que cada uno
tenga su nombre en el selector: `nothing-clock`, `nothing-calendar`,
`nothing-weather` y `nothing-battery`. Se instalan por separado y puedes poner
solo los que quieras.

## Requisitos

Ninguno.

## Instalacion

1. Copia la carpeta `nothing-clock/` a tu directorio de plugins, o anade este repo como
   fuente en **Settings -> Plugins -> Add source**.
2. Activa el plugin `evergaster/nothing-clock`.
3. Anade el bloque: **Desktop widgets -> Add widget**, tipo `evergaster/nothing-clock:clock`.
4. Colocalo y rotalo en el editor de widgets de escritorio. El tamano del
   contenido lo lleva su ajuste `scale`.

## Uso

- **Reloj**: se repinta cada segundo; los segundos son opcionales.

## Ajustes

Compartido en **Settings -> Plugins** (engranaje del plugin):

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `accent` | `#D71921` | Color de acento (el rojo de Nothing). |

Propios del bloque, en el inspector del widget de escritorio:

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `scale` | 100 | Tamano del bloque en por ciento. |
| `hour_format` | `24` | Reloj de 24 o 12 horas. |
| `show_seconds` | `false` | Anade los segundos. |

## Nota de mantenimiento

Los modulos de `lib/` estan copiados en los plugins Nothing hermanos, porque
Noctalia no comparte codigo entre plugins. Si tocas uno, toca las copias: el test
de cada plugin compara su copia con la de los hermanos y avisa si se separan.

Autocomprobacion: `lua5.4 nothing-clock/test.luau` desde la raiz del repo.

## Licencia

MIT.
