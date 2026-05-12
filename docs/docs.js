// AllArkive docs runtime: sidebar toggle, copy buttons, TOC scrollspy.
// No external dependencies; vanilla DOM APIs only.

(function () {
    'use strict';

    function ready(fn) {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', fn);
        } else {
            fn();
        }
    }

    function initSidebarToggle() {
        var btn = document.querySelector('.sidebar-toggle');
        var sidebar = document.querySelector('.doc-sidebar');
        if (!btn || !sidebar) return;
        if (!sidebar.id) sidebar.id = 'doc-sidebar';
        btn.addEventListener('click', function () {
            var open = sidebar.classList.toggle('is-open');
            btn.setAttribute('aria-expanded', open ? 'true' : 'false');
        });
        // Close on link click (mobile drawer)
        sidebar.addEventListener('click', function (event) {
            var target = event.target;
            if (target && target.tagName === 'A' && sidebar.classList.contains('is-open')) {
                sidebar.classList.remove('is-open');
                btn.setAttribute('aria-expanded', 'false');
            }
        });
    }

    function initCopyButtons() {
        var blocks = document.querySelectorAll('.doc-content pre');
        blocks.forEach(function (pre) {
            // Pandoc may wrap pre in <div class="sourceCode">; mount button on the wrapper if so.
            var host = pre.parentElement && pre.parentElement.classList.contains('sourceCode')
                ? pre.parentElement
                : pre;
            // Ensure positioning context
            host.classList.add('has-copy');

            var btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'copy-btn';
            btn.setAttribute('aria-label', 'Copy code to clipboard');
            btn.textContent = 'Copy';
            host.appendChild(btn);

            btn.addEventListener('click', function () {
                var code = pre.querySelector('code') || pre;
                // Extract plain text, ignoring the empty anchor numbering elements.
                var text = code.innerText.replace(/ /g, ' ');
                var done = function (ok) {
                    btn.textContent = ok ? 'Copied' : 'Failed';
                    btn.classList.toggle('is-error', !ok);
                    setTimeout(function () {
                        btn.textContent = 'Copy';
                        btn.classList.remove('is-error');
                    }, 1600);
                };
                if (navigator.clipboard && window.isSecureContext) {
                    navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(fallbackCopy(text)); });
                } else {
                    done(fallbackCopy(text));
                }
            });
        });
    }

    function fallbackCopy(text) {
        try {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.setAttribute('readonly', '');
            ta.style.position = 'absolute';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            var ok = document.execCommand('copy');
            document.body.removeChild(ta);
            return ok;
        } catch (e) {
            return false;
        }
    }

    function initScrollSpy() {
        var toc = document.querySelector('.doc-toc');
        var content = document.querySelector('.doc-content');
        if (!toc || !content) return;

        var links = Array.prototype.slice.call(toc.querySelectorAll('a[href^="#"]'));
        if (!links.length) return;

        var byId = {};
        var headings = [];
        links.forEach(function (a) {
            var id = decodeURIComponent(a.getAttribute('href').slice(1));
            var h = document.getElementById(id);
            if (!h) return;
            byId[id] = a;
            headings.push(h);
        });
        if (!headings.length) return;

        function setActive(id) {
            links.forEach(function (a) {
                if (a === byId[id]) {
                    a.classList.add('is-active');
                } else {
                    a.classList.remove('is-active');
                }
            });
        }

        // Pick the heading whose top is closest above a sentinel line near the top of the viewport.
        var sentinel = 120; // px from top
        var ticking = false;

        function update() {
            ticking = false;
            var current = headings[0];
            for (var i = 0; i < headings.length; i++) {
                var rect = headings[i].getBoundingClientRect();
                if (rect.top - sentinel <= 0) {
                    current = headings[i];
                } else {
                    break;
                }
            }
            if (current && current.id) setActive(current.id);
        }

        function onScroll() {
            if (!ticking) {
                window.requestAnimationFrame(update);
                ticking = true;
            }
        }

        window.addEventListener('scroll', onScroll, { passive: true });
        window.addEventListener('resize', onScroll);
        update();
    }

    ready(function () {
        initSidebarToggle();
        initCopyButtons();
        initScrollSpy();
    });
})();
