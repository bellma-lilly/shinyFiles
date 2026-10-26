// Showcase mode puts the code beside the app on wide screens, which squeezes
// the app (and its sidebar) into half the window. Move the code below instead.
// Runs after Shiny's own load handler, which is what places it alongside.
$(window).on('load', function () {
  setTimeout(function () {
    var sideBySide = $('#showcase-sxs-code #showcase-code-tabs').length > 0;
    if (sideBySide && window.toggleCodePosition) window.toggleCodePosition();
  }, 0);
});
