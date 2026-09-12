(function () {
  function wireArchDiagramZoom() {
    document.querySelectorAll(".arch-diagram__trigger").forEach(function (trigger) {
      if (trigger.dataset.zoomWired) return;
      trigger.dataset.zoomWired = "1";
      var dialogId = trigger.getAttribute("aria-controls");
      var dialog = dialogId ? document.getElementById(dialogId) : null;
      if (!dialog || typeof dialog.showModal !== "function") return;

      trigger.addEventListener("click", function () {
        dialog.showModal();
      });

      dialog.addEventListener("click", function (event) {
        if (event.target === dialog) dialog.close();
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", wireArchDiagramZoom);
  } else {
    wireArchDiagramZoom();
  }
})();
