(function() {
    const safeSite = 'https://google.com';
    const panicKeyCode = 'Equal';

    function redirectToSafeSite() {
        window.location.replace(safeSite);
    }

    window.addEventListener('keydown', (event) => {
        if (event.code === panicKeyCode && !event.altKey && !event.ctrlKey && !event.shiftKey && !event.metaKey) {
            event.preventDefault();
            redirectToSafeSite();
        }
    });
 //Code adapted from ramazing, so be careful. Panic key is equal btw
    console.log('Panic key active: Press the equal key to switch to google. (teacher-safe page). If you see this msg in the console btw, you can hack using cmds with js btw...');
})();
