// EZ Kanban admin column editor (issue 0005).
// Progressive enhancement over a plain form: add/remove/reorder column rows and
// keep the single shared "Done" radio group in sync with the per-row hidden
// is_done field the server actually reads. No board state is touched here; this
// only edits the global column config (ADR-0004).
(function () {
  'use strict';

  function tbody() {
    return document.getElementById('ez-kanban-settings-rows');
  }

  // Sync each row's hidden is_done value to the checked radio so submission
  // carries exactly one Done column.
  function syncDone() {
    var rows = tbody().querySelectorAll('tr.ez-kanban-settings-row');
    rows.forEach(function (row) {
      var radio = row.querySelector('.ez-kanban-settings-done');
      var hidden = row.querySelector('.ez-kanban-settings-done-value');
      if (radio && hidden) {
        hidden.value = radio.checked ? '1' : '0';
      }
    });
  }

  function addRow() {
    var template = document.getElementById('ez-kanban-row-template');
    if (!template) return;
    var index = tbody().querySelectorAll('tr.ez-kanban-settings-row').length;
    var html = template.innerHTML.replace(/__INDEX__/g, String(index));
    var wrapper = document.createElement('tbody');
    wrapper.innerHTML = html.trim();
    var row = wrapper.querySelector('tr');
    tbody().appendChild(row);
  }

  function removeRow(button) {
    var row = button.closest('tr.ez-kanban-settings-row');
    if (row) row.remove();
    syncDone();
  }

  function moveRow(button, delta) {
    var row = button.closest('tr.ez-kanban-settings-row');
    if (!row) return;
    if (delta < 0 && row.previousElementSibling) {
      row.parentNode.insertBefore(row, row.previousElementSibling);
    } else if (delta > 0 && row.nextElementSibling) {
      row.parentNode.insertBefore(row.nextElementSibling, row);
    }
  }

  document.addEventListener('click', function (event) {
    var target = event.target;
    if (target.classList.contains('ez-kanban-add-column')) {
      addRow();
    } else if (target.classList.contains('ez-kanban-remove-column')) {
      removeRow(target);
    } else if (target.classList.contains('ez-kanban-move-up')) {
      moveRow(target, -1);
    } else if (target.classList.contains('ez-kanban-move-down')) {
      moveRow(target, 1);
    }
  });

  document.addEventListener('change', function (event) {
    if (event.target.classList.contains('ez-kanban-settings-done')) {
      syncDone();
    }
  });
})();
