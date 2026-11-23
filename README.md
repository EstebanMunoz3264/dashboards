# Portafolio Power BI · Esteban Muñoz

Sitio estático (GitHub Pages) con mis tableros de Power BI. Por cada proyecto muestra:

1. **Dashboard interactivo** embebido desde Power BI Service (*Publicar en la web*, versión demo).
2. **Arquitectura** Databricks → Power BI.
3. **Código de extracción**: consultas Databricks SQL o Power Query (M), anonimizadas.
4. **Medidas DAX destacadas** y el archivo completo de medidas.

| Proyecto | Tema | Fuente |
|---|---|---|
| Índice de Retención | Retención por canal, metas, herramientas y ARPU | Delta Sharing |
| Flujos de Deserción | Bajas controlables, señales previas, cola de baja | Databricks SQL nativo |
| Gestión de Agencias | Retención, CSAT, ventas vs meta, FCR, tiempos | Databricks SQL nativo |
| Cascada de Retenidos | Supervivencia de cohortes de retenidos | Tabla Databricks |
| Control de Tipificaciones | Calidad de tipificación de cancelaciones | Databricks + Python |
| Operaciones de Red | TRF vs SLA, MTBF, uptime por nodo | Delta Sharing + Excel |

## Estructura

```
index.html            ← sitio (una sola página, rutas #/p/<proyecto>)
assets/config.js      ← ÚNICO archivo a editar: links de embed, LinkedIn, correo, CV, capturas
assets/projects.js    ← datos y código de cada proyecto (generado desde los .pbip/.pbix)
assets/app.js / style.css / vendor/prism.min.js
codigo/<proyecto>/    ← .sql, .pq (Power Query) y medidas.dax de cada tablero
img/                  ← capturas opcionales de cada tablero
```

## Publicar en GitHub Pages

1. Copia todo el contenido de esta carpeta a la raíz del repo `dashboards` y haz push.
2. El repo debe ser **público** (GitHub Pages gratis).
3. *Settings → Pages → Build and deployment → Deploy from a branch → `main` / `(root)`*.
4. En 1–2 minutos queda en `https://estebanmunoz3264.github.io/dashboards/`.

## Agregar el dashboard interactivo de cada proyecto

1. Crea una copia del `.pbix` con datos de demostración (sin información real de clientes).
2. Publícala desde una cuenta de Power BI **personal** (no la corporativa).
3. Power BI Service → *Archivo → Insertar informe → Publicar en la web (público)* → copia el `src` del iframe.
4. Pégalo en `assets/config.js` dentro de `embeds`, en el proyecto correspondiente.

> ⚠️ "Publicar en la web" deja el reporte visible para cualquiera con el link. Nunca publiques el reporte con datos reales.

## Capturas (opcional)

Guarda una imagen en `img/<proyecto>.png` y ponla en `portadas` dentro de `config.js`; se usa en la tarjeta de la portada y como fondo mientras no exista el embed.
