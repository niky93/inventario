# Inventario en linea

Aplicacion web sencilla para administrar productos y existencias desde una computadora o telefono.

## Funciones

- Crear, editar y eliminar productos.
- Registrar entradas, salidas y ajustes de existencias.
- Consultar los ultimos movimientos.
- Buscar por nombre o codigo y filtrar por categoria.
- Ver productos con stock bajo y el valor de compra del inventario.
- Exportar los productos a CSV para abrirlos en Excel.
- Usar los mismos datos desde distintos dispositivos mediante Supabase.
- Consultar unidades vendidas, ganancias e historial de cambios de nombre o precio.

## Configurar la base de datos compartida

1. Crea un proyecto gratuito en [Supabase](https://supabase.com/dashboard).
2. Abre `SQL Editor`, crea una consulta nueva, pega el contenido de `supabase-schema.sql` y ejecutala.
3. Ve a `Authentication` > `Users` y crea el usuario que utilizara el inventario.
4. Ve a `Project Settings` > `API`.
5. Copia la URL del proyecto y la clave publica o `publishable key`.
6. Reemplaza los marcadores dentro de `config.js` con esos dos valores.

La clave publica puede incluirse en el navegador. No copies una clave `service_role` ni una clave secreta dentro de `config.js`.

## Actualizar una base existente

Cuando la base de datos ya fue creada con una version anterior, ejecuta el contenido de `supabase-migration-sales-history.sql` desde `SQL Editor`. Esta migracion agrega el conteo de ventas, las ganancias y el historial de ediciones sin borrar productos existentes.

Para reiniciar automaticamente los contadores de vendidos y ganancias cuando las existencias lleguen a cero, ejecuta despues `supabase-migration-reset-sales-at-zero.sql`.

Para mostrar el resumen final de vendidos y ganancias en el ultimo movimiento antes de reiniciar los contadores, ejecuta despues `supabase-migration-cycle-summary.sql`.

## Publicar con Cloudflare Workers

1. Sube estos archivos al repositorio de GitHub.
2. En [Cloudflare Workers](https://dash.cloudflare.com/), elige `Create application` y conecta el repositorio.
3. Usa `main` como rama de produccion.
4. Deja vacio el comando de compilacion y conserva `npx wrangler deploy` como comando de despliegue.
5. Abre la direccion `*.workers.dev` que Cloudflare mostrara al terminar.

Cada cambio enviado a la rama `main` se publicara automaticamente.

## Probar localmente

Haz doble clic en `iniciar-servidor.bat` y abre `http://localhost:8080`.

Para acceder desde un telefono conectado a la misma red Wi-Fi, usa una de las direcciones marcadas como `En el telefono`.
