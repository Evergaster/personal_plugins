# Nothing Calendar

Bloque de escritorio estilo Nothing: el mes en curso, con hoy marcado en el color de acento.

Forma parte de la familia Nothing, que va un plugin por bloque para que cada uno
tenga su nombre en el selector: `nothing-clock`, `nothing-calendar`,
`nothing-weather` y `nothing-battery`. Se instalan por separado y puedes poner
solo los que quieras.

## Requisitos

Ninguno.

## Instalacion

1. Copia la carpeta `nothing-calendar/` a tu directorio de plugins, o anade este repo como
   fuente en **Settings -> Plugins -> Add source**.
2. Activa el plugin `evergaster/nothing-calendar`.
3. Anade el bloque: **Desktop widgets -> Add widget**, tipo `evergaster/nothing-calendar:calendar`.
4. Colocalo y rotalo en el editor de widgets de escritorio. El tamano del
   contenido lo lleva su ajuste `scale`.

## Uso

- **Calendario**: el mes actual completo, con el dia de hoy con un anillo en el color de acento. El primer dia de la semana es configurable.

## Ajustes

Compartido en **Settings -> Plugins** (engranaje del plugin):

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `accent` | `#D71921` | Color de acento (el rojo de Nothing). |

Propios del bloque, en el inspector del widget de escritorio:

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `scale` | 100 | Tamano del bloque en por ciento. |
| `week_start` | `monday` | Primer dia de la semana. |

## Nota de mantenimiento

Los modulos de `lib/` estan copiados en los plugins Nothing hermanos, porque
Noctalia no comparte codigo entre plugins. Si tocas uno, toca las copias: el test
de cada plugin compara su copia con la de los hermanos y avisa si se separan.

Autocomprobacion: `lua5.4 nothing-calendar/test.luau` desde la raiz del repo.

## Licencia

MIT.
