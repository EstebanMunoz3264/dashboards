// ============================================================
//  CONFIGURACIÓN DEL PORTAFOLIO — edita solo este archivo
// ============================================================
window.CONFIG = {
  nombre: "Esteban Muñoz",
  rol: "Data Analyst · Retención & Churn",
  titulo: "Ingeniero Estadístico",
  ubicacion: "Quito, Ecuador",
  intro:
    "Construyo tableros de Power BI de punta a punta: desde la consulta en Databricks hasta el modelo semántico y el diseño del reporte. Mi foco es la retención de clientes, el análisis de churn y la operación comercial en telecomunicaciones.",
  github: "https://github.com/EstebanMunoz3264/dashboards",
  linkedin: "https://www.linkedin.com/in/esteban-muñoz",
  email: "esteban_3264@hotmail.com",
  cv: "",                // ej: "assets/CV_Esteban_Munoz.pdf"

  experiencia: [
    { periodo: "2026 — hoy", cargo: "Analista de Datos · CRM Analytics, Fidelización y Retención", empresa: "Operador de telecomunicaciones (Ecuador)" },
    { periodo: "2023 — 2025", cargo: "Analista de Datos B2B · Churn involuntario y cobranzas", empresa: "Operador de telecomunicaciones (Ecuador)" },
    { periodo: "2019", cargo: "Ingeniería Estadística", empresa: "Universidad Central del Ecuador" }
  ],

  // ----------------------------------------------------------
  //  LINKS "PUBLICAR EN LA WEB" DE POWER BI
  //  Power BI Service → Archivo → Insertar informe → Publicar en la web (público)
  //  Pega aquí el link (src del iframe) de cada versión demo.
  //  Si queda vacío, la página muestra un aviso en lugar del reporte.
  // ----------------------------------------------------------
  embeds: {
    "indice-retencion": "",
    "flujos-desercion": "",
    "gestion-agencias": "",
    "cascada-retenidos": "",
    "control-tipificaciones": "",
    "operaciones-red": ""
  },

  // Captura opcional de cada tablero (ej: "img/indice-retencion.png")
  portadas: {
    "indice-retencion": "",
    "flujos-desercion": "",
    "gestion-agencias": "",
    "cascada-retenidos": "",
    "control-tipificaciones": "",
    "operaciones-red": ""
  }
};
