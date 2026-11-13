(() => {
  "use strict";

  const DATA = window.MMACRO_RELEASES || {};
  const REPO_URL = DATA.repository || "https://github.com/mozrg/Mmacro";
  const API_URL = "https://api.github.com/repos/mozrg/Mmacro/releases?per_page=100";
  const dateFormatter = new Intl.DateTimeFormat("ru-RU", {
    day: "numeric",
    month: "long",
    year: "numeric"
  });

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function normalizeRelease(release) {
    if (!release || !release.tag) return null;
    const assets = Array.isArray(release.assets) ? release.assets : [];
    const zipAsset = assets.find((asset) => String(asset.name || "").toLowerCase().endsWith(".zip"));
    return {
      tag: String(release.tag),
      name: String(release.name || release.tag),
      publishedAt: release.publishedAt || release.published_at || "",
      url: release.url || release.html_url || `${REPO_URL}/releases/tag/${encodeURIComponent(release.tag)}`,
      notes: release.notes || release.body || "",
      prerelease: Boolean(release.prerelease),
      downloadUrl:
        release.downloadUrl ||
        (zipAsset && zipAsset.browser_download_url) ||
        `${REPO_URL}/archive/refs/tags/${encodeURIComponent(release.tag)}.zip`
    };
  }

  function normalizeReleases(releases) {
    const seen = new Set();
    return releases
      .filter((release) => release && !release.draft)
      .map(normalizeRelease)
      .filter((release) => {
        if (!release || seen.has(release.tag)) return false;
        seen.add(release.tag);
        return true;
      })
      .sort((a, b) => {
        const aTime = Date.parse(a.publishedAt) || 0;
        const bTime = Date.parse(b.publishedAt) || 0;
        return bTime - aTime;
      });
  }

  function formatDate(isoDate) {
    const date = new Date(isoDate);
    if (Number.isNaN(date.getTime())) return "";
    return dateFormatter.format(date).replace(/\s*г\.$/, "");
  }

  function pluralize(count, forms) {
    const n = Math.abs(count) % 100;
    const n1 = n % 10;
    if (n > 10 && n < 20) return forms[2];
    if (n1 > 1 && n1 < 5) return forms[1];
    if (n1 === 1) return forms[0];
    return forms[2];
  }

  function inlineText(value) {
    return String(value)
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/\*\*([^*]+)\*\*/g, "$1")
      .replace(/__([^_]+)__/g, "$1")
      .replace(/`([^`]+)`/g, "$1")
      .replace(/\s+/g, " ")
      .trim();
  }

  function releaseSummary(notes) {
    const lines = String(notes || "")
      .split(/\r?\n/)
      .map((line) => inlineText(line.replace(/^\s*[-*]\s+/, "")))
      .filter(Boolean)
      .filter((line) => !/^v?\d+\.\d+(\.\d+)?$/i.test(line))
      .filter((line) => !/^Mmacro\s+v?\d/i.test(line))
      .filter((line) => !/^(Что нового|Фиксы|Настройки|Изменения):?$/i.test(line));

    if (!lines.length) return "Заметки не указаны.";
    const summary = lines[0];
    if (summary.length <= 170) return /[.!?]$/.test(summary) ? summary : `${summary}.`;
    return `${summary.slice(0, 167).trimEnd()}…`;
  }

  function appendInline(parent, rawText) {
    const text = String(rawText || "")
      .replace(/\*\*([^*]+)\*\*/g, "$1")
      .replace(/__([^_]+)__/g, "$1")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
    const segments = text.split("`");

    segments.forEach((segment, index) => {
      if (!segment) return;
      if (index % 2 === 1) {
        parent.appendChild(element("code", "", segment));
      } else {
        parent.appendChild(document.createTextNode(segment));
      }
    });
  }

  function notesFragment(notes) {
    const fragment = document.createDocumentFragment();
    const lines = String(notes || "").split(/\r?\n/);
    let list = null;
    let hasContent = false;

    const flushList = () => {
      if (list) {
        fragment.appendChild(list);
        list = null;
      }
    };

    lines.forEach((rawLine) => {
      const line = rawLine.trim();
      if (!line) {
        flushList();
        return;
      }

      const cleaned = inlineText(line.replace(/^#{1,6}\s+/, ""));
      if (!cleaned) return;

      if (/^\*{0,2}Mmacro\s+v?\d/i.test(cleaned) || /^v?\d+\.\d+(\.\d+)?\*{0,2}$/i.test(cleaned)) {
        return;
      }

      const isHeading = /^(Что нового|Фиксы|Настройки|Изменения):?$/i.test(cleaned);
      if (isHeading) {
        flushList();
        fragment.appendChild(element("h4", "", cleaned.replace(/:$/, "")));
        hasContent = true;
        return;
      }

      if (/^[-*]\s+/.test(line)) {
        if (!list) list = document.createElement("ul");
        const item = document.createElement("li");
        appendInline(item, line.replace(/^[-*]\s+/, ""));
        list.appendChild(item);
        hasContent = true;
        return;
      }

      flushList();
      const paragraph = document.createElement("p");
      appendInline(paragraph, line);
      fragment.appendChild(paragraph);
      hasContent = true;
    });

    flushList();

    if (!hasContent) {
      fragment.appendChild(element("p", "", "Заметки не указаны."));
    }

    return fragment;
  }

  function buildReleaseEntry(release, latestTag) {
    const isLatest = release.tag === latestTag;
    const article = element("article", `release-entry${isLatest ? " is-latest" : ""}`);
    article.id = release.tag;

    const aside = element("div", "release-aside");
    const heading = element("h3", "release-heading");
    const tagLink = element("a", "release-tag", `v${release.tag}`);
    tagLink.href = `#${encodeURIComponent(release.tag)}`;
    heading.appendChild(tagLink);
    aside.appendChild(heading);

    const time = element("time", "release-date", formatDate(release.publishedAt));
    if (release.publishedAt) time.dateTime = release.publishedAt.slice(0, 10);
    aside.appendChild(time);

    if (isLatest) {
      const badge = element("span", "release-badge");
      const dot = element("span", "status-dot");
      dot.setAttribute("aria-hidden", "true");
      badge.appendChild(dot);
      badge.appendChild(document.createTextNode("Последний релиз"));
      aside.appendChild(badge);
    } else if (release.prerelease) {
      aside.appendChild(element("span", "release-badge", "Предварительная версия"));
    }

    const content = element("div", "release-content");
    const notes = element("div", "release-notes");
    notes.appendChild(notesFragment(release.notes));
    content.appendChild(notes);

    const actions = element("div", "release-actions");
    const download = element("a", "button button-primary", "Скачать ZIP");
    download.href = release.downloadUrl;
    download.setAttribute("aria-label", `Скачать ZIP версии ${release.tag}`);
    actions.appendChild(download);

    const github = element("a", "text-link release-github-link");
    github.href = release.url;
    github.target = "_blank";
    github.rel = "noopener noreferrer";
    github.appendChild(document.createTextNode("Релиз на GitHub "));
    const arrow = element("span", "", "→");
    arrow.setAttribute("aria-hidden", "true");
    github.appendChild(arrow);
    actions.appendChild(github);

    article.append(aside, content, actions);
    return article;
  }

  function renderVersions(releases, latest) {
    const list = document.querySelector("[data-release-list]");
    if (!list || !releases.length) return;

    const fragment = document.createDocumentFragment();
    releases.forEach((release) => fragment.appendChild(buildReleaseEntry(release, latest.tag)));
    list.replaceChildren(fragment);

    if (location.hash) {
      const id = decodeURIComponent(location.hash.slice(1));
      const target = document.getElementById(id);
      if (target) {
        requestAnimationFrame(() => target.scrollIntoView({ block: "start" }));
      }
    }
  }

  function renderHomeReleases(releases, latest) {
    const container = document.querySelector("[data-home-releases]");
    if (!container || !releases.length) return;

    const latestBlock = element("div", "latest-release");
    const latestMain = element("div", "latest-main");

    const state = element("p", "release-state");
    const dot = element("span", "status-dot");
    dot.setAttribute("aria-hidden", "true");
    state.append(dot, document.createTextNode("Последний релиз"));
    latestMain.appendChild(state);

    const heading = element("div", "latest-heading");
    heading.appendChild(element("h3", "", `v${latest.tag}`));
    const headingTime = element("time", "", formatDate(latest.publishedAt));
    if (latest.publishedAt) headingTime.dateTime = latest.publishedAt.slice(0, 10);
    heading.appendChild(headingTime);
    latestMain.appendChild(heading);
    latestMain.appendChild(element("p", "latest-note", releaseSummary(latest.notes)));

    const side = element("div", "latest-side");
    const download = element("a", "button button-primary", "Скачать ZIP");
    download.href = latest.downloadUrl;
    download.setAttribute("aria-label", `Скачать ZIP версии ${latest.tag}`);
    side.appendChild(download);
    const allChanges = element("a", "text-link");
    allChanges.href = "versions.html";
    allChanges.appendChild(document.createTextNode("Все изменения "));
    const arrow = element("span", "", "→");
    arrow.setAttribute("aria-hidden", "true");
    allChanges.appendChild(arrow);
    side.appendChild(allChanges);

    latestBlock.append(latestMain, side);

    const previous = element("div", "release-preview-list");
    previous.setAttribute("aria-label", "Предыдущие релизы");
    releases
      .filter((release) => release.tag !== latest.tag)
      .slice(0, 2)
      .forEach((release) => {
        const row = element("div", "release-preview-row");
        row.appendChild(element("span", "preview-version", `v${release.tag}`));
        const time = element("time", "", formatDate(release.publishedAt));
        if (release.publishedAt) time.dateTime = release.publishedAt.slice(0, 10);
        row.appendChild(time);
        row.appendChild(element("p", "", releaseSummary(release.notes)));
        const link = element("a", "", "ZIP ");
        link.href = release.downloadUrl;
        link.setAttribute("aria-label", `Скачать версию ${release.tag}`);
        const icon = element("span", "", "↓");
        icon.setAttribute("aria-hidden", "true");
        link.appendChild(icon);
        row.appendChild(link);
        previous.appendChild(row);
      });

    container.replaceChildren(latestBlock, previous);
  }

  function updateSharedVersion(latest, releases) {
    document.querySelectorAll("[data-current-version]").forEach((node) => {
      node.textContent = latest.tag;
    });

    document.querySelectorAll("[data-release-count]").forEach((node) => {
      node.textContent = String(releases.length);
    });

    document.querySelectorAll("[data-release-count-word]").forEach((node) => {
      node.textContent = pluralize(releases.length, ["версия", "версии", "версий"]);
    });

    const formattedDate = formatDate(latest.publishedAt);
    document.querySelectorAll("[data-release-date]").forEach((node) => {
      if (formattedDate) node.textContent = formattedDate;
      if (node.tagName === "TIME" && latest.publishedAt) {
        node.dateTime = latest.publishedAt.slice(0, 10);
      }
    });

    document.querySelectorAll("[data-download]").forEach((link) => {
      link.href = latest.downloadUrl;
    });
  }

  function applyReleases(releases) {
    const normalized = normalizeReleases(releases);
    if (!normalized.length) return;
    const latest = normalized.find((release) => !release.prerelease) || normalized[0];
    updateSharedVersion(latest, normalized);
    renderHomeReleases(normalized, latest);
    renderVersions(normalized, latest);
  }

  async function refreshFromGitHub() {
    if (location.protocol === "file:") return;
    try {
      const response = await fetch(API_URL, {
        headers: { Accept: "application/vnd.github+json" },
        signal: AbortSignal.timeout ? AbortSignal.timeout(7000) : undefined
      });
      if (!response.ok) return;
      const releases = await response.json();
      if (Array.isArray(releases) && releases.length) {
        applyReleases(releases);
      }
    } catch {
      // The checked-in release snapshot remains on screen.
    }
  }

  function setupNavigation() {
    const toggle = document.querySelector(".nav-toggle");
    const nav = document.getElementById("site-nav");
    if (!toggle || !nav) return;

    const label = toggle.querySelector(".sr-only");

    const setOpen = (open) => {
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? "Закрыть меню" : "Открыть меню");
      nav.classList.toggle("is-open", open);
      document.body.classList.toggle("menu-open", open);
      if (label) label.textContent = open ? "Закрыть меню" : "Открыть меню";
    };

    toggle.addEventListener("click", () => {
      setOpen(toggle.getAttribute("aria-expanded") !== "true");
    });

    nav.addEventListener("click", (event) => {
      if (event.target.closest("a")) setOpen(false);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
        setOpen(false);
        toggle.focus();
      }
    });

    document.addEventListener("click", (event) => {
      if (
        toggle.getAttribute("aria-expanded") === "true" &&
        !nav.contains(event.target) &&
        !toggle.contains(event.target)
      ) {
        setOpen(false);
      }
    });

    window.addEventListener("resize", () => {
      if (window.innerWidth > 900 && toggle.getAttribute("aria-expanded") === "true") {
        setOpen(false);
      }
    });
  }

  function setYear() {
    document.querySelectorAll("[data-year]").forEach((node) => {
      node.textContent = String(new Date().getFullYear());
    });
  }

  setupNavigation();
  setYear();
  applyReleases(DATA.releases || []);
  refreshFromGitHub();
})();
