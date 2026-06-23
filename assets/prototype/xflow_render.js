(function (global) {
  'use strict';

  var L = function () {
    return global.XFlowLinkage || {};
  };

  function normalizeDynamicListValue(val) {
    if (val == null || val === '') return [];
    if (Array.isArray(val)) return val;
    if (typeof val === 'object') return [val];
    return [];
  }

  var dictCache = {};
  var FIELD_DICT_FALLBACK = {
    txType: 'tx_type',
    goodType: 'good_type',
    proposalType: 'proposal_type',
    tag1: 'tag1',
    provinces: 'provinces',
    owner1Level: 'task_level',
    owner2Level: 'task_level',
    techPlatform: 'tech_platform',
    needAdvanceFund: 'yes_no',
    hasInvoiceTaxCost: 'invoice_cost',
    taxBurdenSide: 'tax_burden',
    needRollback: 'yes_no',
    profitModel: 'profit_model',
  };

  function dictKeyFor(field) {
    return field.dictKey || FIELD_DICT_FALLBACK[field.key] || '';
  }

  function resolveOptions(field) {
    var dk = dictKeyFor(field);
    if (dk && dictCache[dk]) {
      return dictCache[dk].map(function (it) {
        return { label: it.label, value: it.value };
      });
    }
    return field.options || [];
  }

  function userDisplay(val) {
    if (val && typeof val === 'object') {
      return val.name || val.displayName || String(val.userId || val.id || '');
    }
    return val == null ? '' : String(val);
  }

  function userIdOf(val) {
    if (val && typeof val === 'object') return val.userId || val.id || '';
    return val || '';
  }

  async function loadDict(key, apiFn) {
    if (!key || dictCache[key]) return dictCache[key];
    try {
      var res = await apiFn('/xflow/dicts/' + encodeURIComponent(key));
      var data = res && res.data !== undefined ? res.data : res;
      dictCache[key] = (data && data.items) || [];
    } catch (e) {
      dictCache[key] = [];
    }
    return dictCache[key];
  }

  async function enrichFieldsFromDicts(fields, apiFn) {
    if (!apiFn) return fields;
    var keys = {};
    fields.forEach(function (f) {
      var dk = dictKeyFor(f);
      if (dk) keys[dk] = true;
      (f.columns || []).forEach(function (c) {
        if (c.dictKey) keys[c.dictKey] = true;
      });
    });
    await Promise.all(
      Object.keys(keys).map(function (k) {
        return loadDict(k, apiFn);
      }),
    );
    return fields.map(function (f) {
      var nf = Object.assign({}, f);
      var dk = dictKeyFor(f);
      if (dk && dictCache[dk] && dictCache[dk].length) {
        nf.options = resolveOptions(f);
      }
      if (nf.columns) {
        nf.columns = nf.columns.map(function (c) {
          var nc = Object.assign({}, c);
          if (c.dictKey && dictCache[c.dictKey]) {
            nc.options = dictCache[c.dictKey].map(function (it) {
              return { label: it.label, value: it.value };
            });
          }
          return nc;
        });
      }
      return nf;
    });
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }

  var UPLOAD_META = {
    planFiles: {
      variant: 'plan',
      hint: 'JPG / PNG / HEIC / PDF · 最多 5 个',
      title: '点击选择或拖拽图片 / PDF',
      desc: '单个不超过 10MB · 优先图片',
      accept: '.jpg,.jpeg,.png,.heic,.heif,.pdf,image/*,application/pdf',
      icon: 'ti-photo-plus',
      maxBytes: 10 * 1024 * 1024,
    },
    contractFiles: {
      variant: 'contract',
      hint: 'PDF / DOCX · 最多 5 个',
      title: '上传供货商/渠道商务合同',
      desc: '审批层单独查看 · 与方案附件分开',
      accept: '.pdf,.doc,.docx,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      icon: 'ti-file-certificate',
      maxBytes: 20 * 1024 * 1024,
    },
  };

  function uploadMetaFor(field) {
    var base = UPLOAD_META[field.key] || {};
    return {
      variant: base.variant || 'plan',
      hint: base.hint || '最多 ' + (field.maxFiles || 5) + ' 个',
      title: base.title || '点击选择或拖拽文件',
      desc: base.desc || '上传后自动保存到文件服务器',
      accept: base.accept || '*/*',
      icon: base.icon || 'ti-upload',
      maxBytes: base.maxBytes || 20 * 1024 * 1024,
    };
  }

  function newUploadId() {
    return 'uf-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
  }

  function formatFileSize(bytes) {
    var n = Number(bytes) || 0;
    if (n < 1024) return n + ' B';
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
    return (n / (1024 * 1024)).toFixed(1) + ' MB';
  }

  function normalizeUploadItems(val) {
    if (!val) return [];
    if (!Array.isArray(val)) {
      if (typeof val === 'string' && val.trim()) {
        return [{ id: newUploadId(), fileName: val, status: 'done', progress: 100 }];
      }
      return [];
    }
    return val.map(function (it) {
      if (typeof it === 'string') {
        return { id: newUploadId(), fileName: it, status: 'done', progress: 100 };
      }
      return Object.assign(
        {
          id: it.id || newUploadId(),
          fileName: it.fileName || it.name || '未命名文件',
          status: it.status || (it.url || it.objectKey ? 'done' : 'uploading'),
          progress: it.progress != null ? it.progress : it.url || it.objectKey ? 100 : 0,
        },
        it,
      );
    });
  }

  function storageApiBase() {
    var base = localStorage.getItem('dunes_api_base') || '';
    if (base) return base.replace(/\/$/, '');
    var flow = localStorage.getItem('dunes_flow_api_base');
    if (flow) return flow.replace(/\/$/, '');
    var host = localStorage.getItem('dunes_api_host') || 'localhost';
    return 'http://' + host + ':6090/api/v1';
  }

  function uploadToStorage(file, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      var form = new FormData();
      form.append('file', file, file.name || 'upload');
      form.append('bucket', 'xflow-proposals');
      xhr.upload.onprogress = function (e) {
        if (e.lengthComputable && onProgress) onProgress(Math.round((e.loaded / e.total) * 100));
      };
      xhr.onload = function () {
        var text = xhr.responseText || '';
        try {
          var res = JSON.parse(text);
          if (res.success !== false && res.data) resolve(res.data);
          else reject(new Error((res && res.message) || '上传失败'));
        } catch (err) {
          reject(new Error(text || '上传失败'));
        }
      };
      xhr.onerror = function () {
        reject(new Error('网络错误'));
      };
      var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
      xhr.open('POST', storageApiBase() + '/storage/upload');
      if (token) xhr.setRequestHeader('Authorization', 'Bearer ' + token);
      xhr.send(form);
    });
  }

  function fileIconClass(name, mime) {
    var n = String(name || '').toLowerCase();
    var m = String(mime || '').toLowerCase();
    if (m.indexOf('image/') === 0 || /\.(jpg|jpeg|png|heic|heif|gif|webp)$/.test(n)) return 'ti-photo';
    if (/\.pdf$/.test(n) || m === 'application/pdf') return 'ti-file-type-pdf';
    if (/\.docx?$/.test(n) || m.indexOf('word') >= 0) return 'ti-file-certificate';
    return 'ti-file';
  }

  function renderUploadFileItem(item, listKey) {
    var st = item.status || 'done';
    var prog = item.progress != null ? item.progress : st === 'done' ? 100 : 0;
    var meta =
      st === 'uploading'
        ? '上传中 ' + prog + '%'
        : st === 'error'
          ? item.error || '上传失败'
          : formatFileSize(item.size);
    var bar =
      st === 'uploading'
        ? '<div class="xf-uf-bar"><i style="width:' + prog + '%"></i></div>'
        : st === 'error'
          ? '<div class="xf-uf-bar err"><i style="width:100%"></i></div>'
          : '';
    return (
      '<div class="xf-upload-file ' +
      esc(st) +
      '" data-upload-id="' +
      esc(item.id) +
      '">' +
      '<div class="xf-uf-ic"><i class="ti ' +
      fileIconClass(item.fileName, item.mimeType) +
      '"></i></div>' +
      '<div class="xf-uf-bd"><div class="xf-uf-nm">' +
      esc(item.fileName) +
      '</div><div class="xf-uf-meta">' +
      esc(meta) +
      '</div>' +
      bar +
      '</div>' +
      '<button type="button" class="xf-uf-del" data-upload-key="' +
      esc(listKey) +
      '" data-upload-id="' +
      esc(item.id) +
      '" title="删除"><i class="ti ti-x"></i></button></div>'
    );
  }

  function renderUploadFileItems(listKey, items) {
    items = normalizeUploadItems(items);
    if (!items.length) return '';
    return items.map(function (it) {
      return renderUploadFileItem(it, listKey);
    }).join('');
  }

  function renderUploadFilesList(root, listKey, items) {
    var list = root.querySelector('[data-upload-list="' + listKey + '"]');
    if (!list) return;
    list.innerHTML = renderUploadFileItems(listKey, items);
  }

  function renderUploadField(field, values) {
    var key = field.key;
    var meta = uploadMetaFor(field);
    var max = field.maxFiles || 5;
    var items = normalizeUploadItems(values[key]);
    values[key] = items;
    var label = field.label || key;
    if (key === 'contractFiles') label = '商务合同附件';
    return (
      '<div class="xf-upload-block" data-upload-block="' +
      esc(key) +
      '">' +
      '<div class="xf-upload-lbl">' +
      esc(label) +
      ' <span class="xf-upload-meta">' +
      esc(meta.hint) +
      '</span></div>' +
      '<div class="xf-upload-card xf-upload ' +
      meta.variant +
      '" data-key="' +
      esc(key) +
      '" data-max="' +
      max +
      '" data-accept="' +
      esc(meta.accept) +
      '" data-max-bytes="' +
      meta.maxBytes +
      '">' +
      '<i class="ti ' +
      meta.icon +
      ' xf-up-ic"></i>' +
      '<div class="xf-up-t">' +
      esc(meta.title) +
      '</div>' +
      '<div class="xf-up-d">' +
      esc(meta.desc) +
      '</div></div>' +
      '<div class="xf-upload-files" data-upload-list="' +
      esc(key) +
      '">' +
      renderUploadFileItems(key, items) +
      '</div></div>'
    );
  }

  function queueUploadFiles(root, uKey, field, values, notify, fileList) {
    var card = root.querySelector('.xf-upload[data-key="' + uKey + '"]');
    if (!card) return;
    var max = parseInt(card.getAttribute('data-max'), 10) || field.maxFiles || 5;
    var maxBytes = parseInt(card.getAttribute('data-max-bytes'), 10) || 20 * 1024 * 1024;
    var items = normalizeUploadItems(values[uKey]);
    var room = max - items.filter(function (it) {
      return it.status !== 'error';
    }).length;
    if (room <= 0) {
      if (global.DunesAppUI && DunesAppUI.toast) DunesAppUI.toast('最多上传 ' + max + ' 个文件', true);
      else if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('最多上传 ' + max + ' 个文件', true);
      return;
    }
    var files = Array.from(fileList || []).slice(0, room);
    files.forEach(function (file) {
      if (file.size > maxBytes) {
        if (global.DunesAppUI && DunesAppUI.toast) {
          DunesAppUI.toast(file.name + ' 超过大小限制', true);
        }
        return;
      }
      var item = {
        id: newUploadId(),
        fileName: file.name,
        size: file.size,
        mimeType: file.type || '',
        status: 'uploading',
        progress: 0,
      };
      items.push(item);
      values[uKey] = items;
      renderUploadFilesList(root, uKey, items);
      uploadToStorage(file, function (pct) {
        item.progress = pct;
        renderUploadFilesList(root, uKey, values[uKey]);
      })
        .then(function (data) {
          item.status = 'done';
          item.progress = 100;
          item.url = data.url || '';
          item.objectKey = data.objectKey || data.url || '';
          item.backend = data.backend || '';
          renderUploadFilesList(root, uKey, values[uKey]);
          notify();
        })
        .catch(function (err) {
          item.status = 'error';
          item.error = (err && err.message) || '上传失败';
          renderUploadFilesList(root, uKey, values[uKey]);
          notify();
        });
    });
    notify();
  }

  function pickUploadFiles(root, uKey, field, values, notify) {
    var card = root.querySelector('.xf-upload[data-key="' + uKey + '"]');
    if (!card) return;
    var accept = card.getAttribute('data-accept') || '*/*';
    var max = parseInt(card.getAttribute('data-max'), 10) || field.maxFiles || 5;
    var items = normalizeUploadItems(values[uKey]);
    var room = max - items.filter(function (it) {
      return it.status !== 'error';
    }).length;
    if (room <= 0) {
      if (global.DunesAppUI && DunesAppUI.toast) DunesAppUI.toast('最多上传 ' + max + ' 个文件', true);
      else if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('最多上传 ' + max + ' 个文件', true);
      return;
    }
    var input = document.createElement('input');
    input.type = 'file';
    input.multiple = room > 1;
    input.accept = accept;
    input.onchange = function () {
      if (!input.files || !input.files.length) return;
      queueUploadFiles(root, uKey, field, values, notify, input.files);
    };
    input.click();
  }

  function bindUploadDrag(root, values, notify) {
    root.querySelectorAll('.xf-upload-card.xf-upload').forEach(function (card) {
      if (card._xfDragBound) return;
      card._xfDragBound = true;
      ['dragenter', 'dragover'].forEach(function (evName) {
        card.addEventListener(evName, function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          card.classList.add('drag');
        });
      });
      card.addEventListener('dragleave', function (ev) {
        ev.preventDefault();
        card.classList.remove('drag');
      });
      card.addEventListener('drop', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        card.classList.remove('drag');
        var uKey = card.dataset.key;
        var state = root._xfState;
        if (!state || !ev.dataTransfer || !ev.dataTransfer.files || !ev.dataTransfer.files.length) return;
        var field = state.fields.find(function (f) {
          return f.key === uKey;
        });
        if (!field) return;
        queueUploadFiles(root, uKey, field, values, notify, ev.dataTransfer.files);
      });
    });
  }

  function fieldWrap(field, inner, extraClass) {
    var req = field.required ? '<span class="req">*</span>' : '';
    var cls = 'fld xf-fld' + (extraClass ? ' ' + extraClass : '');
    var vis = field.visibleWhen ? ' data-visible-when="' + esc(field.visibleWhen) + '"' : '';
    if (field.type === 'section') {
      var style = field.sectionStyle && field.sectionStyle !== 'default' ? ' ' + field.sectionStyle : '';
      return '<div class="xf-ss-divider' + style + '">' + esc(field.label) + '</div>';
    }
    return (
      '<div class="' +
      cls +
      '" data-key="' +
      esc(field.key) +
      '"' +
      vis +
      '><label class="fld-lbl">' +
      esc(field.label || field.key) +
      ' ' +
      req +
      '</label>' +
      inner +
      '</div>'
    );
  }

  function renderPill(field, values, multi) {
    var opts = resolveOptions(field);
    if (field.layout === 'provinceGrid' || dictKeyFor(field) === 'provinces') {
      opts = resolveOptions({ dictKey: 'provinces', key: field.key, layout: field.layout });
    }
    var cur = values[field.key];
    var selected = multi ? (Array.isArray(cur) ? cur : []) : [cur];
    var cls = field.layout === 'provinceGrid' ? 'xf-province-grid' : 'xf-pill-group';
    var inner = opts
      .map(function (o) {
        var on = selected.indexOf(o.value) >= 0 ? ' on' : '';
        var tag = field.layout === 'provinceGrid' ? 'xf-province-pill' : 'xf-pill';
        return (
          '<span class="' +
          tag +
          on +
          '" data-pill-key="' +
          esc(field.key) +
          '" data-pill-val="' +
          esc(o.value) +
          '" data-multi="' +
          (multi ? '1' : '0') +
          '">' +
          esc(o.label) +
          '</span>'
        );
      })
      .join('');
    return fieldWrap(field, '<div class="' + cls + '">' + inner + '</div>');
  }

  function renderLevel(field, values) {
    var opts = resolveOptions(field);
    if (!opts.length) {
      opts = [
        { label: 'S', value: 'S' },
        { label: 'A', value: 'A' },
        { label: 'B', value: 'B' },
        { label: 'C', value: 'C' },
      ];
    }
    var cur = values[field.key] || 'C';
    var inner = opts
      .map(function (o) {
        var on = cur === o.value ? ' on' : '';
        return (
          '<span class="xf-lp lp-' +
          esc(o.value) +
          on +
          '" data-level-key="' +
          esc(field.key) +
          '" data-level-val="' +
          esc(o.value) +
          '">' +
          esc(o.label) +
          '</span>'
        );
      })
      .join('');
    return fieldWrap(field, '<div class="xf-lvl-pills">' + inner + '</div>');
  }

  function renderDynamicList(field, values) {
    var rows = normalizeDynamicListValue(values[field.key]);
    var cols = field.columns || [{ key: 'col1', label: '列1', type: 'text' }];
    var rowsHtml = rows
      .map(function (row, ri) {
        var cells = cols
          .map(function (col) {
            var v = row[col.key] == null ? '' : row[col.key];
            var inp =
              col.type === 'select'
                ? '<select class="fld-sel xf-dyn-in" data-list="' +
                  esc(field.key) +
                  '" data-row="' +
                  ri +
                  '" data-col="' +
                  esc(col.key) +
                  '">' +
                  (col.options || [])
                    .map(function (o) {
                      return (
                        '<option value="' +
                        esc(o.value) +
                        '"' +
                        (String(v) === String(o.value) ? ' selected' : '') +
                        '>' +
                        esc(o.label) +
                        '</option>'
                      );
                    })
                    .join('') +
                  '</select>'
                : '<input class="fld-in xf-dyn-in" data-list="' +
                  esc(field.key) +
                  '" data-row="' +
                  ri +
                  '" data-col="' +
                  esc(col.key) +
                  '" value="' +
                  esc(v) +
                  '" placeholder="' +
                  esc(col.placeholder || '') +
                  '"/>';
            return '<div class="dr-cell"><div class="dr-lbl">' + esc(col.label) + '</div>' + inp + '</div>';
          })
          .join('');
        return (
          '<div class="xf-dyn-row" data-list-row="' +
          ri +
          '">' +
          cells +
          '<button type="button" class="xf-dyn-rm" data-list="' +
          esc(field.key) +
          '" data-row="' +
          ri +
          '" aria-label="删除行" title="删除行"><i class="ti ti-x"></i></button></div>'
        );
      })
      .join('');
    var add =
      '<button type="button" class="xf-dyn-add" data-list-add="' +
      esc(field.key) +
      '">+ 添加一行</button>';
    return fieldWrap(field, '<div class="xf-dyn-list" data-list="' + esc(field.key) + '">' + rowsHtml + '</div>' + add);
  }

  function renderCellInput(fieldKey, col, row, ri, nested, nri) {
    var v = row[col.key] == null ? '' : row[col.key];
    var attrs =
      ' data-list="' +
      esc(fieldKey) +
      '" data-row="' +
      ri +
      '" data-col="' +
      esc(col.key) +
      '"';
    if (nested) {
      attrs += ' data-nested="' + esc(nested) + '" data-nested-row="' + nri + '"';
    }
    if (col.type === 'select') {
      return (
        '<select class="fld-sel xf-dyn-in"' +
        attrs +
        '>' +
        (col.options || [])
          .map(function (o) {
            return (
              '<option value="' +
              esc(o.value) +
              '"' +
              (String(v) === String(o.value) ? ' selected' : '') +
              '>' +
              esc(o.label) +
              '</option>'
            );
          })
          .join('') +
        '</select>'
      );
    }
    return (
      '<input class="fld-in xf-dyn-in" value="' +
      esc(v) +
      '" placeholder="' +
      esc(col.placeholder || '') +
      '"' +
      attrs +
      '/>'
    );
  }

  function renderStructuredTable(field, values) {
    var rows = normalizeDynamicListValue(values[field.key]);
    var cols = field.columns || [];
    var nestedKey = field.nestedKey || 'items';
    var nestedCols = field.nestedColumns || [];
    var rowsHtml = rows
      .map(function (row, ri) {
        var cells = cols
          .map(function (col) {
            return (
              '<div class="dr-cell"><div class="dr-lbl">' +
              esc(col.label) +
              '</div>' +
              renderCellInput(field.key, col, row, ri, null, 0) +
              '</div>'
            );
          })
          .join('');
        var tiers = Array.isArray(row[nestedKey]) ? row[nestedKey] : [];
        var tierHead =
          nestedCols.length > 0
            ? '<div class="xf-tier-block"><div class="xf-tier-h">达量阶梯 · 机构保费</div><table class="xf-tier-table"><thead><tr>' +
              nestedCols
                .map(function (c) {
                  return '<th>' + esc(c.label) + '</th>';
                })
                .join('') +
              '<th></th></tr></thead><tbody>' +
              tiers
                .map(function (tier, ti) {
                  return (
                    '<tr><td colspan="' +
                    nestedCols.length +
                    '"><div class="xf-tier-cells">' +
                    nestedCols
                      .map(function (col) {
                        return renderCellInput(field.key, col, tier, ri, nestedKey, ti);
                      })
                      .join('') +
                    '</div></td><td><button type="button" class="xf-tier-rm" data-list="' +
                    esc(field.key) +
                    '" data-row="' +
                    ri +
                    '" data-nested-row="' +
                    ti +
                    '" aria-label="删除档位" title="删除档位"><i class="ti ti-x"></i></button></td></tr>'
                  );
                })
                .join('') +
              '</tbody></table><button type="button" class="xf-tier-add" data-list="' +
              esc(field.key) +
              '" data-row="' +
              ri +
              '">+ 添加档位</button></div>'
            : '';
        return (
          '<div class="xf-struct-row" data-list-row="' +
          ri +
          '">' +
          cells +
          tierHead +
          '<button type="button" class="xf-dyn-rm" data-list="' +
          esc(field.key) +
          '" data-row="' +
          ri +
          '" aria-label="删除行" title="删除行"><i class="ti ti-x"></i></button></div>'
        );
      })
      .join('');
    var add =
      '<button type="button" class="xf-dyn-add" data-list-add="' +
      esc(field.key) +
      '" data-structured="1">+ 添加供货商</button>';
    return fieldWrap(
      field,
      '<div class="xf-struct-list" data-list="' + esc(field.key) + '" data-nested-key="' + esc(nestedKey) + '">' + rowsHtml + '</div>' + add,
    );
  }

  function renderMatrix(field, values) {
    var rows = normalizeDynamicListValue(values[field.key]);
    var cols = field.columns || [{ key: 'col1', label: '列1', type: 'text' }];
    var head =
      '<thead><tr>' +
      cols.map(function (c) {
        return '<th>' + esc(c.label) + '</th>';
      }).join('') +
      '<th></th></tr></thead>';
    var body = rows
      .map(function (row, ri) {
        var cells = cols
          .map(function (col) {
            var v = row[col.key] == null ? '' : row[col.key];
            return (
              '<td><input class="fld-in xf-dyn-in xf-matrix-in" data-list="' +
              esc(field.key) +
              '" data-row="' +
              ri +
              '" data-col="' +
              esc(col.key) +
              '" value="' +
              esc(v) +
              '" placeholder="' +
              esc(col.placeholder || '') +
              '"/></td>'
            );
          })
          .join('');
        return (
          '<tr class="xf-matrix-row" data-list-row="' +
          ri +
          '">' +
          cells +
          '<td><button type="button" class="xf-dyn-rm" data-list="' +
          esc(field.key) +
          '" data-row="' +
          ri +
          '" aria-label="删除行" title="删除行"><i class="ti ti-x"></i></button></td></tr>'
        );
      })
      .join('');
    var add =
      '<button type="button" class="xf-dyn-add" data-list-add="' +
      esc(field.key) +
      '">+ 添加一行</button>';
    return fieldWrap(
      field,
      '<div class="xf-matrix-wrap" data-list="' +
        esc(field.key) +
        '"><table class="xf-matrix-table">' +
        head +
        '<tbody>' +
        body +
        '</tbody></table></div>' +
        add,
    );
  }

  function renderComputed(field, values) {
    var v = '';
    if (field.hook === 'stampTax') v = L().stampTax(values);
    else if (field.computeExpr) v = L().evalExpr(field.computeExpr, values);
    values[field.key] = v;
    return fieldWrap(
      field,
      '<div class="xf-computed" id="xf-cmp-' + esc(field.key) + '" data-computed="' + esc(field.key) + '">' + esc(v || '—') + '</div>',
    );
  }

  function renderAction(field) {
    var kind = field.actionKind || 'custom';
    return (
      '<button type="button" class="xf-action-btn act-' +
      esc(kind) +
      '" data-action="' +
      esc(kind) +
      '" data-action-key="' +
      esc(field.key) +
      '">' +
      esc(field.label || '操作') +
      '</button>'
    );
  }

  function renderActionBar(fields, values, allFields) {
    var actions = fields.filter(function (f) {
      return (
        f.type === 'action' &&
        f.actionKind !== 'excel-import' &&
        f.actionKind !== 'ai-policy' &&
        f.actionKind !== 'ai-summary'
      );
    });
    if (!actions.length) return '';
    return (
      '<div class="xf-action-bar">' +
      actions
        .map(function (f) {
          return renderAction(f);
        })
        .join('') +
      '</div>'
    );
  }

  function renderBasic(field, values, idx) {
    var id = 'xf-f-' + idx;
    var val = values[field.key] == null ? field.defaultValue || '' : values[field.key];
    var input = '';
    if (field.type === 'textarea') {
      input = '<textarea class="fld-in xf-in" id="' + id + '" data-key="' + esc(field.key) + '" rows="3">' + esc(val) + '</textarea>';
    } else if (field.type === 'select') {
      input =
        '<select class="fld-sel xf-in" id="' +
        id +
        '" data-key="' +
        esc(field.key) +
        '">' +
        resolveOptions(field)
          .map(function (o) {
            return (
              '<option value="' +
              esc(o.value) +
              '"' +
              (String(val) === String(o.value) ? ' selected' : '') +
              '>' +
              esc(o.label) +
              '</option>'
            );
          })
          .join('') +
        '</select>';
    } else if (field.type === 'date') {
      input =
        '<input class="fld-in mono xf-in" type="date" id="' +
        id +
        '" data-key="' +
        esc(field.key) +
        '" value="' +
        esc(val) +
        '"/>';
    } else if (field.type === 'upload') {
      return (
        '<div class="fld xf-fld xf-fld-upload" data-key="' +
        esc(field.key) +
        '">' +
        renderUploadField(field, values) +
        '</div>'
      );
    } else if (field.type === 'money' || field.type === 'number') {
      input =
        '<input class="fld-in mono xf-in" inputmode="decimal" id="' +
        id +
        '" data-key="' +
        esc(field.key) +
        '" value="' +
        esc(val) +
        '" placeholder="' +
        esc(field.placeholder || '') +
        '"/>';
    } else if (field.type === 'user') {
      var uid = userIdOf(val);
      var uname = userDisplay(val);
      input =
        '<div class="xf-user-picker" data-user-key="' +
        esc(field.key) +
        '">' +
        '<input class="fld-in xf-user-display" id="' +
        id +
        '" value="' +
        esc(uname) +
        '" placeholder="' +
        esc(field.placeholder || '搜索姓名/部门') +
        '" autocomplete="off"/>' +
        '<input type="hidden" class="xf-user-id" data-key="' +
        esc(field.key) +
        '" value="' +
        esc(uid) +
        '"/>' +
        '<div class="xf-user-dropdown hidden"></div></div>';
    } else {
      var ro = field.readonly ? ' readonly style="background:var(--bg-soft)"' : '';
      input =
        '<input class="fld-in xf-in" id="' +
        id +
        '" data-key="' +
        esc(field.key) +
        '" value="' +
        esc(val) +
        '" placeholder="' +
        esc(field.placeholder || '') +
        '"' +
        ro +
        '/>';
    }
    return fieldWrap(field, input);
  }

  function renderField(field, values, idx, allFields) {
    if (field.type === 'row') {
      var childKeys = field.children || [];
      var inner = childKeys
        .map(function (k) {
          var cf = allFields.find(function (f) {
            return f.key === k;
          });
          return cf ? renderField(cf, values, idx, allFields) : '';
        })
        .join('');
      return '<div class="xf-fld-row">' + inner + '</div>';
    }
    switch (field.type) {
      case 'section':
        return fieldWrap(field, '');
      case 'pill':
        return renderPill(field, values, false);
      case 'multiSelect':
        return renderPill(field, values, true);
      case 'level':
        return renderLevel(field, values);
      case 'dynamicList':
        return renderDynamicList(field, values);
      case 'structuredTable':
        return renderStructuredTable(field, values);
      case 'matrix':
        return renderMatrix(field, values);
      case 'computed':
        return renderComputed(field, values);
      case 'action':
        return renderAction(field);
      default:
        return renderBasic(field, values, idx);
    }
  }

  function renderForm(fields, values, layout) {
    var byKey = {};
    fields.forEach(function (f) {
      byKey[f.key] = f;
    });
    var rowChildren = {};
    fields.forEach(function (f) {
      if (f.type === 'row' && f.children) {
        f.children.forEach(function (k) {
          rowChildren[k] = true;
        });
      }
    });
    var progressHtml =
      '<div class="xf-progress-card"><div style="display:flex;justify-content:space-between;font-size:11px"><span>提案完整度</span><span><span id="xf-progress-val">0</span>%</span></div><div class="bar"><i id="xf-progress-bar" style="width:0%"></i></div><div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;font-size:10px;margin-top:6px"><span>业务 <span id="xf-biz-meta">0/0</span></span><span>财务 <span id="xf-fin-meta">0/0</span></span></div></div>';
    var actionKeys = {};
    fields.forEach(function (f) {
      if (
        f.type === 'action' &&
        f.actionKind !== 'excel-import' &&
        f.actionKind !== 'ai-policy' &&
        f.actionKind !== 'ai-summary'
      ) {
        actionKeys[f.key] = true;
      }
    });
    var html =
      progressHtml +
      renderActionBar(fields, values, fields) +
      '<div class="xf-form-card"><div id="xf-form-fields-inner">' +
      fields
        .map(function (f, i) {
          if (rowChildren[f.key] || actionKeys[f.key]) return '';
          return renderField(f, values, i, fields);
        })
        .join('') +
      '</div></div><div id="xf-tech-approver-preview"></div>';
    return html;
  }

  function listFieldHtml(field, values) {
    if (field.type === 'matrix') return renderMatrix(field, values);
    if (field.type === 'structuredTable') return renderStructuredTable(field, values);
    return renderDynamicList(field, values);
  }

  function rerenderListField(root, field, values) {
    if (!root || !field) return;
    var parent = root.querySelector('.xf-fld[data-key="' + field.key + '"]');
    if (!parent) return;
    parent.outerHTML = listFieldHtml(field, values);
  }

  function rerenderFormFields(root, fields, values, layout) {
    if (!root) return;
    var rowChildren = {};
    fields.forEach(function (f) {
      if (f.type === 'row' && f.children) {
        f.children.forEach(function (k) {
          rowChildren[k] = true;
        });
      }
    });
    var actionKeys = {};
    fields.forEach(function (f) {
      if (
        f.type === 'action' &&
        f.actionKind !== 'excel-import' &&
        f.actionKind !== 'ai-policy' &&
        f.actionKind !== 'ai-summary'
      ) {
        actionKeys[f.key] = true;
      }
    });
    var inner = root.querySelector('#xf-form-fields-inner');
    if (!inner) return;
    inner.innerHTML = fields
      .map(function (f, i) {
        if (rowChildren[f.key] || actionKeys[f.key]) return '';
        return renderField(f, values, i, fields);
      })
      .join('');
    if (root._xfState) {
      bindUserPickers(root, root._xfState.apiFn, root._xfState.values, root._xfNotify);
      bindUploadDrag(root, root._xfState.values, root._xfNotify);
    }
  }

  function syncDynInput(el, values) {
    var key = el.dataset.list;
    var ri = parseInt(el.dataset.row, 10);
    var col = el.dataset.col;
    var nested = el.dataset.nested;
    var nri = el.dataset.nestedRow != null ? parseInt(el.dataset.nestedRow, 10) : -1;
    if (!key || isNaN(ri)) return;
    if (!Array.isArray(values[key])) values[key] = [];
    if (nested && nri >= 0) {
      if (!values[key][ri]) values[key][ri] = {};
      if (!Array.isArray(values[key][ri][nested])) values[key][ri][nested] = [];
      if (!values[key][ri][nested][nri]) values[key][ri][nested][nri] = {};
      values[key][ri][nested][nri][col] = el.value;
    } else {
      if (!values[key][ri]) values[key][ri] = {};
      values[key][ri][col] = el.value;
    }
  }

  function clearDynRow(rowEl) {
    rowEl.querySelectorAll('input,select,textarea').forEach(function (el) {
      if (el.tagName === 'SELECT') el.selectedIndex = 0;
      else el.value = '';
    });
  }

  function bindUserPickers(root, apiFn, values, notify) {
    if (!apiFn && !(global.XFlowDynamic && global.XFlowDynamic.searchOrgUsers)) return;
    function searchUsers(q) {
      if (global.XFlowDynamic && global.XFlowDynamic.searchOrgUsers) {
        return global.XFlowDynamic.searchOrgUsers(q);
      }
      return apiFn('/org/users?q=' + encodeURIComponent(q)).then(function (res) {
        return res && res.data !== undefined ? res.data : res;
      });
    }
    function searchFailed(err) {
      var msg =
        global.XFlowDynamic && global.XFlowDynamic.translateSubmitError
          ? global.XFlowDynamic.translateSubmitError(err && err.message)
          : '人员搜索失败';
      if (global.DunesAppUI && global.DunesAppUI.toast) global.DunesAppUI.toast(msg, true);
      else if (global.DunesAPI && global.DunesAPI.toast) global.DunesAPI.toast(msg, true);
    }
    root.querySelectorAll('.xf-user-picker').forEach(function (wrap) {
      if (wrap._xfUserBound) return;
      wrap._xfUserBound = true;
      var key = wrap.getAttribute('data-user-key');
      var input = wrap.querySelector('.xf-user-display');
      var hid = wrap.querySelector('.xf-user-id');
      var drop = wrap.querySelector('.xf-user-dropdown');
      if (!input || !drop) return;
      var timer = null;
      function closeDrop() {
        drop.classList.add('hidden');
      }
      function pick(user) {
        values[key] = {
          userId: user.id || user.userId,
          name: user.displayName || user.name,
          dept: user.departmentName || user.dept || '',
          title: user.title || '',
        };
        input.value = values[key].name;
        if (hid) hid.value = String(values[key].userId);
        closeDrop();
        if (notify) notify();
      }
      function renderUsers(list) {
        if (!list || !list.length) {
          drop.innerHTML = '<div class="xf-user-empty">无匹配人员</div>';
          drop.classList.remove('hidden');
          return;
        }
        drop.innerHTML = list
          .slice(0, 8)
          .map(function (u) {
            var label = (u.displayName || u.name || '') + (u.departmentName ? ' · ' + u.departmentName : '');
            return (
              '<button type="button" class="xf-user-opt" data-uid="' +
              esc(u.id || u.userId) +
              '">' +
              esc(label) +
              '</button>'
            );
          })
          .join('');
        drop.classList.remove('hidden');
        drop.querySelectorAll('.xf-user-opt').forEach(function (btn) {
          btn.addEventListener('click', function (ev) {
            ev.preventDefault();
            var uid = btn.getAttribute('data-uid');
            var user = list.find(function (u) {
              return String(u.id || u.userId) === String(uid);
            });
            if (user) pick(user);
          });
        });
      }
      input.addEventListener('input', function () {
        clearTimeout(timer);
        var q = input.value.trim();
        if (q.length < 1) {
          closeDrop();
          return;
        }
        timer = setTimeout(function () {
          searchUsers(q)
            .then(function (data) {
              renderUsers(Array.isArray(data) ? data : []);
            })
            .catch(function (err) {
              searchFailed(err);
              renderUsers([]);
            });
        }, 220);
      });
      input.addEventListener('focus', function () {
        var q = input.value.trim();
        if (q.length >= 1) input.dispatchEvent(new Event('input'));
      });
      document.addEventListener('click', function (ev) {
        if (!wrap.contains(ev.target)) closeDrop();
      });
    });
  }

  function bindActionButtons(root, fields, values, layout) {
    root.querySelectorAll('.xf-action-btn').forEach(function (btn) {
      if (btn._xfActBound) return;
      btn._xfActBound = true;
      function fire(ev) {
        ev.preventDefault();
        ev.stopPropagation();
        var state = root._xfState;
        if (!state) return;
        collectValues(root, state.fields, state.values);
        var kind = btn.dataset.action;
        if (L().handleAction) {
          L().handleAction(kind, state.values, state.fields, state.layout, function () {
            rerenderFormFields(root, state.fields, state.values, state.layout);
            root._xfNotify();
          });
          return;
        }
        if (kind === 'save-draft') {
          try {
            localStorage.setItem('xf_draft_' + (global.pendingXFlowKey || ''), JSON.stringify(state.values));
            if (global.DunesAppUI && DunesAppUI.tip) DunesAppUI.tip('草稿已暂存');
            else if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('草稿已暂存');
          } catch (err) {
            /* ignore */
          }
        } else if (global.DunesAPI && DunesAPI.toast) {
          DunesAPI.toast('操作：' + kind);
        }
      }
      btn.addEventListener('click', fire);
    });
  }

  function bindForm(root, fields, values, layout, onChange, apiFn) {
    if (!root) return;

    root._xfState = { fields: fields, values: values, layout: layout || {}, onChange: onChange, apiFn: apiFn };

    function notify() {
      var state = root._xfState;
      if (!state) return;
      L().runHooks(state.layout, state.values);
      state.fields.forEach(function (f) {
        if (f.type === 'computed') {
          var el = root.querySelector('[data-computed="' + f.key + '"]');
          if (el) {
            var v = f.hook === 'stampTax' ? L().stampTax(state.values) : L().evalExpr(f.computeExpr, state.values);
            state.values[f.key] = v;
            el.textContent = v || '—';
          }
        }
      });
      root.querySelectorAll('.xf-fld[data-visible-when]').forEach(function (el) {
        var cond = el.getAttribute('data-visible-when');
        el.classList.toggle('hidden', !L().parseCond(cond, state.values));
      });
      L().updateProgress(state.layout, state.values);
      if (state.onChange) state.onChange(state.values);
    }
    root._xfNotify = notify;

    if (!root._xfDelegated) {
      root._xfDelegated = true;

      root.addEventListener('click', function (e) {
        var state = root._xfState;
        if (!state) return;
        var values = state.values;
        var fields = state.fields;
        var layout = state.layout;
        var notify = root._xfNotify;

        var addBtn = e.target.closest('[data-list-add]');
        if (addBtn) {
          e.preventDefault();
          e.stopPropagation();
          var key = addBtn.getAttribute('data-list-add');
          if (!Array.isArray(values[key])) values[key] = [];
          var col = fields.find(function (f) {
            return f.key === key;
          });
          if (!col) return;
          var row = {};
          (col.columns || []).forEach(function (c) {
            row[c.key] = '';
          });
          if (col.type === 'structuredTable' && col.nestedKey) {
            row[col.nestedKey] = [];
          }
          values[key].push(row);
          rerenderListField(root, col, values);
          notify();
          return;
        }

        var rmBtn = e.target.closest('.xf-dyn-rm');
        if (rmBtn) {
          e.preventDefault();
          e.stopPropagation();
          var rmKey = rmBtn.dataset.list;
          var ri = parseInt(rmBtn.dataset.row, 10);
          var rmCol = fields.find(function (f) {
            return f.key === rmKey;
          });
          if (Array.isArray(values[rmKey])) {
            values[rmKey].splice(ri, 1);
            rerenderListField(root, rmCol, values);
          }
          notify();
          return;
        }

        var tierAdd = e.target.closest('.xf-tier-add');
        if (tierAdd) {
          e.preventDefault();
          e.stopPropagation();
          var tKey = tierAdd.dataset.list;
          var tRi = parseInt(tierAdd.dataset.row, 10);
          var tCol = fields.find(function (f) {
            return f.key === tKey;
          });
          if (!tCol || !tCol.nestedKey) return;
          if (!Array.isArray(values[tKey])) values[tKey] = [];
          if (!values[tKey][tRi]) values[tKey][tRi] = {};
          if (!Array.isArray(values[tKey][tRi][tCol.nestedKey])) values[tKey][tRi][tCol.nestedKey] = [];
          var tier = {};
          (tCol.nestedColumns || []).forEach(function (c) {
            tier[c.key] = '';
          });
          values[tKey][tRi][tCol.nestedKey].push(tier);
          rerenderListField(root, tCol, values);
          notify();
          return;
        }

        var tierRm = e.target.closest('.xf-tier-rm');
        if (tierRm) {
          e.preventDefault();
          e.stopPropagation();
          var trKey = tierRm.dataset.list;
          var trRi = parseInt(tierRm.dataset.row, 10);
          var trTi = parseInt(tierRm.dataset.nestedRow, 10);
          var trCol = fields.find(function (f) {
            return f.key === trKey;
          });
          if (trCol && trCol.nestedKey && values[trKey] && values[trKey][trRi]) {
            values[trKey][trRi][trCol.nestedKey].splice(trTi, 1);
            rerenderListField(root, trCol, values);
          }
          notify();
          return;
        }

        var pill = e.target.closest('.xf-pill, .xf-province-pill');
        if (pill) {
          e.preventDefault();
          e.stopPropagation();
          var pKey = pill.dataset.pillKey;
          var pVal = pill.dataset.pillVal;
          var multi = pill.dataset.multi === '1';
          if (multi) {
            var arr = Array.isArray(values[pKey]) ? values[pKey].slice() : [];
            var ix = arr.indexOf(pVal);
            if (ix >= 0) arr.splice(ix, 1);
            else arr.push(pVal);
            values[pKey] = arr;
          } else {
            values[pKey] = pVal;
            root.querySelectorAll('[data-pill-key="' + pKey + '"]').forEach(function (p) {
              p.classList.toggle('on', p.dataset.pillVal === pVal);
            });
          }
          root.querySelectorAll('[data-pill-key="' + pKey + '"]').forEach(function (p) {
            if (multi) {
              var a = values[pKey] || [];
              p.classList.toggle('on', a.indexOf(p.dataset.pillVal) >= 0);
            }
          });
          (layout.linkage || []).forEach(function (rule) {
            if (rule.type === 'optionsFrom' && rule.source === pKey && rule.target) {
              L().applyOptionsFrom(pKey, rule.target, values, rule.rowShape);
              var tf = fields.find(function (f) {
                return f.key === rule.target;
              });
              if (tf) rerenderListField(root, tf, values);
            }
          });
          notify();
          return;
        }

        var lp = e.target.closest('.xf-lp');
        if (lp) {
          e.preventDefault();
          e.stopPropagation();
          var lKey = lp.dataset.levelKey;
          values[lKey] = lp.dataset.levelVal;
          root.querySelectorAll('[data-level-key="' + lKey + '"]').forEach(function (p) {
            p.classList.toggle('on', p.dataset.levelVal === values[lKey]);
          });
          notify();
          return;
        }

        var upload = e.target.closest('.xf-upload');
        if (upload && !e.target.closest('.xf-uf-del')) {
          e.preventDefault();
          e.stopPropagation();
          var uKey = upload.dataset.key;
          var uField = fields.find(function (f) {
            return f.key === uKey;
          });
          if (uField) pickUploadFiles(root, uKey, uField, values, notify);
          return;
        }

        var delUpload = e.target.closest('.xf-uf-del');
        if (delUpload) {
          e.preventDefault();
          e.stopPropagation();
          var listKey = delUpload.getAttribute('data-upload-key');
          var itemId = delUpload.getAttribute('data-upload-id');
          var arr = normalizeUploadItems(values[listKey]);
          values[listKey] = arr.filter(function (it) {
            return String(it.id) !== String(itemId);
          });
          renderUploadFilesList(root, listKey, values[listKey]);
          notify();
          return;
        }

        var actBtn = e.target.closest('.xf-action-btn');
        if (actBtn) {
          e.preventDefault();
          e.stopPropagation();
          collectValues(root, fields, values);
          var kind = actBtn.dataset.action;
          if (L().handleAction) {
            L().handleAction(kind, values, fields, layout, function () {
              rerenderFormFields(root, fields, values, layout);
              notify();
            });
            bindActionButtons(root, fields, values, layout);
            return;
          }
          if (kind === 'save-draft') {
            try {
              localStorage.setItem('xf_draft_' + (global.pendingXFlowKey || ''), JSON.stringify(values));
              if (global.DunesAppUI && DunesAppUI.tip) DunesAppUI.tip('草稿已暂存');
              else if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('草稿已暂存');
            } catch (err) {
              /* ignore */
            }
          } else if (global.DunesAPI && DunesAPI.toast) {
            DunesAPI.toast('操作：' + kind);
          }
        }
      });

      root.addEventListener('input', function (e) {
        var state = root._xfState;
        if (!state) return;
        var el = e.target;
        if (el.classList && el.classList.contains('xf-in') && el.dataset.key) {
          state.values[el.dataset.key] = el.value;
          root._xfNotify();
          return;
        }
        if (el.classList && el.classList.contains('xf-dyn-in')) {
          syncDynInput(el, state.values);
          root._xfNotify();
        }
      });

      root.addEventListener('change', function (e) {
        var state = root._xfState;
        if (!state) return;
        var el = e.target;
        if (el.classList && el.classList.contains('xf-in') && el.dataset.key) {
          state.values[el.dataset.key] = el.value;
          root._xfNotify();
          return;
        }
        if (el.classList && el.classList.contains('xf-dyn-in')) {
          syncDynInput(el, state.values);
          root._xfNotify();
        }
      });
    }

    notify();
    bindActionButtons(root, fields, values, layout);
    bindUserPickers(root, apiFn || (global.XFlowDynamic && global.XFlowDynamic.api), values, notify);
    bindUploadDrag(root, values, notify);
  }

  function collectValues(root, fields, values) {
    root.querySelectorAll('.xf-in').forEach(function (el) {
      if (el.dataset.key) values[el.dataset.key] = el.value;
    });
    var pillKeys = {};
    root.querySelectorAll('.xf-pill.on[data-pill-key], .xf-province-pill.on[data-pill-key]').forEach(function (p) {
      var k = p.dataset.pillKey;
      if (!k) return;
      if (!pillKeys[k]) pillKeys[k] = [];
      pillKeys[k].push(p.dataset.pillVal);
    });
    Object.keys(pillKeys).forEach(function (k) {
      var field = (fields || []).find(function (f) {
        return f.key === k;
      });
      var isMulti =
        (field && (field.type === 'multiSelect' || field.layout === 'provinceGrid' || field.multiple)) ||
        pillKeys[k].length > 1;
      values[k] = isMulti ? pillKeys[k] : pillKeys[k][0] || '';
    });
    root.querySelectorAll('.xf-lvl-pills .xf-lp.on').forEach(function (on) {
      var k = on.dataset.levelKey;
      if (k) values[k] = on.dataset.levelVal || '';
    });
    (fields || []).forEach(function (f) {
      if (f.type === 'upload') {
        var arr = normalizeUploadItems(values[f.key]);
        values[f.key] = arr.filter(function (it) {
          return it.status === 'done' && (it.url || it.objectKey);
        });
        return;
      }
      if (f.type !== 'user' && f.dataSource !== 'org_user') return;
      var hid = root.querySelector('.xf-user-id[data-key="' + f.key + '"]');
      var disp = root.querySelector('.xf-user-picker[data-user-key="' + f.key + '"] .xf-user-display');
      if (hid && hid.value) {
        var prev = values[f.key];
        values[f.key] = {
          userId: parseInt(hid.value, 10) || hid.value,
          name: disp ? disp.value : userDisplay(prev),
          dept: prev && prev.dept ? prev.dept : '',
          title: prev && prev.title ? prev.title : '',
        };
      }
    });
    return values;
  }

  global.XFlowRender = {
    renderForm: renderForm,
    bindForm: bindForm,
    collectValues: collectValues,
    renderField: renderField,
    enrichFieldsFromDicts: enrichFieldsFromDicts,
    resolveOptions: resolveOptions,
    clearDictCache: function () {
      dictCache = {};
    },
  };
})(typeof window !== 'undefined' ? window : global);
