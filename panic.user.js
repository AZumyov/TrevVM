// ==UserScript==
// @name         TrevVM panic key
// @namespace    https://github.com/AZumyov/TrevVM
// @version      1.0.0
// @description  Press = to leave the TrevVM tab and open a neutral page.
// @match        *://localhost/*
// @match        https://*.app.github.dev/*
// @match        https://*.githubpreview.dev/*
// @match        *://127.0.0.1/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(function () {
    "use strict";

    // Change this if you prefer another neutral page.
    var safeSite = "https://www.google.com";
    var redirecting = false;

    function isEditable(target) {
        if (!target) return false;
        if (target.isContentEditable) return true;
        return /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName);
    }

    function panic(event) {
        var pressed = event.code === "Equal" || event.code === "NumpadEqual" || event.key === "=";
        if (!pressed || event.altKey || event.ctrlKey || event.shiftKey || event.metaKey) return;
        if (redirecting || isEditable(event.target)) return;
        event.preventDefault();
        redirecting = true;
        window.location.replace(safeSite);
    }

    window.addEventListener("keydown", panic, true);
})();
