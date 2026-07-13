(function (global) {
  'use strict';

  var PREVIEW_LIMIT = 6;

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }

  function statusLabel(st) {
    var map = {
      draft: '草稿',
      pending_initiate: '待确认发起',
      pending: '审批中',
      approved: '已通过',
      rejected: '已驳回',
      voided: '已作废',
    };
    return map[st] || st || '—';
  }

  function statusClass(st) {
    if (st === 'approved') return 'ok';
    if (st === 'rejected') return 'bad';
    if (st === 'pending' || st === 'pending_initiate') return 'warn';
    return 'muted';
  }

  function fmtList(arr) {
    if (!arr || !arr.length) return '—';
    return arr
      .map(function (x) {
        if (x == null || x === '') return '';
        if (typeof x === 'string') return x;
        return x.label || x.name || x.province || String(x);
      })
      .filter(Boolean)
      .join('、');
  }

  function formatUserDisplay(v) {
    if (v == null || v === '') return '';
    if (typeof v === 'string') {
      if (v.indexOf('map[') === 0) return '';
      return v;
    }
    if (typeof v === 'object') {
      var name = v.displayName || v.name || '';
      var dept = v.dept || v.departmentName || '';
      var title = v.title || '';
      var meta = [dept, title].filter(Boolean).join(' · ');
      if (name && meta) return name + '（' + meta + '）';
      return name || (v.userId != null ? '用户#' + v.userId : '');
    }
    return String(v);
  }

  function normalizeDynamicListValue(val) {
    if (val == null || val === '') return [];
    if (Array.isArray(val)) return val;
    if (typeof val === 'object') return [val];
    return [];
  }

  function resolveOptions(field) {
    if (global.XFlowRender && global.XFlowRender.resolveOptions) {
      return global.XFlowRender.resolveOptions(field);
    }
    return field.options || [];
  }

  function labelForOptionValue(field, value) {
    if (value == null || value === '') return '';
    var options = resolveOptions(field);
    for (var i = 0; i < options.length; i++) {
      if (String(options[i].value) === String(value)) return options[i].label;
    }
    return String(value);
  }

  function formatFieldValue(field, val) {
    if (val == null || val === '') return '';
    field = field || {};
    var t = field.type || 'text';
    if (t === 'user') return formatUserDisplay(val) || '—';
    if (t === 'upload') {
      var files = normalizeUploadItems(val);
      return files.length ? files.length + ' 个文件' : '';
    }
    if (t === 'multiSelect') {
      var msArr = Array.isArray(val) ? val : [val];
      if (!msArr.length) return '';
      return msArr
        .map(function (v) {
          return labelForOptionValue(field, v);
        })
        .filter(Boolean)
        .join('、');
    }
    if (t === 'select' || t === 'pill' || t === 'level') {
      return labelForOptionValue(field, val);
    }
    if (Array.isArray(val)) {
      if (!val.length) return '';
      if (t === 'dynamicList' || t === 'matrix' || t === 'structuredTable') {
        return val.length + '行';
      }
      if (typeof val[0] === 'object') {
        return val
          .map(function (row) {
            if (row == null) return '';
            if (typeof row === 'string') return row;
            if (row.fileName) return row.fileName;
            if (row.label) return row.label;
            if (row.name) return row.name;
            if (row.province) return row.province;
            if (row.value) return row.value;
            return JSON.stringify(row);
          })
          .filter(Boolean)
          .join('、');
      }
      return val.filter(Boolean).join('、');
    }
    if (typeof val === 'object') {
      if (t === 'dynamicList' || t === 'matrix' || t === 'structuredTable') {
        return '1行';
      }
      if (val.fileName) return val.fileName;
      if (val.text) return val.text;
      return formatUserDisplay(val) || JSON.stringify(val);
    }
    if (typeof val === 'boolean') return val ? '是' : '否';
    return String(val);
  }

  var COL_LABELS = {
    cycle: '周期类型',
    term: '账期',
    weight: '权重(%)',
    province: '省份',
    note: '备注',
    rate: '折扣率',
    supplier: '供货商',
    baseTier: '基准档',
    currentRate: '当前费率',
    marketing: '营销费率',
    nonOil: '非油',
    channel: '渠道',
    universalRate: '通用费率',
    marketingRate: '营销费率',
    product: '产品',
    cost: '成本',
    salePrice: '售价',
    customerPrice: '客户价',
    rebate: '返佣',
    tierType: '档位类型',
    threshold: '阈值',
  };

  function isExpandableField(field, val) {
    if (!field || val == null) return false;
    var t = field.type || '';
    if (t === 'dynamicList' || t === 'matrix' || t === 'structuredTable' || t === 'upload') {
      return Array.isArray(val) ? val.length > 0 : normalizeUploadItems(val).length > 0;
    }
    return false;
  }

  function inferColumns(rows, field) {
    field = field || {};
    if (field.columns && field.columns.length) return field.columns;
    if (!rows || !rows.length || typeof rows[0] !== 'object') return [];
    var nestedKey = field.nestedKey || 'items';
    return Object.keys(rows[0])
      .filter(function (k) {
        return k !== nestedKey && !Array.isArray(rows[0][k]) && typeof rows[0][k] !== 'object';
      })
      .map(function (k) {
        return { key: k, label: COL_LABELS[k] || k };
      });
  }

  function formatCellDisplay(val, col, row) {
    if (val == null || val === '') {
      if (row && col && col.key) {
        var aliases = {
          note: ['description', 'desc', 'remark'],
          rate: ['discount', 'ratio', 'value'],
          province: ['prov', 'name'],
          term: ['ratio', 'period', 'cycleType'],
          cycle: ['type', 'cycleType'],
          weight: ['ratio', 'percent', 'pct'],
        };
        var alts = aliases[col.key] || [];
        for (var i = 0; i < alts.length; i++) {
          if (row[alts[i]] != null && String(row[alts[i]]).trim() !== '') {
            val = row[alts[i]];
            break;
          }
        }
      }
    }
    if (val == null || val === '') return '—';
    if (col && col.type === 'select' && col.options) {
      var hit = (col.options || []).find(function (o) {
        return String(o.value) === String(val);
      });
      if (hit) return hit.label;
    }
    if (typeof val === 'object') return formatUserDisplay(val) || JSON.stringify(val);
    return String(val);
  }

  function renderNestedTable(nestedCols, nestedRows) {
    nestedCols = nestedCols && nestedCols.length ? nestedCols : inferColumns(nestedRows, {});
    if (!nestedCols.length || !nestedRows.length) return '';
    var html =
      '<div class="xf-det-nested"><table class="xf-det-table xf-det-table-nested"><thead><tr>';
    nestedCols.forEach(function (col) {
      html += '<th>' + esc(col.label || col.key) + '</th>';
    });
    html += '</tr></thead><tbody>';
    nestedRows.forEach(function (row) {
      html += '<tr>';
      nestedCols.forEach(function (col) {
        html += '<td>' + esc(formatCellDisplay(row[col.key], col, row)) + '</td>';
      });
      html += '</tr>';
    });
    return html + '</tbody></table></div>';
  }

  function renderTableDetail(field, rows) {
    rows = normalizeDynamicListValue(rows);
    if (!rows.length) return '<div class="hint">暂无明细</div>';
    var cols = inferColumns(rows, field);
    if (!cols.length) {
      return (
        '<pre class="xf-det-json">' +
        esc(JSON.stringify(rows, null, 2)) +
        '</pre>'
      );
    }
    var nestedKey = (field && field.nestedKey) || 'items';
    var nestedCols = (field && field.nestedColumns) || [];
    var html = '<div class="xf-det-table-wrap"><table class="xf-det-table"><thead><tr>';
    cols.forEach(function (col) {
      html += '<th>' + esc(col.label || col.key) + '</th>';
    });
    html += '</tr></thead><tbody>';
    rows.forEach(function (row) {
      html += '<tr>';
      cols.forEach(function (col) {
        html += '<td>' + esc(formatCellDisplay(row[col.key], col, row)) + '</td>';
      });
      html += '</tr>';
      if (Array.isArray(row[nestedKey]) && row[nestedKey].length) {
        html +=
          '<tr class="xf-det-tr-nested"><td colspan="' +
          cols.length +
          '">' +
          renderNestedTable(nestedCols, row[nestedKey]) +
          '</td></tr>';
      }
    });
    return html + '</tbody></table></div>';
  }

  function normalizeUploadItems(val) {
    if (!val) return [];
    if (!Array.isArray(val)) {
      if (typeof val === 'string' && val.trim()) {
        return [{ id: 'uf-0', fileName: val, status: 'done', progress: 100 }];
      }
      return [];
    }
    return val.map(function (it, i) {
      if (typeof it === 'string') {
        return { id: 'uf-' + i, fileName: it, status: 'done', progress: 100 };
      }
      return Object.assign(
        {
          id: it.id || 'uf-' + i,
          fileName: it.fileName || it.name || '未命名文件',
          status: it.status || (it.url || it.objectKey ? 'done' : 'uploading'),
          progress: it.progress != null ? it.progress : it.url || it.objectKey ? 100 : 0,
        },
        it,
      );
    });
  }

  function storageApiBase() {
    var base = localStorage.getItem('dunes_api_base');
    if (base) return base.replace(/\/$/, '');
    var flow = localStorage.getItem('dunes_flow_api_base');
    if (flow) return flow.replace(/\/$/, '');
    var host = localStorage.getItem('dunes_api_host') || window.location.hostname || 'localhost';
    return 'http://' + host + ':6090/api/v1';
  }

  function isImageFile(item) {
    var n = String((item && item.fileName) || '').toLowerCase();
    var m = String((item && item.mimeType) || '').toLowerCase();
    return m.indexOf('image/') === 0 || /\.(jpg|jpeg|png|heic|heif|gif|webp)$/.test(n);
  }

  function storagePublicBase() {
    return (
      localStorage.getItem('dunes_storage_public_base') ||
      localStorage.getItem('dunes_ftp_public_base') ||
      'https://image.heunion.com/zdfiles'
    ).replace(/\/$/, '');
  }

  function joinPublicUrl(base, objectKey) {
    if (!objectKey) return '';
    if (/^https?:\/\//.test(objectKey)) return objectKey;
    return base.replace(/\/$/, '') + '/' + String(objectKey).replace(/^\//, '');
  }

  function resolvePublicFileUrl(item) {
    item = item || {};
    if (item.url && /^https?:\/\//.test(item.url)) return item.url;
    var key = item.objectKey || item.url || '';
    if (/^https?:\/\//.test(key)) return key;
    if (!key) return '';
    if (item.backend === 'ftp' || String(key).indexOf('proposals/') === 0 || String(key).indexOf('im/') === 0) {
      return joinPublicUrl(storagePublicBase(), key);
    }
    return '';
  }

  function buildDownloadUrl(item) {
    item = item || {};
    var direct = resolvePublicFileUrl(item);
    if (direct) return direct;
    var key = item.objectKey || item.url || '';
    if (/^https?:\/\//.test(key)) return key;
    if (!key) return '';
    var bucket = item.bucket || 'xflow-proposals';
    return (
      storageApiBase() +
      '/storage/download?bucket=' +
      encodeURIComponent(bucket) +
      '&objectKey=' +
      encodeURIComponent(key) +
      (item.fileName ? '&fileName=' + encodeURIComponent(item.fileName) : '')
    );
  }

  async function resolveMediaUrl(item) {
    item = item || {};
    var direct = resolvePublicFileUrl(item);
    if (direct) return direct;
    if (item.url && /^https?:\/\//.test(item.url)) return item.url;
    var key = item.objectKey || item.url || '';
    if (/^https?:\/\//.test(key)) return key;
    if (!key) return '';
    var bucket = item.bucket || 'xflow-proposals';
    try {
      var res = await fetch(
        storageApiBase() +
          '/storage/presigned-get?bucket=' +
          encodeURIComponent(bucket) +
          '&objectKey=' +
          encodeURIComponent(key),
      );
      var json = await res.json();
      var data = json.data !== undefined ? json.data : json;
      return (data && data.url) || '';
    } catch (e) {
      return buildDownloadUrl(item);
    }
  }

  function renderUploadDetail(field, val) {
    var items = normalizeUploadItems(val).filter(function (it) {
      return it.status !== 'error';
    });
    if (!items.length) return '<div class="hint">暂无文件</div>';
    var html = '<div class="xf-det-file-list">';
    items.forEach(function (it, i) {
      var isImg = isImageFile(it);
      html +=
        '<div class="xf-det-file-item">' +
        (isImg
          ? '<button type="button" class="xf-det-file-preview" data-file-key="' +
            esc(field.key) +
            '" data-file-idx="' +
            i +
            '"><span class="xf-det-file-thumb" data-thumb-key="' +
            esc(field.key) +
            '" data-file-idx="' +
            i +
            '"><i class="ti ti-photo"></i></span></button>'
          : '<div class="xf-det-file-icon"><i class="ti ' +
            (String(it.fileName || '').toLowerCase().indexOf('.pdf') >= 0 ? 'ti-file-type-pdf' : 'ti-file') +
            '"></i></div>') +
        '<div class="xf-det-file-meta"><div class="xf-det-file-name">' +
        esc(it.fileName) +
        '</div>' +
        (it.size ? '<div class="xf-det-file-size">' + esc(formatFileSize(it.size)) + '</div>' : '') +
        '</div>' +
        '<div class="xf-det-file-actions">' +
        (isImg
          ? '<button type="button" class="xf-det-file-view" data-file-key="' +
            esc(field.key) +
            '" data-file-idx="' +
            i +
            '"><i class="ti ti-eye"></i>预览</button>'
          : '') +
        '<button type="button" class="xf-det-file-dl" data-file-key="' +
        esc(field.key) +
        '" data-file-idx="' +
        i +
        '"><i class="ti ti-download"></i>下载</button>' +
        '</div></div>';
    });
    return html + '</div>';
  }

  function formatFileSize(bytes) {
    var n = Number(bytes) || 0;
    if (n < 1024) return n + ' B';
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
    return (n / (1024 * 1024)).toFixed(1) + ' MB';
  }

  function renderExpandDetailHtml(item) {
    var field = item.field || {};
    var val = item.rawValue;
    if (field.type === 'upload') return renderUploadDetail(field, val);
    return renderTableDetail(field, val);
  }

  function kvExpandable(item, idx) {
    var summary = item.value || '';
    return (
      '<div class="xf-det-kv-expand" data-kv-expand="' +
      esc(item.key || idx) +
      '" data-kv-summary="' +
      esc(summary) +
      '">' +
      '<button type="button" class="xf-det-kv-head">' +
      '<span class="xf-det-k">' +
      esc(item.label) +
      '</span>' +
      '<span class="xf-det-v-sum">' +
      esc(summary) +
      ' <i class="ti ti-chevron-down"></i></span>' +
      '</button>' +
      '<div class="xf-det-kv-body hidden">' +
      renderExpandDetailHtml(item) +
      '</div></div>'
    );
  }

  function kvItem(item, idx) {
    if (item.expandable) return kvExpandable(item, idx);
    return kv(item.label, item.value);
  }

  function buildFieldSections(fields, formValues, detail) {
    fields = fields || [];
    formValues = formValues || {};
    detail = detail || {};
    if ((!formValues.provinces || !formValues.provinces.length) && detail.coverage && detail.coverage.length) {
      formValues = Object.assign({}, formValues, { provinces: detail.coverage });
    }
    var priorityKeys = ['title', 'tag1', 'provinces', 'txType', 'goodType', 'proposalType', 'techPlatform', 'launchDate', 'launchChannel'];
    var sections = [];
    var current = { title: '基本信息', items: [] };
    fields.forEach(function (f) {
      if (!f || !f.key) return;
      if (f.type === 'section') {
        if (current.items.length) sections.push(current);
        current = { title: f.label || '板块', items: [] };
        return;
      }
      if (f.type === 'action' || f.type === 'row' || f.key === 'proposalCode') return;
      var val = formValues[f.key];
      if (f.type === 'dynamicList' || f.type === 'matrix' || f.type === 'structuredTable') {
        val = normalizeDynamicListValue(val);
      }
      var text = formatFieldValue(f, val);
      if (!text) return;
      var fieldDef = f;
      var expandable = isExpandableField(f, val);
      if (
        !expandable &&
        Array.isArray(val) &&
        val.length &&
        typeof val[0] === 'object' &&
        !val[0].fileName &&
        !val[0].url &&
        !val[0].objectKey
      ) {
        fieldDef = Object.assign({}, f, { type: f.type || 'dynamicList' });
        expandable = true;
        if (text.indexOf('行') < 0) text = val.length + '行';
      }
      current.items.push({
        label: f.label || f.key,
        value: text,
        key: f.key,
        field: fieldDef,
        rawValue: val,
        expandable: expandable,
      });
    });
    if (current.items.length) sections.push(current);
    sections.forEach(function (sec) {
      sec.items.sort(function (a, b) {
        var ai = priorityKeys.indexOf(a.key);
        var bi = priorityKeys.indexOf(b.key);
        if (ai >= 0 && bi >= 0) return ai - bi;
        if (ai >= 0) return -1;
        if (bi >= 0) return 1;
        return 0;
      });
    });
    if (!sections.length && formValues && Object.keys(formValues).length) {
      Object.keys(formValues).forEach(function (k) {
        if (k === 'proposalCode') return;
        var text = formatFieldValue({ type: 'text', key: k }, formValues[k]);
        if (text) current.items.push({ label: k, value: text });
      });
      if (current.items.length) sections.push(current);
    }
    return sections;
  }

  function renderHero(d) {
    var owner2 = formatUserDisplay(d.owner2) || formatUserDisplay((d.formValues || {}).owner2);
    return (
      '<div class="xf-det-hero">' +
      '<div class="xf-det-hero-top">' +
      '<span class="xf-det-code">' +
      esc(d.code || '') +
      '</span>' +
      '<span class="xf-det-status ' +
      statusClass(d.status) +
      '">' +
      esc(statusLabel(d.status)) +
      '</span></div>' +
      '<div class="xf-det-title">' +
      esc(d.title || '销售提案') +
      '</div>' +
      '<div class="xf-det-meta">' +
      '<span><i class="ti ti-tag"></i>' +
      esc(d.tag1 || '—') +
      '</span>' +
      '<span><i class="ti ti-chart-bar"></i>' +
      esc(d.taskLevel || 'C') +
      ' 级</span>' +
      '<span><i class="ti ti-map-pin"></i>' +
      esc(fmtList(d.coverage)) +
      '</span></div></div>'
    );
  }

  function buildSectionsByDetailConfig(fields, formValues, cfg, detail) {
    cfg = cfg || {};
    detail = detail || {};
    var tabs = cfg.tabs || [];
    var allSections = buildFieldSections(fields, formValues, detail);
    if (!tabs.length) return allSections;
    var tabGroups = {
      biz: ['业务元数据'],
      finance: ['财务模块', '商务模式'],
      solution: ['方案叙事'],
      tech: ['技术能力', '风控标准'],
    };
    return tabs
      .map(function (tab) {
        var titles = tabGroups[tab.key] || [String(tab.label || '').split(' · ')[0]];
        var items = [];
        allSections.forEach(function (sec) {
          if (titles.indexOf(sec.title) >= 0) items = items.concat(sec.items || []);
        });
        if (!items.length && tab.key === 'biz') {
          allSections.slice(0, 1).forEach(function (sec) {
            items = items.concat(sec.items || []);
          });
        }
        return { title: tab.label || tab.key, items: items };
      })
      .filter(function (sec) {
        return sec.items && sec.items.length;
      });
  }

  function lastRejectStep(trail, assigneeNames) {
    if (!trail || !trail.steps) return null;
    assigneeNames = assigneeNames || {};
    var rejected = (trail.steps || []).filter(function (s) {
      return String(s.decision || '').toUpperCase() === 'REJECTED';
    });
    if (!rejected.length) return null;
    var step = rejected[rejected.length - 1];
    return {
      comment: step.comment || '无说明',
      who: assigneeNames[step.assigneeId] || '审批人',
      stepNo: step.stepNo,
      at: step.decidedAt,
    };
  }

  function renderClosedBanner(d) {
    if (d.status !== 'voided') return '';
    return (
      '<div class="xf-reject-banner" style="border-color:var(--border-soft);background:var(--bg-soft)">' +
      '<div class="xf-reject-title" style="color:var(--text-2)"><i class="ti ti-ban"></i>提案已作废</div>' +
      '<div class="xf-reject-comment" style="background:#fff;border-left-color:var(--border-strong);color:var(--text-3)">' +
      '该提案已关闭，不可重新填写或再次提交。' +
      '</div></div>'
    );
  }

  function renderRejectBanner(d, extras) {
    if (d.status !== 'rejected') return '';
    extras = extras || {};
    var info = lastRejectStep(extras.trail, extras.assigneeNames);
    var meta = info
      ? '第' + info.stepNo + '步 · ' + info.who + (info.at ? ' · ' + String(info.at).slice(0, 16).replace('T', ' ') : '')
      : '审批未通过，请修改后重新提交';
    var comment = info ? info.comment : '请查看流程追踪了解详情';
    return (
      '<div class="xf-reject-banner">' +
      '<div class="xf-reject-title"><i class="ti ti-alert-circle"></i>审批已驳回</div>' +
      '<div class="xf-reject-meta">' +
      esc(meta) +
      '</div>' +
      '<div class="xf-reject-comment">' +
      esc(comment) +
      '</div></div>'
    );
  }

  function renderPendingHint(d, extras) {
    extras = extras || {};
    if (d.status !== 'pending' && d.status !== 'pending_initiate') return '';
    if (extras.myTodo) return '';
    var who = currentApproverLabel(extras.trail, extras.assigneeNames, extras.stages);
    if (!who) who = '审批人';
    return (
      '<div class="xf-det-card xf-det-wait-card">' +
      '<div class="xf-det-card-h"><i class="ti ti-hourglass"></i>审批进行中</div>' +
      '<div class="xf-det-wait-body">当前节点：<b>' +
      esc(who) +
      '</b>。您可在「流程追踪」查看完整进度。</div></div>'
    );
  }

  function renderPeopleCard(d, extras) {
    extras = extras || {};
    var fv = d.formValues || {};
    var rows = [];
    if (d.createdBy) rows.push(['创建人', d.createdBy]);
    rows.push(['第一责任人', formatUserDisplay(fv.owner1) || d.owner1 || d.initiator || '—']);
    if (owner2Line(fv, d)) rows.push(['第二责任人', owner2Line(fv, d)]);
    if (formatUserDisplay(fv.respNational)) rows.push(['全国负责人', formatUserDisplay(fv.respNational)]);
    if (formatUserDisplay(fv.respOps)) rows.push(['运营负责人', formatUserDisplay(fv.respOps)]);
    if (formatUserDisplay(fv.respProvince)) rows.push(['省区负责人', formatUserDisplay(fv.respProvince)]);
    if (formatUserDisplay(fv.respTech)) rows.push(['技术负责人', formatUserDisplay(fv.respTech)]);
    if (d.techRoute) rows.push(['技术路由', d.techRoute]);
    var cur = currentApproverLabel(extras.trail, extras.assigneeNames, extras.stages);
    if (cur) rows.push(['当前审批节点', cur]);
    if (!rows.length) return '';
    return (
      '<div class="xf-det-card xf-det-people">' +
      '<div class="xf-det-card-h"><i class="ti ti-users"></i>相关责任人</div>' +
      rows
        .map(function (r) {
          return (
            '<div class="xf-det-people-row"><span class="xf-det-k">' +
            esc(r[0]) +
            '</span><span class="xf-det-v">' +
            esc(r[1]) +
            '</span></div>'
          );
        })
        .join('') +
      '</div>'
    );
  }

  function owner2Line(fv, d) {
    var name = formatUserDisplay(fv.owner2) || formatUserDisplay(d.owner2) || '';
    var level = fv.owner2Level || d.owner2Level || '';
    if (!name) return level ? String(level).toUpperCase() + '级' : '';
    return name + (level ? ' · ' + String(level).toUpperCase() + '级' : '');
  }

  function currentApproverLabel(trail, assigneeNames, stages) {
    if (!trail) return '';
    assigneeNames = assigneeNames || {};
    stages = stages || [];
    var stepNo = trail.currentStep || 1;
    var step = (trail.steps || []).find(function (s) {
      return Number(s.stepNo) === Number(stepNo);
    });
    if (step && step.assigneeId && assigneeNames[step.assigneeId]) {
      var stage = stages[stepNo - 1];
      var stageName = stage && stage.stageName ? stage.stageName : '第' + stepNo + '步';
      return stageName + ' · ' + assigneeNames[step.assigneeId];
    }
    if (step && step.decision) return '第' + stepNo + '步 · ' + step.decision;
    return '';
  }

  function renderApprovalPanel(todo, sticky) {
    if (!todo || !todo.id) return '';
    var cls = sticky ? ' xf-det-approve-sticky' : '';
    return (
      '<div class="xf-det-card xf-det-approve-card' +
      cls +
      '" data-xf-approve="1">' +
      '<div class="xf-det-card-h"><i class="ti ti-gavel"></i>待您审批</div>' +
      '<div class="xf-det-approve-hint">请查看填报内容与流程进度，填写意见后确认。</div>' +
      '<textarea id="xf-approve-comment" class="xf-approve-comment" placeholder="请填写审批意见（必填）" rows="2"></textarea>' +
      '<div class="xf-det-approve-actions">' +
      '<button type="button" class="xf-apv-btn reject" id="xf-reject-btn"><i class="ti ti-x"></i>驳回</button>' +
      '<button type="button" class="xf-apv-btn approve" id="xf-approve-btn"><i class="ti ti-check"></i>通过</button>' +
      '</div></div>'
    );
  }

  function kv(label, val) {
    if (val == null || val === '') return '';
    return (
      '<div class="xf-det-kv"><span class="xf-det-k">' +
      esc(label) +
      '</span><span class="xf-det-v">' +
      esc(String(val)) +
      '</span></div>'
    );
  }

  function renderFormSections(sections) {
    if (!sections || !sections.length) {
      return '<div class="xf-det-card"><div class="hint">暂无填报内容</div></div>';
    }
    return sections
      .map(function (sec, si) {
        var items = sec.items || [];
        var visible = items.slice(0, PREVIEW_LIMIT);
        var hidden = items.slice(PREVIEW_LIMIT);
        var html =
          '<div class="xf-det-card xf-det-section" data-sec="' +
          si +
          '">' +
          '<div class="xf-det-card-h">' +
          esc(sec.title) +
          ' · ' +
          items.length +
          ' 项</div>';
        visible.forEach(function (it, ii) {
          html += kvItem(it, si + '-' + ii);
        });
        if (hidden.length) {
          html += '<div class="xf-det-more hidden" data-more="' + si + '" data-hidden="' + hidden.length + '">';
          hidden.forEach(function (it, ii) {
            html += kvItem(it, si + '-h-' + ii);
          });
          html += '</div>';
          html +=
            '<button type="button" class="xf-det-expand" data-expand="' +
            si +
            '">展开剩余 ' +
            hidden.length +
            ' 项 <i class="ti ti-chevron-down"></i></button>';
        }
        return html + '</div>';
      })
      .join('');
  }

  function renderTrackTimeline(trail, stages, assigneeNames, detail) {
    stages = stages || [];
    assigneeNames = assigneeNames || {};
    detail = detail || {};
    var steps = (trail && trail.steps) || [];
    var curStep = trail && trail.currentStep ? Number(trail.currentStep) : 1;

    function assigneeLabel(trailStep, fallback) {
      fallback = fallback || '审批节点';
      if (trailStep && trailStep.assigneeId && assigneeNames[trailStep.assigneeId]) {
        return assigneeNames[trailStep.assigneeId] + ' · ' + fallback;
      }
      return fallback;
    }

    function stageLabel(stepNo, stepType) {
      var st = stages[stepNo - 1];
      if (st && st.stageName) return st.stageName;
      if (stepType === 'DIRECT_SUP') return '部门主管';
      if (stepType === 'FINANCE') return '财务总监';
      if (stepType === 'ROLE') return '技术审批';
      return stepType || '审批节点';
    }

    function fmtTime(v) {
      if (!v) return '';
      try {
        var d = new Date(v);
        if (isNaN(d.getTime())) return String(v);
        var p = function (n) {
          return String(n).padStart(2, '0');
        };
        return (
          d.getFullYear() +
          '-' +
          p(d.getMonth() + 1) +
          '-' +
          p(d.getDate()) +
          ' ' +
          p(d.getHours()) +
          ':' +
          p(d.getMinutes()) +
          ':' +
          p(d.getSeconds())
        );
      } catch (e) {
        return String(v);
      }
    }

    var html =
      '<div class="xf-det-card xf-det-track">' +
      '<div class="xf-det-card-h"><i class="ti ti-route"></i>流程追踪</div>' +
      '<div class="history-stack xf-det-history">';
    html +=
      '<div class="history-step done"><div class="hs-dot"><i class="ti ti-flag"></i></div><div class="hs-bd">' +
      '<div class="hs-h"><div class="who">' +
      esc(detail.createdBy || detail.owner1 || '发起人') +
      ' <span class="role">提交人</span></div><div class="tm">' +
      esc(fmtTime((trail && trail.createdAt) || detail.createdAt)) +
      '</div></div>' +
      '<div class="hs-cmt">提交提案 · ' +
      esc(detail.code || '') +
      '</div></div></div>';

    steps.forEach(function (trailStep) {
      var stepNo = Number(trailStep.stepNo) || 0;
      var label = stageLabel(stepNo, trailStep.stepType);
      var who = assigneeLabel(trailStep, label);
      var cls = 'todo';
      var icon = String(stepNo);
      var cmt = '待处理';
      if (trailStep.decision === 'APPROVED') {
        cls = 'done';
        icon = '<i class="ti ti-check"></i>';
        cmt = trailStep.comment || '已通过';
      } else if (trailStep.decision === 'REJECTED') {
        cls = 'rejected';
        icon = '<i class="ti ti-x"></i>';
        cmt = trailStep.comment || '已驳回';
      } else if (stepNo === curStep && detail.status === 'pending') {
        cls = 'cur';
        icon = '<i class="ti ti-clock"></i>';
        cmt = '审批进行中';
      }
      var tm = trailStep.decidedAt ? fmtTime(trailStep.decidedAt) : (cls === 'cur' ? '当前处理' : '待处理');
      html +=
        '<div class="history-step ' +
        cls +
        '"><div class="hs-dot">' +
        icon +
        '</div><div class="hs-bd"><div class="hs-h"><div class="who">' +
        esc(who) +
        '</div><div class="tm">' +
        esc(tm) +
        '</div></div><div class="hs-cmt">' +
        esc(cmt) +
        '</div></div></div>';
    });

    if (detail.status === 'approved') {
      html +=
        '<div class="history-step done"><div class="hs-dot"><i class="ti ti-circle-check"></i></div><div class="hs-bd">' +
        '<div class="hs-h"><div class="who">审批通过</div><div class="tm">' +
        esc(fmtTime(trail && trail.finishedAt)) +
        '</div></div><div class="hs-cmt">全部节点已完成</div></div></div>';
    }
    html += '</div></div>';
    return html;
  }

  function renderMainPanels(d, cfg, stages, extras) {
    extras = extras || {};
    var sections = buildSectionsByDetailConfig(extras.fields, d.formValues || {}, cfg, d);
    if (!sections.length) sections = buildFieldSections(extras.fields, d.formValues || {}, d);
    var tabs = [{ key: 'content', label: '填报内容' }];
    if (cfg.showApprovalFlow !== false) tabs.push({ key: 'track', label: '流程追踪' });
    var nav = tabs
      .map(function (t, i) {
        return (
          '<button type="button" class="xf-det-tab' +
          (i === 0 ? ' on' : '') +
          '" data-tab="' +
          esc(t.key) +
          '">' +
          esc(t.label) +
          '</button>'
        );
      })
      .join('');
    return (
      '<div class="xf-det-card xf-det-tabs-wrap">' +
      '<div class="xf-det-tabs">' +
      nav +
      '</div>' +
      '<div class="xf-det-tab-body">' +
      '<div class="xf-det-tab-pane" data-tab="content">' +
      renderFormSections(sections) +
      '</div>' +
      '<div class="xf-det-tab-pane hidden" data-tab="track">' +
      renderTrackTimeline(extras.trail, stages, extras.assigneeNames, d) +
      '</div></div></div>'
    );
  }

  function renderPushContext(d) {
    if (!d.draftedBy && !d.pushMessage) return '';
    var by = d.draftedBy || {};
    return (
      '<div class="xf-det-card xf-det-push">' +
      '<div class="xf-det-card-h"><i class="ti ti-send"></i>运营推送上下文</div>' +
      '<div class="xf-det-push-body">' +
      '<div class="xf-det-push-row"><span>推送人</span><b>' +
      esc(by.name || '—') +
      '</b></div>' +
      '<div class="xf-det-push-row"><span>部门</span><b>' +
      esc(by.dept || '—') +
      '</b></div>' +
      (by.at ? '<div class="xf-det-push-row"><span>时间</span><b>' + esc(by.at) + '</b></div>' : '') +
      (d.pushMessage ? '<div class="xf-det-push-msg">' + esc(d.pushMessage) + '</div>' : '') +
      '</div></div>'
    );
  }

  function renderStages(stages) {
    if (window.XFlowDynamic && window.XFlowDynamic.renderStageRows) {
      return (
        '<div class="xf-det-card" style="margin-top:10px"><div class="xf-det-card-h"><i class="ti ti-git-branch"></i>审批流程配置</div>' +
        window.XFlowDynamic.renderStageRows(stages, window.XFlowDynamic.getCurrentLayout()) +
        '</div>'
      );
    }
    return '';
  }

  function renderCcCard(ccList) {
    ccList = ccList || [];
    if (!ccList.length) return '';
    var rows = ccList
      .map(function (c) {
        var reasons = (c.reasons || []).join(' · ');
        return (
          '<div class="xf-det-cc-row">' +
          '<div class="xf-det-cc-name">' +
          esc(c.name || '—') +
          '</div>' +
          '<div class="xf-det-cc-meta">' +
          esc(c.role || '') +
          (c.dept ? ' · ' + esc(c.dept) : '') +
          '</div>' +
          (reasons ? '<div class="xf-det-cc-reason">' + esc(reasons) + '</div>' : '') +
          '</div>'
        );
      })
      .join('');
    return (
      '<div class="xf-det-card"><div class="xf-det-card-h"><i class="ti ti-bell"></i>知会 / 抄送 · ' +
      ccList.length +
      ' 人</div>' +
      rows +
      '</div>'
    );
  }

  function renderActions(d, cfg, extras) {
    extras = extras || {};
    var st = d.status;
    var html = '<div class="xf-det-actions">';
    if (st === 'draft' || st === 'pending_initiate') {
      html +=
        '<button type="button" class="act-btn danger" id="xf-delete-btn"><i class="ti ti-trash"></i>删除草稿</button>';
    }
    if (st === 'draft') {
      html +=
        '<button type="button" class="act-btn" id="xf-push-btn"><i class="ti ti-send"></i>推送给业务负责人</button>';
    }
    if (st === 'pending_initiate') {
      html +=
        '<button type="button" class="act-btn primary" id="xf-initiate-btn"><i class="ti ti-check"></i>确认发起</button>';
    }
    if (st === 'rejected' && extras.canReedit) {
      html +=
        '<button type="button" class="act-btn primary tappable" id="xf-detail-reedit-btn"><i class="ti ti-edit"></i>重新填写并提交</button>';
      html +=
        '<button type="button" class="act-btn danger tappable" id="xf-detail-void-btn"><i class="ti ti-trash"></i>作废</button>';
    }
    html += '</div>';
    return html;
  }

  function renderCcRulesShell() {
    if (window.XFlowDynamic && window.XFlowDynamic.renderCcRulesCardHtml) {
      return window.XFlowDynamic.renderCcRulesCardHtml({
        cardId: 'xf-detail-cc-rules-card',
        bodyId: 'xf-detail-cc-rules-body',
        panelId: 'xf-detail-cc-rules-panel',
        cardClass: 'xf-det-card xf-cc-rules-card',
      });
    }
    return '';
  }

  function renderDetail(d, cfg, stages, extras) {
    cfg = cfg || {};
    stages = stages || cfg.stages || [];
    extras = extras || {};
    return (
      renderHero(d) +
      renderClosedBanner(d) +
      renderRejectBanner(d, extras) +
      renderPeopleCard(d, extras) +
      renderPendingHint(d, extras) +
      (cfg.showPushContext !== false ? renderPushContext(d) : '') +
      renderMainPanels(d, cfg, stages, extras) +
      (cfg.showCcCard !== false ? renderCcCard(d.ccList) : '') +
      (extras.myTodo ? renderApprovalPanel(extras.myTodo, true) : '') +
      renderActions(d, cfg, extras)
    );
  }

  function bindTabs(root) {
    if (!root) return;
    root.querySelectorAll('.xf-det-tab').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var tab = btn.getAttribute('data-tab');
        root.querySelectorAll('.xf-det-tab').forEach(function (b) {
          b.classList.toggle('on', b.getAttribute('data-tab') === tab);
        });
        root.querySelectorAll('.xf-det-tab-pane').forEach(function (p) {
          p.classList.toggle('hidden', p.getAttribute('data-tab') !== tab);
        });
      });
    });
  }

  function bindKvExpand(root) {
    if (!root) return;
    root.querySelectorAll('.xf-det-kv-expand .xf-det-kv-head').forEach(function (btn) {
      if (btn._kvBound) return;
      btn._kvBound = true;
      btn.addEventListener('click', function () {
        var wrap = btn.closest('.xf-det-kv-expand');
        if (!wrap) return;
        var body = wrap.querySelector('.xf-det-kv-body');
        var sum = wrap.querySelector('.xf-det-v-sum');
        if (!body) return;
        var collapsed = body.classList.toggle('hidden');
        wrap.classList.toggle('on', !collapsed);
        if (!collapsed) loadDetailThumbs(wrap);
      });
    });
  }

  function getDetailFileItem(root, fieldKey, idx) {
    var detail = root._xfDetail || {};
    var fv = detail.formValues || {};
    var items = normalizeUploadItems(fv[fieldKey]);
    return items[Number(idx)] || null;
  }

  async function loadDetailThumbs(scope) {
    if (!scope) return;
    scope.querySelectorAll('[data-thumb-key]').forEach(async function (el) {
      if (el._thumbLoaded) return;
      var fieldKey = el.getAttribute('data-thumb-key');
      var idx = el.getAttribute('data-file-idx');
      var item = getDetailFileItem(scope.closest('#xf-detail-panel') || scope, fieldKey, idx);
      if (!item) return;
      el._thumbLoaded = true;
      try {
        var url = await resolveMediaUrl(item);
        if (url) {
          var img = document.createElement('img');
          img.src = url;
          img.alt = '';
          img.loading = 'lazy';
          el.innerHTML = '';
          el.appendChild(img);
        }
      } catch (e) {
        /* keep icon */
      }
    });
  }

  function showImageLightbox(url, name) {
    var old = document.querySelector('.xf-lightbox');
    if (old) old.remove();
    var overlay = document.createElement('div');
    overlay.className = 'xf-lightbox';
    overlay.innerHTML =
      '<div class="xf-lightbox-backdrop"></div>' +
      '<div class="xf-lightbox-body">' +
      '<button type="button" class="xf-lightbox-close" aria-label="关闭"><i class="ti ti-x"></i></button>' +
      '<img alt="" />' +
      '<div class="xf-lightbox-cap"></div></div>';
    var img = overlay.querySelector('img');
    if (img) {
      img.src = url;
      img.alt = name || '';
    }
    var cap = overlay.querySelector('.xf-lightbox-cap');
    if (cap) cap.textContent = name || '';
    document.body.appendChild(overlay);
    overlay.querySelector('.xf-lightbox-close').addEventListener('click', function () {
      overlay.remove();
    });
    overlay.querySelector('.xf-lightbox-backdrop').addEventListener('click', function () {
      overlay.remove();
    });
  }

  async function downloadDetailFile(item) {
    if (!item) return;
    var direct = resolvePublicFileUrl(item);
    if (direct) {
      var a = document.createElement('a');
      a.href = direct;
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
      if (item.fileName) a.download = item.fileName;
      document.body.appendChild(a);
      a.click();
      a.remove();
      return;
    }
    try {
      var url = await resolveMediaUrl(item);
      if (url) {
        var link = document.createElement('a');
        link.href = url;
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        if (item.fileName) link.download = item.fileName;
        document.body.appendChild(link);
        link.click();
        link.remove();
        return;
      }
    } catch (e) {
      console.warn('downloadDetailFile', e);
    }
    if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('无法获取下载地址，请确认 MinIO 已启动', true);
  }

  function bindFileActions(root) {
    if (!root) return;
    var openPreview = async function (btn) {
      var item = getDetailFileItem(root, btn.getAttribute('data-file-key'), btn.getAttribute('data-file-idx'));
      if (!item) return;
      var url = await resolveMediaUrl(item);
      if (url) showImageLightbox(url, item.fileName);
      else if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('无法预览图片', true);
    };
    root.querySelectorAll('.xf-det-file-preview, .xf-det-file-view').forEach(function (btn) {
      if (btn._imgBound) return;
      btn._imgBound = true;
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        openPreview(btn);
      });
    });
    root.querySelectorAll('.xf-det-file-dl').forEach(function (btn) {
      if (btn._dlBound) return;
      btn._dlBound = true;
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        var item = getDetailFileItem(root, btn.getAttribute('data-file-key'), btn.getAttribute('data-file-idx'));
        downloadDetailFile(item);
      });
    });
  }

  function bindExpand(root) {
    if (!root) return;
    root.querySelectorAll('.xf-det-expand').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var si = btn.getAttribute('data-expand');
        var more = root.querySelector('.xf-det-more[data-more="' + si + '"]');
        if (!more) return;
        var hidden = Number(more.getAttribute('data-hidden') || 0);
        var isHidden = more.classList.toggle('hidden');
        btn.innerHTML = isHidden
          ? '展开剩余 ' + hidden + ' 项 <i class="ti ti-chevron-down"></i>'
          : '收起 <i class="ti ti-chevron-up"></i>';
      });
    });
  }

  function showDetailPanel(proposalId, detail, cfg, stages, hooks) {
    hooks = hooks || {};
    var panel = document.getElementById('xf-detail-panel');
    var formPanel = document.getElementById('xf-form-panel');
    if (!panel) return;
    document.querySelectorAll('#xf-void-btn').forEach(function (el) {
      el.remove();
    });
    var extras = {
      fields: hooks.fields || [],
      trail: hooks.trail || null,
      assigneeNames: hooks.assigneeNames || {},
      myTodo: hooks.myTodo || null,
      stages: stages || [],
      canReedit: !!hooks.canReedit,
    };
    panel.innerHTML = renderDetail(detail, cfg, stages, extras);
    panel._xfDetail = detail;
    panel.style.display = 'block';
    if (formPanel) formPanel.style.display = 'none';
    window.__xfActiveStages = stages || [];
    bindTabs(panel);
    bindExpand(panel);
    bindKvExpand(panel);
    bindFileActions(panel);
    if (window.XFlowDynamic && window.XFlowDynamic.bindStageHelps) {
      window.XFlowDynamic.bindStageHelps(panel);
    }
    var dsName = document.querySelector('.screen[data-screen="XF"] .ds-name');
    if (dsName) dsName.textContent = detail.title || '销售提案详情';
    var dsCrumb = document.querySelector('.screen[data-screen="XF"] .ds-crumb');
    if (dsCrumb) dsCrumb.textContent = '销售提案 · 详情 · ' + (detail.code || proposalId);

    var pushBtn = document.getElementById('xf-push-btn');
    if (pushBtn && hooks.onPush) {
      pushBtn.addEventListener('click', function () {
        hooks.onPush(proposalId, detail);
      });
    }
    var initBtn = document.getElementById('xf-initiate-btn');
    if (initBtn && hooks.onInitiate) {
      initBtn.addEventListener('click', function () {
        hooks.onInitiate(proposalId, detail);
      });
    }
    var delBtn = document.getElementById('xf-delete-btn');
    if (delBtn && hooks.onDelete) {
      delBtn.addEventListener('click', function () {
        hooks.onDelete(proposalId, detail);
      });
    }
    var reeditBtn = panel.querySelector('#xf-detail-reedit-btn');
    if (reeditBtn && hooks.onReedit) {
      reeditBtn.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        hooks.onReedit(proposalId, detail, extras);
      });
    }
    var voidBtn = panel.querySelector('#xf-detail-void-btn');
    if (voidBtn && hooks.onVoid) {
      voidBtn.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        hooks.onVoid(proposalId, detail, extras);
      });
    }
    var approveBtn = document.getElementById('xf-approve-btn');
    var rejectBtn = document.getElementById('xf-reject-btn');
    var bindApprove = function (btn, handler) {
      if (!btn || btn._xfBound || !handler) return;
      btn._xfBound = true;
      btn.addEventListener('click', handler);
    };
    var onApprove = function () {
      var commentEl = document.getElementById('xf-approve-comment');
      var comment = commentEl && commentEl.value ? commentEl.value.trim() : '';
      if (!comment) {
        if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('请填写审批意见', true);
        else alert('请填写审批意见');
        if (commentEl) commentEl.focus();
        return;
      }
      hooks.onApprove(extras.myTodo, comment);
    };
    var onReject = function () {
      var commentEl = document.getElementById('xf-approve-comment');
      var comment = commentEl && commentEl.value ? commentEl.value.trim() : '';
      if (!comment) {
        if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('请填写审批意见', true);
        else alert('请填写审批意见');
        if (commentEl) commentEl.focus();
        return;
      }
      hooks.onReject(extras.myTodo, comment);
    };
    panel.querySelectorAll('#xf-approve-btn').forEach(function (btn) {
      bindApprove(btn, hooks.onApprove ? onApprove : null);
    });
    panel.querySelectorAll('#xf-reject-btn').forEach(function (btn) {
      bindApprove(btn, hooks.onReject ? onReject : null);
    });
    if (extras.myTodo) {
      setTimeout(function () {
        var card = panel.querySelector('[data-xf-approve="1"]');
        if (card) card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      }, 120);
    }
  }

  function hideDetailPanel() {
    var panel = document.getElementById('xf-detail-panel');
    var formPanel = document.getElementById('xf-form-panel');
    if (panel) {
      panel.innerHTML = '';
      panel.style.display = 'none';
    }
    if (formPanel) formPanel.style.display = 'block';
  }

  global.XFlowDetail = {
    renderDetail: renderDetail,
    showDetailPanel: showDetailPanel,
    hideDetailPanel: hideDetailPanel,
    lastRejectStep: lastRejectStep,
    bindTabs: bindTabs,
    buildFieldSections: buildFieldSections,
    formatUserDisplay: formatUserDisplay,
  };
})(typeof window !== 'undefined' ? window : global);
