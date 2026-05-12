'use strict';

// All API calls go through the nginx proxy at /api/rag/,
// which forwards to the RAG service at http://rag:8000/.
const RAG_API = '/api/rag';
let KIWIX_URL = 'http://localhost:8081'; // updated from /status on boot

let currentMode = 'search'; // 'search' | 'ai'
let abortController = null;

// ── Boot ──────────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
    setupModeToggle();
    setupNavLinks();
    setupForm();
    loadStatus();
});

// ── Navigation ────────────────────────────────────────────────────────────────

function setupNavLinks() {
    document.getElementById('nav-search').addEventListener('click', (e) => {
        e.preventDefault();
        setMode('search');
        document.getElementById('search').scrollIntoView({ behavior: 'smooth' });
    });

    document.getElementById('nav-chat').addEventListener('click', (e) => {
        e.preventDefault();
        setMode('ai');
        document.getElementById('search').scrollIntoView({ behavior: 'smooth' });
        document.getElementById('query-input').focus();
    });

    document.getElementById('nav-manage').addEventListener('click', (e) => {
        e.preventDefault();
        document.getElementById('manage').scrollIntoView({ behavior: 'smooth' });
    });
}

// ── Mode toggle ───────────────────────────────────────────────────────────────

function setupModeToggle() {
    document.getElementById('btn-search-mode').addEventListener('click', () => setMode('search'));
    document.getElementById('btn-ai-mode').addEventListener('click', () => setMode('ai'));
}

function setMode(mode) {
    currentMode = mode;

    const searchBtn = document.getElementById('btn-search-mode');
    const aiBtn = document.getElementById('btn-ai-mode');
    const input = document.getElementById('query-input');
    const submitBtn = document.getElementById('submit-btn');

    searchBtn.classList.toggle('active', mode === 'search');
    aiBtn.classList.toggle('active', mode === 'ai');

    if (mode === 'search') {
        input.placeholder = 'Search the archive…';
        submitBtn.textContent = 'Search';
        document.getElementById('ai-panel').hidden = true;
        document.getElementById('ai-response').innerHTML = '';
    } else {
        input.placeholder = 'Ask a question…';
        submitBtn.textContent = 'Ask';
    }
}

// ── Form submission ───────────────────────────────────────────────────────────

function setupForm() {
    document.getElementById('query-form').addEventListener('submit', async (e) => {
        e.preventDefault();
        const query = document.getElementById('query-input').value.trim();
        if (!query) return;

        if (currentMode === 'search') {
            openKiwixSearch(query);
        } else {
            await askAI(query);
        }
    });
}

function openKiwixSearch(query) {
    const url = new URL('/search', KIWIX_URL);
    url.searchParams.set('lang', 'eng');
    url.searchParams.set('pattern', query);
    window.open(url.toString(), '_blank', 'noopener,noreferrer');
}

async function askAI(query) {
    const panel = document.getElementById('ai-panel');
    const responseEl = document.getElementById('ai-response');
    const submitBtn = document.getElementById('submit-btn');

    // Cancel any in-flight request
    if (abortController) abortController.abort();
    abortController = new AbortController();

    panel.hidden = false;
    responseEl.innerHTML = '<span class="thinking">Searching archive and generating response…</span>';
    submitBtn.disabled = true;
    submitBtn.textContent = 'Working…';

    try {
        const res = await fetch(`${RAG_API}/v1/chat/completions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: 'allarkive-rag',
                messages: [{ role: 'user', content: query }],
                stream: false,
            }),
            signal: abortController.signal,
        });

        if (!res.ok) {
            const text = await res.text().catch(() => '');
            responseEl.innerHTML = `<span class="response-error">Error ${res.status}: ${escapeHtml(text.slice(0, 200))}</span>`;
            return;
        }

        const data = await res.json();
        const content = data.choices?.[0]?.message?.content ?? '';
        responseEl.innerHTML = renderResponse(content);
    } catch (err) {
        if (err.name === 'AbortError') return;
        responseEl.innerHTML = '<span class="response-error">Request failed. Is the RAG service running?</span>';
    } finally {
        submitBtn.disabled = false;
        submitBtn.textContent = 'Ask';
    }
}

// ── Response rendering ────────────────────────────────────────────────────────

// Converts the RAG service's markdown output (with [[N: title]](url) citations)
// to safe HTML. Processes citations before HTML-escaping to preserve URLs.
function renderResponse(text) {
    // Split on citation markers first, so URL characters survive HTML-escaping.
    const citRe = /\[\[(\d+): ([^\]]+)\]\]\(([^)]+)\)/g;
    const parts = [];
    let last = 0;
    let m;

    while ((m = citRe.exec(text)) !== null) {
        parts.push({ type: 'text', value: text.slice(last, m.index) });
        parts.push({ type: 'cite', n: m[1], title: m[2], url: m[3] });
        last = m.index + m[0].length;
    }
    parts.push({ type: 'text', value: text.slice(last) });

    let html = '';
    for (const p of parts) {
        if (p.type === 'cite') {
            html += `<a href="${escapeHtml(p.url)}" class="citation" target="_blank" rel="noopener noreferrer">[${escapeHtml(p.n)}: ${escapeHtml(p.title)}]</a>`;
        } else {
            let t = escapeHtml(p.value);
            // Bold: **text**
            t = t.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
            // Inline code: `code`
            t = t.replace(/`([^`\n]+)`/g, '<code>$1</code>');
            html += t;
        }
    }

    // Wrap double-newline-separated blocks in <p> tags
    return html
        .split(/\n\n+/)
        .filter(s => s.trim())
        .map(s => `<p>${s.replace(/\n/g, '<br>')}</p>`)
        .join('\n');
}

// ── Status and archive info ───────────────────────────────────────────────────

async function loadStatus() {
    const statusEl = document.getElementById('status');
    const archivesEl = document.getElementById('archives-table');

    try {
        const res = await fetch(`${RAG_API}/status`, { cache: 'no-store' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (data.kiwix_url) {
            KIWIX_URL = data.kiwix_url;
            document.getElementById('link-archive').href = data.kiwix_url;
        }
        if (data.webui_url) {
            document.getElementById('link-chat').href = data.webui_url;
        }
        applySearchOnlyMode(!!data.search_only);
        renderStatusLine(statusEl, data);
        renderArchivesTable(archivesEl, data);
    } catch {
        statusEl.textContent = 'Status unavailable. Is the RAG service running?';
        archivesEl.innerHTML = '<p class="error-msg">Could not reach the RAG service. Run: <code>docker compose up -d</code></p>';
    }
}

function renderStatusLine(el, data) {
    const ragState = data.rag_ready ? 'ready' : 'index not built';
    const archiveStr = data.archive_count > 0
        ? `${data.archive_count} source${data.archive_count !== 1 ? 's' : ''} / ${data.archive_total_gb} GB`
        : 'no archives';
    const modelStr = data.search_only ? 'search-only (no chat model)' : data.chat_model;
    el.textContent = `binding: localhost only · archive: ${archiveStr} · model: ${modelStr} · RAG: ${ragState}`;
}

// Hide the "Ask AI" UI when the backend reports no chat model is configured.
// Toggles cleanly each /status refresh, so flipping --no-model on/off doesn't
// require a hard refresh.
function applySearchOnlyMode(searchOnly) {
    const navChat = document.getElementById('nav-chat');
    const aiBtn = document.getElementById('btn-ai-mode');
    const searchBtn = document.getElementById('btn-search-mode');

    if (navChat) navChat.hidden = searchOnly;
    if (aiBtn) aiBtn.hidden = searchOnly;

    if (searchOnly) {
        // Force search mode and keep the input pointed at archive search.
        setMode('search');
        if (searchBtn) searchBtn.textContent = 'Search archive (no AI configured)';
    } else if (searchBtn && searchBtn.textContent.startsWith('Search archive (no AI')) {
        searchBtn.textContent = 'Search archive';
    }
}

function renderArchivesTable(el, data) {
    if (!data.archives || data.archives.length === 0) {
        el.innerHTML = '<p class="no-archives">No archives installed. Run: <code>./scripts/fetch-bundle.sh balanced</code></p>';
        return;
    }

    const rows = data.archives.map(a => {
        const date = a.mtime ? new Date(a.mtime * 1000).toLocaleDateString() : '—';
        return `<tr>
            <td class="archive-name">${escapeHtml(a.name)}</td>
            <td class="archive-size">${a.size_gb} GB</td>
            <td class="archive-date">${escapeHtml(date)}</td>
        </tr>`;
    }).join('');

    el.innerHTML = `
        <table class="archives">
            <thead>
                <tr><th>Archive</th><th>Size</th><th>Last modified</th></tr>
            </thead>
            <tbody>${rows}</tbody>
        </table>
        <p class="verify-note">To verify checksums: <code>./scripts/fetch-bundle.sh --verify &lt;bundle-name&gt;</code></p>
    `;
}

// ── Utilities ─────────────────────────────────────────────────────────────────

function escapeHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}
