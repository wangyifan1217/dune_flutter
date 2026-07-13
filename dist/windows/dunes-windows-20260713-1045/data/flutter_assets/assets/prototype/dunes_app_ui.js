(function (global) {
  'use strict';

  function activePhone() {
    return (
      document.querySelector('.screen.active .phone-screen') ||
      document.querySelector('.screen[data-screen="XF"] .phone-screen') ||
      document.querySelector('.phone-screen')
    );
  }

  function overlayRoot() {
    var phone = activePhone();
    if (!phone) return document.body;
    var root = phone.querySelector('.dunes-phone-overlay-root');
    if (!root) {
      root = document.createElement('div');
      root.className = 'dunes-phone-overlay-root';
      phone.appendChild(root);
    }
    return root;
  }

  function showToast(msg, isErr) {
    var phone = activePhone();
    if (!phone) return;
    var t = phone.querySelector('.dunes-app-toast');
    if (!t) {
      t = document.createElement('div');
      t.className = 'dunes-app-toast';
      phone.appendChild(t);
    }
    t.className = 'dunes-app-toast' + (isErr ? ' err' : '');
    t.textContent = msg == null ? '' : String(msg);
    t.classList.add('show');
    clearTimeout(t._tid);
    t._tid = setTimeout(function () {
      t.classList.remove('show');
    }, 2800);
  }

  function showTip(msg) {
    if (global.DunesDialog && typeof global.DunesDialog.alert === 'function') {
      return global.DunesDialog.alert(msg == null ? '' : String(msg));
    }
    showToast(msg);
    return Promise.resolve();
  }

  function showConfirm(msg) {
    if (global.DunesDialog && typeof global.DunesDialog.confirm === 'function') {
      return global.DunesDialog.confirm(msg == null ? '' : String(msg));
    }
    return Promise.resolve(confirm(msg));
  }

  function mountOverlay(el) {
    var root = overlayRoot();
    root.appendChild(el);
    return root;
  }

  if (global.DunesAPI && typeof global.DunesAPI.toast === 'function') {
    global.DunesAPI.toast = function (msg, isErr) {
      showToast(msg, isErr);
    };
  }

  global.DunesAppUI = {
    activePhone: activePhone,
    overlayRoot: overlayRoot,
    toast: showToast,
    tip: showTip,
    confirm: showConfirm,
    mountOverlay: mountOverlay,
  };
})(typeof window !== 'undefined' ? window : global);
