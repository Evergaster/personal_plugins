# Nothing Battery

Bloque de escritorio estilo Nothing: la bateria del periferico que elijas (audifonos, mouse, teclado), leida de BlueZ y upower.

Forma parte de la familia Nothing, que va un plugin por bloque para que cada uno
tenga su nombre en el selector: `nothing-clock`, `nothing-calendar`,
`nothing-weather` y `nothing-battery`. Se instalan por separado y puedes poner
solo los que quieras.

## Requisitos

`busctl` (systemd) y `upower` para la bateria.

## Instalacion

1. Copia la carpeta `nothing-battery/` a tu directorio de plugins, o anade este repo como
   fuente en **Settings -> Plugins -> Add source**.
2. Activa el plugin `evergaster/nothing-battery`.
3. Anade el bloque: **Desktop widgets -> Add widget**, tipo `evergaster/nothing-battery:battery`.
4. Colocalo y rotalo en el editor de widgets de escritorio. El tamano del
   contenido lo lleva su ajuste `scale`.

## Uso

- **Bateria**: nombre, icono y 10 puntos de nivel; se pinta en rojo por debajo del umbral. Al hacer clic se abre el selector de dispositivos.

## Ajustes

Compartido en **Settings -> Plugins** (engranaje del plugin):

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `accent` | `#D71921` | Color de acento (el rojo de Nothing). |

Propios del bloque, en el inspector del widget de escritorio:

| Clave | Defecto | Descripcion |
| --- | --- | --- |
| `scale` | 100 | Tamano del bloque en por ciento. |
| `device` | vacio | MAC o parte del nombre del dispositivo. |
| `device_poll_seconds` | `120` | Cada cuanto se relee la bateria. |
| `low_battery_threshold` | `20` | Umbral de rojo. |

## De donde salen los datos

Una llamada a BlueZ (`busctl` sobre `org.bluez`) y, para lo que no pasa por
Bluetooth, `upower`. Los dos listados se cruzan por MAC para no duplicar el
mismo aparato. Muchos audifonos solo publican un porcentaje global por BlueZ y
no las cifras izquierda/derecha por separado (eso requiere el protocolo SPP del
fabricante). Comprueba a mano con
`busctl --system --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects`
y `upower -e`.

## Precedencia del dispositivo

El ajuste `device` gana al arrancar; el selector del bloque lo sustituye en
caliente y el cambio se guarda en el directorio de datos del plugin. Si dejas
`device` vacio, el selector es la unica fuente. Vacio en ambos significa
"automatico": el primer periferico conectado que informe bateria.

## Nota de mantenimiento

Los modulos de `lib/` estan copiados en los plugins Nothing hermanos, porque
Noctalia no comparte codigo entre plugins. Si tocas uno, toca las copias: el test
de cada plugin compara su copia con la de los hermanos y avisa si se separan.

Autocomprobacion: `lua5.4 nothing-battery/test.luau` desde la raiz del repo.

## Licencia

MIT.
