(() => {
  const C = window.CONFIG || {};
  const PROJECTS = (window.PROJECTS || []).map(p => ({
    ...p,
    embed: (C.embeds && C.embeds[p.slug]) || p.embed || "",
    cover: (C.portadas && C.portadas[p.slug]) || p.cover || ""
  }));
  const app = document.getElementById("app");
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fmt = n => n >= 1000 ? (n / 1000).toFixed(1).replace(".0", "") + "k" : String(n);

  // ---------- DAX grammar for Prism ----------
  if (window.Prism) {
    Prism.languages.dax = {
      comment: [{ pattern: /\/\*[\s\S]*?\*\//, greedy: true }, { pattern: /(--|\/\/).*/, greedy: true }],
      string: { pattern: /"(?:[^"]|"")*"/, greedy: true },
      table: { pattern: /'(?:[^']|'')+'(?=\[)?/, greedy: true },
      measure: { pattern: /\[[^\]]+\]/, greedy: true },
      keyword: /\b(?:VAR|RETURN|IN|NOT|AND|OR|TRUE|FALSE|DEFINE|EVALUATE|ORDER BY|ASC|DESC|SKIP|DENSE)\b/i,
      function: /\b[A-Z][A-Z0-9.]*(?=\s*\()/,
      variable: /\b_[A-Za-z0-9_]+\b/,
      number: /\b\d+(?:\.\d+)?\b/,
      operator: /&&|\|\||<=|>=|<>|[-+*\/=<>&]/,
      punctuation: /[(),{}]/
    };
  }
  const LANG = { sql: "sql", m: "powerquery", dax: "dax" };
  const LANG_LABEL = { sql: "SQL", m: "M", dax: "DAX" };
  const highlight = (code, lang) => {
    const g = window.Prism && Prism.languages[LANG[lang]];
    return g ? Prism.highlight(code, g, LANG[lang]) : esc(code);
  };
  const codeBlock = (code, lang) => {
    if (lang === "dax" && !code.includes("\n") && /\bRETURN\b/.test(code)) code = code.replace(/\s+(RETURN)\s+/, "\n$1\n    ").replace(/\s+(VAR)\s+/g, "\n$1 ").trim();
    const n = code.split("\n").length;
    const gutter = Array.from({ length: n }, (_, i) => i + 1).join("\n");
    return `<div class="code-body"><pre class="gutter" aria-hidden="true">${gutter}</pre><pre class="code"><code>${highlight(code, lang)}</code></pre></div>`;
  };

  const toast = msg => {
    let t = document.querySelector(".toast");
    if (!t) { t = document.createElement("div"); t.className = "toast"; document.body.appendChild(t); }
    t.textContent = msg; t.classList.add("show");
    clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove("show"), 1600);
  };
  const copy = text => navigator.clipboard?.writeText(text).then(() => toast("Código copiado"), () => toast("No se pudo copiar"));

  const miniViz = seed => {
    const bars = Array.from({ length: 10 }, (_, i) => 30 + Math.round(60 * Math.abs(Math.sin(seed * 1.7 + i * 0.9))));
    return `<div class="mini" aria-hidden="true"><div class="k"></div><div class="k"></div><div class="k"></div><div class="k"></div>
      <div class="chart">${bars.map(h => `<i style="height:${h}%"></i>`).join("")}</div><div class="donut"><span></span></div></div>`;
  };

  // ---------- views ----------
  function home() {
    const tot = PROJECTS.reduce((a, p) => {
      a.m += p.stats.medidas; a.q += p.stats.consultas; a.l += p.stats.lineas_sql; a.p += p.stats.paginas; return a;
    }, { m: 0, q: 0, l: 0, p: 0 });
    const tags = ["Todos", ...new Set(PROJECTS.map(p => p.tag))];
    app.innerHTML = `
    <div class="view">
      <section class="hero">
        <span class="eyebrow"><span class="dot"></span>${esc(C.rol)} · ${esc(C.ubicacion)}</span>
        <h1>Dashboards que explican<br/><span class="grad">por qué se van los clientes.</span></h1>
        <p class="lead">${esc(C.intro)}</p>
        <div class="hero-actions">
          <a class="btn primary" href="#proyectos">Ver proyectos ↓</a>
          ${C.linkedin ? `<a class="btn" href="${esc(C.linkedin)}" target="_blank" rel="noopener">LinkedIn ↗</a>` : ""}
          ${C.cv ? `<a class="btn" href="${esc(C.cv)}" target="_blank" rel="noopener">Descargar CV</a>` : ""}
          ${C.email ? `<a class="btn" href="mailto:${esc(C.email)}">Contacto</a>` : ""}
        </div>
        <div class="kpis">
          <div class="kpi"><b>${PROJECTS.length}</b><span>tableros en producción</span></div>
          <div class="kpi"><b>${tot.p}</b><span>páginas de reporte</span></div>
          <div class="kpi"><b>${tot.m}</b><span>medidas DAX</span></div>
          <div class="kpi"><b>${fmt(tot.l)}</b><span>líneas de SQL en Databricks</span></div>
        </div>
      </section>
      <div class="section-head" id="proyectos">
        <div><h2>Proyectos</h2><p>Cada tablero incluye el reporte interactivo, el código de extracción y las medidas clave.</p></div>
        <div class="filters">${tags.map((t, i) => `<button class="chip-btn${i ? "" : " on"}" data-tag="${esc(t)}">${esc(t)}</button>`).join("")}</div>
      </div>
      <section class="grid">${PROJECTS.map((p, i) => `
        <a class="card" href="#/p/${p.slug}" style="--c:${p.color}" data-tag="${esc(p.tag)}">
          <div class="card-visual">${p.cover ? `<img src="${esc(p.cover)}" alt="Vista del tablero ${esc(p.title)}" loading="lazy"/>` : miniViz(i + 1)}</div>
          <span class="card-cta" aria-hidden="true">→</span>
          <div class="card-body">
            <span class="tag">${esc(p.tag)}</span>
            <h3>${esc(p.title)}</h3>
            <p>${esc(p.summary)}</p>
            <div class="card-meta"><span><b>${p.stats.paginas}</b> páginas</span><span><b>${p.stats.medidas}</b> medidas</span><span><b>${p.stats.consultas}</b> ${p.stats.consultas === 1 ? "consulta" : "consultas"}</span></div>
          </div>
        </a>`).join("")}
      </section>
    </div>`;
    app.querySelectorAll(".chip-btn").forEach(b => b.addEventListener("click", () => {
      app.querySelectorAll(".chip-btn").forEach(x => x.classList.toggle("on", x === b));
      const t = b.dataset.tag;
      app.querySelectorAll(".card").forEach(c => { c.style.display = t === "Todos" || c.dataset.tag === t ? "" : "none"; });
    }));
  }

  function project(slug) {
    const i = PROJECTS.findIndex(p => p.slug === slug);
    if (i < 0) return home();
    const p = PROJECTS[i];
    const prev = PROJECTS[(i - 1 + PROJECTS.length) % PROJECTS.length];
    const next = PROJECTS[(i + 1) % PROJECTS.length];
    const hasSQL = p.queries.some(q => q.lang === "sql");
    const flow = hasSQL
      ? [["Fuente", "Databricks · Lakehouse", "Capas silver / gold"], ["Extracción", "Consulta nativa SQL", `${p.stats.consultas} consultas, toda la lógica en Databricks`], ["Modelo", "Modelo semántico", `${p.stats.medidas} medidas DAX`], ["Reporte", "Power BI Service", `${p.stats.paginas} páginas`]]
      : [["Fuente", "Databricks · Lakehouse", p.source], ["Extracción", "Power Query (M)", `${p.stats.consultas} consultas`], ["Modelo", "Modelo semántico", `${p.stats.medidas} medidas DAX`], ["Reporte", "Power BI Service", `${p.stats.paginas} páginas`]];

    app.innerHTML = `
    <div class="view" style="--c:${p.color}">
      <a class="back" href="#/">← Todos los proyectos</a>
      <section class="p-hero" style="--c:${p.color}">
        <span class="tag">${esc(p.tag)}</span>
        <h1>${esc(p.title)}</h1>
        <p class="summary">${esc(p.summary)}</p>
        <div class="stack">${p.stack.map(s => `<span>${esc(s)}</span>`).join("")}</div>
        <div class="p-stats">
          <div class="kpi"><b>${p.stats.paginas}</b><span>páginas</span></div>
          <div class="kpi"><b>${p.stats.medidas}</b><span>medidas DAX</span></div>
          <div class="kpi"><b>${p.stats.consultas}</b><span>consultas de extracción</span></div>
          <div class="kpi"><b>${p.stats.lineas_sql ? fmt(p.stats.lineas_sql) : "M"}</b><span>${p.stats.lineas_sql ? "líneas de SQL" : "Power Query"}</span></div>
        </div>
      </section>

      <section class="block">
        <div class="block-title"><span class="num">01</span><h2>Dashboard interactivo</h2></div>
        <p class="block-sub">Navega el reporte tal como está publicado en Power BI Service: filtros, segmentadores y drill-through funcionan.</p>
        <div class="embed-wrap">
          <div class="embed-bar"><i></i><i></i><i></i><span class="url">app.powerbi.com · ${esc(p.title)}</span>
            ${p.embed ? `<a class="full" href="${esc(p.embed)}" target="_blank" rel="noopener">Pantalla completa ↗</a>` : ""}</div>
          <div class="embed-frame">
            ${p.embed
              ? `<iframe title="${esc(p.title)}" src="${esc(p.embed)}" loading="lazy" allowfullscreen></iframe>`
              : `<div class="embed-empty">${p.cover ? `<img src="${esc(p.cover)}" alt="Captura del tablero ${esc(p.title)}"/>` : `<div class="ghost">${"<div></div>".repeat(8)}</div>`}
                 <div class="msg"><b>Versión demo en preparación</b><span>El reporte interactivo se publicará aquí con datos de demostración.</span></div></div>`}
          </div>
        </div>
        <div class="pages">${p.pages.map((pg, k) => `<span><em>${String(k + 1).padStart(2, "0")}</em>${esc(pg)}</span>`).join("")}</div>
      </section>

      <section class="block two">
        <div class="panel"><h3>Qué resuelve</h3><ul class="checks">${p.highlights.map(h => `<li>${esc(h)}</li>`).join("")}</ul></div>
        <div class="panel"><h3>Fuente de datos</h3><p style="margin:0 0 10px;font-size:15px">${esc(p.source)}</p>
          <p style="margin:0;color:var(--muted);font-size:14px">${hasSQL
            ? "Las transformaciones se ejecutan en Databricks mediante consultas nativas; Power BI recibe tablas listas para el modelo, lo que reduce el tiempo de actualización y mantiene una sola versión de la lógica de negocio."
            : "Power BI lee tablas de la capa gold/temporal de Databricks y aplica en Power Query solo la limpieza final (tipos, filtros y homologación de valores)."}</p></div>
      </section>

      <section class="block">
        <div class="block-title"><span class="num">02</span><h2>Arquitectura</h2></div>
        <div class="flow">${flow.map(f => `<div class="node"><small>${f[0]}</small><b>${esc(f[1])}</b><span>${esc(f[2])}</span></div>`).join("")}</div>
      </section>

      <section class="block">
        <div class="block-title"><span class="num">03</span><h2>Código de extracción</h2></div>
        <p class="block-sub">${hasSQL ? "Consultas en Databricks SQL que alimentan cada tabla del modelo." : "Consultas de Power Query (M) que conectan el modelo con Databricks."} Identificadores de conexión anonimizados.</p>
        <div class="code-shell" id="q-shell">
          <div class="tabs" role="tablist">${p.queries.map((q, k) => `<button class="tab${k ? "" : " on"}" role="tab" data-k="${k}"><span class="lang ${q.lang}">${LANG_LABEL[q.lang]}</span>${esc(q.name)}</button>`).join("")}</div>
          <div id="q-body"></div>
        </div>
      </section>

      <section class="block">
        <div class="block-title"><span class="num">04</span><h2>Medidas DAX destacadas</h2></div>
        <p class="block-sub">Una muestra de las ${p.stats.medidas} medidas del modelo. <a href="${esc(p.daxFile)}" target="_blank" rel="noopener" style="color:var(--c)">Ver todas ↗</a></p>
        <div class="dax-grid">${p.dax.map(m => `<div class="dax-card"><header>${esc(m.name)}</header>${codeBlock(m.expr, "dax")}</div>`).join("")}</div>
      </section>

      <nav class="pnav">
        <a href="#/p/${prev.slug}"><small>← Anterior</small><b>${esc(prev.title)}</b></a>
        <a class="next" href="#/p/${next.slug}"><small>Siguiente →</small><b>${esc(next.title)}</b></a>
      </nav>
    </div>`;

    const body = document.getElementById("q-body");
    const showQuery = k => {
      const q = p.queries[k];
      const lines = q.code.split("\n").length;
      body.innerHTML = `<div class="code-head"><span class="fname">${esc(q.file.split("/").pop())}</span><span>${esc(q.kind)} · ${lines} líneas</span>
        <span class="actions"><button class="mini-btn" data-copy>Copiar</button><a class="mini-btn" href="${esc(q.file)}" target="_blank" rel="noopener">Archivo ↗</a></span>
        ${q.note ? `<span class="note">${esc(q.note)}</span>` : ""}</div>${codeBlock(q.code, q.lang)}`;
      body.querySelector("[data-copy]").addEventListener("click", () => copy(q.code));
      document.querySelectorAll("#q-shell .tab").forEach(t => t.classList.toggle("on", +t.dataset.k === k));
    };
    document.querySelectorAll("#q-shell .tab").forEach(t => t.addEventListener("click", () => showQuery(+t.dataset.k)));
    showQuery(0);
  }

  function about() {
    const skills = ["Databricks / Spark SQL", "Power BI", "DAX", "Power Query (M)", "Delta Sharing", "Python · pandas", "scikit-learn", "Modelado semántico", "Análisis de cohortes", "Churn & retención", "Excel avanzado"];
    app.innerHTML = `
    <div class="view about">
      <div>
        <span class="eyebrow"><span class="dot"></span>${esc(C.titulo)}</span>
        <h1 style="font-family:var(--display);font-size:clamp(36px,5vw,54px);letter-spacing:-1px;margin:18px 0 14px;line-height:1.05">${esc(C.nombre)}</h1>
        <p style="color:var(--muted);font-size:17px;margin:0 0 24px">${esc(C.intro)}</p>
        <div class="skills">${skills.map(s => `<span>${esc(s)}</span>`).join("")}</div>
        <div class="hero-actions">
          ${C.linkedin ? `<a class="btn primary" href="${esc(C.linkedin)}" target="_blank" rel="noopener">LinkedIn ↗</a>` : ""}
          <a class="btn" href="${esc(C.github)}" target="_blank" rel="noopener">GitHub ↗</a>
          ${C.email ? `<a class="btn" href="mailto:${esc(C.email)}">${esc(C.email)}</a>` : ""}
        </div>
      </div>
      <div class="panel"><h3>Trayectoria</h3><ul class="timeline">${(C.experiencia || []).map(e => `<li><small>${esc(e.periodo)}</small><div><b>${esc(e.cargo)}</b><span>${esc(e.empresa)}</span></div></li>`).join("")}</ul></div>
    </div>`;
  }

  function route() {
    const h = location.hash;
    const m = h.match(/^#\/p\/([\w-]+)/);
    document.querySelectorAll(".topnav a").forEach(a => a.classList.remove("active"));
    if (m) project(m[1]);
    else if (h.startsWith("#/sobre-mi")) { about(); document.querySelector('.topnav a[href="#/sobre-mi"]').classList.add("active"); }
    else if (h === "#proyectos") { if (!app.querySelector(".hero")) home(); document.getElementById("proyectos")?.scrollIntoView(); return; }
    else { home(); document.querySelector('.topnav a[href="#/"]').classList.add("active"); }
    window.scrollTo(0, 0);
  }
  if (C.github) document.getElementById("nav-github").href = C.github;
  document.getElementById("year").textContent = new Date().getFullYear();
  window.addEventListener("hashchange", route);
  route();
})();
