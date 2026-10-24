(function () {
    "use strict";

    // Override before loading: window.TREVVM_PANIC_URL = "https://example.com";
    var safeSite = window.TREVVM_PANIC_URL || "https://www.google.com";
    var redirecting = false;

    function isEditable(target) {
        if (!target || !target.tagName) return false;
        return /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable === true;
    }

    function panic(event) {
        var pressed = event.code === "Equal" || event.code === "NumpadEqual" || event.key === "=";
        if (!pressed || event.altKey || event.ctrlKey || event.shiftKey || event.metaKey) return;
        if (isEditable(event.target)) return;
        if (redirecting) return;
        event.preventDefault();
        redirecting = true;
        window.location.replace(safeSite);
    }

    window.addEventListener("keydown", panic, true);
})();
