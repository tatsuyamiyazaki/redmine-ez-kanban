// Freshness controls for the read-only Kanban board (issue 0009).
//
// Manual refresh and opt-in polling both re-fetch the CURRENT URL (so the
// active filter / scope / subproject / cap state is preserved) as an XHR and
// swap only the board container's contents. The surrounding page and the
// user's scroll position are left intact. Strictly read-only: GET only, no
// writes to Redmine (R5).
(function () {
  'use strict';

  var STORAGE_KEY = 'ezKanbanPollInterval';
  var pollTimer = null;

  function container() {
    return document.getElementById('ez-kanban-board-container');
  }

  function refresh() {
    var el = container();
    if (!el) { return; }
    fetch(window.location.href, {
      headers: { 'X-Requested-With': 'XMLHttpRequest' },
      credentials: 'same-origin'
    }).then(function (response) {
      return response.ok ? response.text() : null;
    }).then(function (html) {
      if (html === null) { return; }
      var target = container();
      // Replace only the board's contents so page scroll is preserved.
      if (target) { target.innerHTML = html; }
    }).catch(function () {
      // On failure leave the stale board in place rather than blanking it.
    });
  }

  function applyInterval(seconds) {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    if (seconds > 0) { pollTimer = setInterval(refresh, seconds * 1000); }
  }

  function readStored() {
    try {
      return window.localStorage ? localStorage.getItem(STORAGE_KEY) : null;
    } catch (e) {
      return null;
    }
  }

  function store(value) {
    try {
      if (window.localStorage) { localStorage.setItem(STORAGE_KEY, value); }
    } catch (e) {
      // Ignore storage failures (private mode, quota); polling still works.
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    var button = document.getElementById('ez-kanban-refresh');
    if (button) {
      button.addEventListener('click', function (event) {
        event.preventDefault();
        refresh();
      });
    }

    var select = document.getElementById('ez-kanban-poll-interval');
    if (select) {
      // Restore a previously chosen interval; absent it, the server default
      // (off) stands, keeping costly polling opt-in.
      var saved = readStored();
      if (saved !== null) { select.value = saved; }
      applyInterval(parseInt(select.value, 10) || 0);

      select.addEventListener('change', function () {
        var seconds = parseInt(select.value, 10) || 0;
        store(String(seconds));
        applyInterval(seconds);
      });
    }
  });
}());
