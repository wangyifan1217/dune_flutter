(function () {
  'use strict';

  var SALES_KEY = 'sales-proposal';

  function host() {
    return localStorage.getItem('dunes_api_host') || window.location.hostname || 'localhost';
  }

  function apiBases() {
    var list = [];
    var flow = localStorage.getItem('dunes_flow_api_base');
    if (flow) list.push(flow.replace(/\/$/, ''));
    var stored = localStorage.getItem('dunes_api_base');
    if (stored) list.push(stored.replace(/\/$/, ''));
    list.push('http://' + host() + ':6087/api/v1');
    list.push('http://' + host() + ':6090/api/v1');
    var seen = {};
    return list.filter(function (b) {
      if (seen[b]) return false;
      seen[b] = true;
      return true;
    });
  }

  let pendingKey = null;
  let currentDetail = null;
  let formValues = {};
  let currentLayout = {};
  let currentProposalId = null;
  let detailConfig = null;
  let pushWhitelistCache = null;
  let b3TemplatesLoading = false;
  let currentStages = [];
  let profileCache = null;

  function notify(msg, isErr) {
    var text = msg == null ? '' : String(msg);
    if (window.DunesAppUI && DunesAppUI.toast) {
      DunesAppUI.toast(text, isErr);
      return;
    }
    if (window.DunesAPI && DunesAPI.toast) {
      DunesAPI.toast(text, isErr);
      return;
    }
    var phone =
      document.querySelector('.screen[data-screen="XF"] .phone-screen') ||
      document.querySelector('.screen.active .phone-screen') ||
      document.querySelector('.phone-screen');
    if (phone) {
      var t = phone.querySelector('.dunes-app-toast');
      if (!t) {
        t = document.createElement('div');
        t.className = 'dunes-app-toast';
        phone.appendChild(t);
      }
      t.className = 'dunes-app-toast' + (isErr ? ' err' : '');
      t.textContent = text;
      t.classList.add('show');
      clearTimeout(t._tid);
      t._tid = setTimeout(function () {
        t.classList.remove('show');
      }, 2800);
      return;
    }
    if (isErr) alert(text);
  }

  function parseApiMessage(body) {
    if (body == null || body === '') return '请求失败';
    if (typeof body === 'string') {
      try {
        var parsed = JSON.parse(body);
        return parseApiMessage(parsed);
      } catch (e) {
        return body.length > 120 ? body.slice(0, 120) + '…' : body;
      }
    }
    if (typeof body === 'object') {
      if (body.message) return String(body.message);
      if (body.error) return String(body.error);
    }
    return '请求失败';
  }

  function translateSubmitError(raw) {
    var msg = String(raw || '提交失败');
    if (/invalid credentials|unauthorized|401/i.test(msg)) return '登录已失效，请重新登录';
    if (/network|fetch|failed to fetch|api unavailable/i.test(msg)) {
      return '网络异常，请确认已登录且后端服务已启动';
    }
    if (/timeout/i.test(msg)) return '请求超时，请稍后重试';
    if (/proposal name|title.*required/i.test(msg)) return '请填写提案名称';
    if (/missing required fields/i.test(msg)) {
      return msg.replace(/^missing required fields:\s*/i, '请填写：');
    }
    if (/assignee not configured|Zeebe|zeebe-full profile/i.test(msg)) {
      return '审批流程未就绪：请配置组织用户直属上级，或启动 Zeebe（zeebe-full profile）';
    }
    if (/[\u4e00-\u9fff]/.test(msg)) return msg;
    return '提交失败，请稍后重试';
  }

  function isNetworkError(err) {
    var msg = String((err && err.message) || err || '');
    return /network|fetch|failed to fetch|api unavailable|timeout/i.test(msg);
  }

  function translateDraftError(err) {
    var msg = String((err && err.message) || err || '草稿保存失败');
    if (isNetworkError(msg)) return { network: true, message: '网络不可用，草稿已暂存到本机' };
    var friendly = translateSubmitError(msg);
    if (friendly !== '提交失败，请稍后重试') return { network: false, message: friendly };
    return { network: false, message: msg.indexOf('草稿') >= 0 ? msg : '草稿保存失败：' + msg };
  }

  function pad2(n) {
    n = String(n);
    return n.length >= 2 ? n : '0' + n;
  }

  function normalizeDateValue(v) {
    if (v == null || v === '') return v;
    var s = String(v).trim().replace(/\s+/g, '').replace(/\//g, '-');
    var m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
    if (m) return m[1] + '-' + pad2(m[2]) + '-' + pad2(m[3]);
    return s;
  }

  function normalizeUserValue(v) {
    if (v == null || v === '') return v;
    if (typeof v === 'object') {
      var uid = v.userId != null ? v.userId : v.id;
      if (uid == null || uid === '') return v;
      var parsed = parseInt(String(uid), 10);
      return {
        userId: !isNaN(parsed) && parsed > 0 ? parsed : uid,
        name: v.name || v.displayName || '',
        dept: v.dept || v.departmentName || '',
        title: v.title || '',
      };
    }
    return String(v).trim();
  }

  function normalizeListFieldValue(val) {
    if (val == null || val === '') return [];
    if (Array.isArray(val)) return val.slice();
    if (typeof val === 'object') return [Object.assign({}, val)];
    return [];
  }

  function sanitizeFormBody(values, fields, opts) {
    opts = opts || {};
    var out = Object.assign({}, values);
    (fields || []).forEach(function (f) {
      if (f.type === 'dynamicList' || f.type === 'matrix' || f.type === 'structuredTable') {
        if (out[f.key] != null) out[f.key] = normalizeListFieldValue(out[f.key]);
      }
      if (f.type === 'date' || f.key === 'launchDate') {
        if (out[f.key] != null && out[f.key] !== '') out[f.key] = normalizeDateValue(out[f.key]);
      }
      if (f.type === 'user' || f.dataSource === 'org_user') {
        if (out[f.key] != null) out[f.key] = normalizeUserValue(out[f.key]);
      }
      if (f.type === 'upload' && Array.isArray(out[f.key])) {
        out[f.key] = out[f.key]
          .filter(function (it) {
            return it && (it.url || it.objectKey || it.fileName || it.name);
          })
          .map(function (it) {
            return {
              id: it.id,
              fileName: it.fileName || it.name,
              url: it.url,
              objectKey: it.objectKey,
              status: 'done',
            };
          });
      }
    });
    if (opts.proposalId) out.proposalId = opts.proposalId;
    return out;
  }

  async function searchOrgUsers(q) {
    q = String(q || '').trim();
    if (!q) return [];
    return unwrap(await api('/org/users?q=' + encodeURIComponent(q)));
  }

  function tip(msg) {
    if (window.DunesAppUI && DunesAppUI.tip) return DunesAppUI.tip(msg);
    if (window.DunesDialog && DunesDialog.alert) return DunesDialog.alert(msg);
    notify(msg);
    return Promise.resolve();
  }

  function profileHasSupervisor(p) {
    return !!(p && (p.directSupervisorName || p.reportToName || p.directSupervisorId));
  }

  async function getMyProfile() {
    if (profileCache && (profileCache.userId || profileHasSupervisor(profileCache))) return profileCache;
    profileCache = null;
    try {
      profileCache = unwrap(await api('/org/users/me'));
    } catch (e) {
      try {
        var uid = currentUserId();
        if (uid) profileCache = unwrap(await api('/org/users/' + uid));
      } catch (e2) {
        profileCache = null;
      }
    }
    return profileCache || {};
  }

  async function fetchUserBrief(id) {
    try {
      var u = unwrap(await api('/org/users/' + id));
      return {
        name: u.displayName || u.name || '用户 #' + id,
        dept: u.departmentName || u.dept || '',
        title: u.title || '',
      };
    } catch (e) {
      return { name: '用户 #' + id, dept: '', title: '' };
    }
  }

  async function resolveStageApprovers(stage) {
    var lines = [];
    if (!stage) return lines;
    if (stage.approverType === 'DIRECT_SUP') {
      var p1 = await getMyProfile();
      if (p1.directSupervisorName) {
        lines.push({ name: p1.directSupervisorName, dept: '', title: '' });
      } else if (p1.reportToName) {
        lines.push({ name: p1.reportToName, dept: '', title: '' });
      } else if (p1.directSupervisorId) {
        lines.push(await fetchUserBrief(p1.directSupervisorId));
      } else {
        lines.push({ name: '未配置直属上级', dept: '', title: '请在组织用户中设置直接主管' });
      }
    } else if (stage.approverType === 'DIVISION') {
      var p2 = await getMyProfile();
      if (p2.divisionSupervisorName) {
        lines.push({ name: p2.divisionSupervisorName, dept: '', title: '' });
      } else if (p2.divisionSupervisorId) {
        lines.push(await fetchUserBrief(p2.divisionSupervisorId));
      } else {
        lines.push({ name: '未配置事业部负责人', dept: '', title: '请在组织用户中设置分管主管' });
      }
    } else if (stage.approverType === 'ROLE') {
      if (stage.roleCode === 'TECH') {
        var tp = formValues.techPlatform || '';
        var techName =
          window.XFlowLinkage && window.XFlowLinkage.TECH_ROUTE
            ? window.XFlowLinkage.TECH_ROUTE[tp] || '待根据技术标签确定'
            : '待根据技术标签确定';
        lines.push({
          name: techName,
          dept: '',
          title: tp ? '技术标签：' + tp : '请先填写技术标签',
        });
      } else {
        try {
          var fas = unwrap(await api('/xflow/functional-approvers')) || [];
          var fa = fas.find(function (f) {
            return f.roleCode === stage.roleCode;
          });
          if (fa && fa.approverIds && fa.approverIds.length) {
            for (var i = 0; i < fa.approverIds.length; i++) {
              lines.push(await fetchUserBrief(fa.approverIds[i]));
            }
          } else {
            lines.push({ name: '角色 · ' + (stage.roleCode || ''), dept: '', title: '未配置职能审批人' });
          }
        } catch (e) {
          lines.push({ name: '角色 · ' + (stage.roleCode || ''), dept: '', title: '加载失败' });
        }
      }
    } else if (stage.approverType === 'SYSTEM') {
      lines.push({ name: '系统自动', dept: '', title: '归档留痕 · 无需人工审批' });
    } else if (stage.approverIds && stage.approverIds.length) {
      for (var j = 0; j < stage.approverIds.length; j++) {
        lines.push(await fetchUserBrief(stage.approverIds[j]));
      }
    } else {
      lines.push({ name: '指定审批人', dept: '', title: '未配置' });
    }
    return lines;
  }

  function formatApproverTip(stage, lines) {
    var title = stage.stageName || '审批阶段';
    var body = (lines || [])
      .map(function (l) {
        var row = l.name || '—';
        if (l.dept) row += '\n' + l.dept;
        if (l.title) row += '\n' + l.title;
        return row;
      })
      .join('\n\n');
    return body ? title + '\n\n' + body : title;
  }

  async function onStageHelpClick(idx) {
    var stages = window.__xfActiveStages || currentStages || [];
    var st = stages[idx];
    if (!st) return;
    var btn = document.querySelector('.xf-stage-help[data-stage-idx="' + idx + '"]');
    if (btn) btn.disabled = true;
    try {
      var lines = await resolveStageApprovers(st);
      await tip(formatApproverTip(st, lines));
    } catch (e) {
      notify('加载审批人失败', true);
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  function bindStageHelps(box) {
    if (!box) return;
    if (box._xfStageBound) return;
    box._xfStageBound = true;
    box.addEventListener('click', function (ev) {
      var btn = ev.target.closest('.xf-stage-help');
      if (!btn) return;
      ev.preventDefault();
      ev.stopPropagation();
      var idx = parseInt(btn.getAttribute('data-stage-idx'), 10);
      if (!isNaN(idx)) onStageHelpClick(idx);
    });
  }

  function stageMetaLabel(st) {
    if (st.approverType === 'SYSTEM') return '系统自动';
    if (st.approverType === 'ROLE') {
      if (st.roleCode === 'TECH') return '按技术标签';
      return '角色 · ' + (st.roleCode || '');
    }
    if (st.approverType === 'DIRECT_SUP') return '部门主管';
    if (st.approverType === 'DIVISION') return '事业部负责人';
    if (st.approverType === 'USER') return '指定人员';
    if ((st.approverIds || []).length) return st.approverIds.length + ' 人';
    return '指定审批人';
  }

  function renderExtraStageRow(st, num, system) {
    var meta = st.meta || (system ? '系统自动' : '');
    return (
      '<div class="xf-stage-row' +
      (system ? ' xf-stage-system' : '') +
      '">' +
      '<div class="xf-stage-no">' +
      num +
      '</div>' +
      '<div class="xf-stage-body">' +
      '<div class="xf-stage-head">' +
      '<div class="xf-stage-name">' +
      (st.stageName || '阶段') +
      '</div>' +
      '</div>' +
      (meta ? '<div class="xf-stage-meta">' + esc(meta) + '</div>' : '') +
      '</div></div>'
    );
  }

  function renderStageRows(stages, layout) {
    layout = layout || currentLayout || {};
    var flow = layout.approvalFlow || {};
    var prefix = flow.prefix || [];
    var suffix = flow.suffix || [];
    if (!stages || !stages.length) {
      if (!prefix.length && !suffix.length) return '<div class="hint">未配置审批阶段</div>';
      stages = [];
    }
    var parts = [];
    var n = 1;
    prefix.forEach(function (st) {
      parts.push(renderExtraStageRow(st, n, true));
      n++;
    });
    stages.forEach(function (st, i) {
      parts.push(
        '<div class="xf-stage-row">' +
          '<div class="xf-stage-no">' +
          n +
          '</div>' +
          '<div class="xf-stage-body">' +
          '<div class="xf-stage-head">' +
          '<div class="xf-stage-name">' +
          (st.stageName || '阶段') +
          '</div>' +
          (st.approverType !== 'SYSTEM'
            ? '<button type="button" class="xf-stage-help" data-stage-idx="' +
              i +
              '" aria-label="查看审批人"><i class="ti ti-help"></i></button>'
            : '') +
          '</div>' +
          '<div class="xf-stage-meta">' +
          (st.mode || 'SINGLE') +
          ' · ' +
          stageMetaLabel(st) +
          '</div></div></div>',
      );
      n++;
    });
    suffix.forEach(function (st) {
      parts.push(renderExtraStageRow(st, n, true));
      n++;
    });
    return parts.join('');
  }

  function currentUserId() {
    return parseInt(localStorage.getItem('dunes_user_id') || window.__dunesSelfUserId || '0', 10) || 0;
  }

  async function loadPushWhitelist() {
    if (pushWhitelistCache) return pushWhitelistCache;
    try {
      const cfg = unwrap(await api('/xflow/templates/' + encodeURIComponent(SALES_KEY) + '/detail-config'));
      pushWhitelistCache = (cfg && cfg.pushRules) || [];
    } catch (e) {
      pushWhitelistCache = [];
    }
    return pushWhitelistCache;
  }

  async function api(path, opts) {
    opts = opts || {};
    const token = localStorage.getItem('dunes_token') || '';
    var lastErr = null;
    for (var i = 0; i < apiBases().length; i++) {
      try {
        const r = await fetch(apiBases()[i] + path, {
          method: opts.method || 'GET',
          headers: Object.assign(
            { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
            opts.headers || {},
          ),
          body: opts.body,
        });
        if (r.status === 501 || r.status === 404) {
          lastErr = new Error(await r.text());
          continue;
        }
        const ct = r.headers.get('content-type') || '';
        const body = ct.includes('json') ? await r.json() : await r.text();
        if (!r.ok) throw new Error(parseApiMessage(body));
        if (body && typeof body === 'object' && body.success === false) {
          throw new Error(parseApiMessage(body));
        }
        return body;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr || new Error('API unavailable');
  }

  function unwrap(res) {
    if (res && typeof res === 'object' && res.success === false) {
      throw new Error(parseApiMessage(res));
    }
    return res && res.data !== undefined ? res.data : res;
  }

  var submittingForm = false;

  function bindSubmitButton() {
    var btn = document.getElementById('xf-submit-btn');
    if (!btn) return;
    btn.onclick = function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      submitCurrentForm();
    };
    syncDeleteDraftButton();
    syncVoidRejectedButton();
  }

  function isProposalClosedStatus(st) {
    st = String(st || '').toLowerCase();
    return st === 'voided' || st === 'superseded';
  }

  function resetProposalEditorState() {
    window.__xfRejectedResubmit = false;
    window.__xfRejectInfo = null;
    syncVoidRejectedButton();
    document
      .querySelectorAll('#xf-form-panel .xf-rejected-banner, #xf-form-panel .xf-delegate-banner, #xf-form-panel .xf-draft-banner')
      .forEach(function (el) {
        el.remove();
      });
    var submitBtn = document.getElementById('xf-submit-btn');
    if (submitBtn) {
      submitBtn.innerHTML = '<i class="ti ti-send"></i>提交审批';
      submitBtn.disabled = false;
    }
    var detailPanel = document.getElementById('xf-detail-panel');
    if (detailPanel) {
      detailPanel.innerHTML = '';
      detailPanel.style.display = 'none';
    }
    var formPanel = document.getElementById('xf-form-panel');
    if (formPanel) formPanel.style.display = 'block';
  }

  async function voidRejectedProposal(proposalId) {
    if (!proposalId) return;
    var ok = await confirmAction('确定作废该提案？作废后将不再提示重新填写。');
    if (!ok) return;
    try {
      unwrap(
        await api('/xflow/proposals/' + proposalId + '/void', {
          method: 'POST',
          body: JSON.stringify({}),
        }),
      );
      resetProposalEditorState();
      try {
        localStorage.setItem('dunes_rejection_seen_PROPOSAL_' + proposalId, String(Date.now()));
      } catch (eSeen) {}
      notify('提案已作废');
      if (window.WorkbenchLive) {
        if (window.WorkbenchLive.markRejectionSeenByBusinessId) {
          window.WorkbenchLive.markRejectionSeenByBusinessId(proposalId);
        }
        if (window.WorkbenchLive.loadB14Initiated) await window.WorkbenchLive.loadB14Initiated();
        if (window.WorkbenchLive.refreshMyBadgeFromServer) await window.WorkbenchLive.refreshMyBadgeFromServer();
      }
      if (typeof go === 'function') go('B14');
      else if (typeof back === 'function') back();
    } catch (e) {
      console.warn('voidRejectedProposal', e);
      notify(String((e && e.message) || e || '作废失败'), true);
    }
  }

  function syncVoidRejectedButton() {
    var bar = document.querySelector('#xf-form-panel .action-bar');
    if (!bar) return;
    var voidBtn = bar.querySelector('#xf-form-void-btn');
    if (!window.__xfRejectedResubmit || !currentProposalId) {
      if (voidBtn) voidBtn.remove();
      return;
    }
    if (!voidBtn) {
      voidBtn = document.createElement('button');
      voidBtn.type = 'button';
      voidBtn.className = 'act-btn danger tappable';
      voidBtn.id = 'xf-form-void-btn';
      voidBtn.innerHTML = '<i class="ti ti-trash"></i>作废';
      var submitBtn = document.getElementById('xf-submit-btn');
      if (submitBtn && submitBtn.parentNode) {
        submitBtn.parentNode.insertBefore(voidBtn, submitBtn.nextSibling);
      } else {
        bar.appendChild(voidBtn);
      }
    }
    voidBtn.onclick = function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      voidRejectedProposal(currentProposalId);
    };
  }

  async function confirmAction(message) {
    if (window.DunesAppUI && DunesAppUI.confirm) return DunesAppUI.confirm(message);
    if (window.DunesDialog && DunesDialog.confirm) return DunesDialog.confirm(message);
    if (window.dunesConfirm) return window.dunesConfirm(message);
    return confirm(message);
  }

  function syncDeleteDraftButton() {
    var bar = document.querySelector('#xf-form-panel .action-bar');
    if (!bar) return;
    var del = document.getElementById('xf-delete-draft-btn');
    if (!currentProposalId) {
      if (del) del.remove();
      return;
    }
    if (!del) {
      del = document.createElement('button');
      del.type = 'button';
      del.className = 'act-btn danger';
      del.id = 'xf-delete-draft-btn';
      del.innerHTML = '<i class="ti ti-trash"></i>删除草稿';
      bar.insertBefore(del, bar.firstChild);
    }
    del.onclick = function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      deleteProposalDraft(currentProposalId);
    };
  }

  async function refreshWorkbenchAfterDraftChange() {
    if (window.WorkbenchLive && window.WorkbenchLive.loadB14Initiated) {
      try {
        await window.WorkbenchLive.loadB14Initiated();
      } catch (e) {
        /* ignore */
      }
    }
    if (window.WorkbenchLive && window.WorkbenchLive.refreshMyBadgeFromServer) {
      window.WorkbenchLive.refreshMyBadgeFromServer().catch(function () {});
    }
  }

  async function deleteProposalDraft(proposalId, opts) {
    opts = opts || {};
    var pid = proposalId || currentProposalId;
    if (!pid) return false;
    var ok = await confirmAction('确认删除此草稿？删除后不可恢复。');
    if (!ok) return false;
    try {
      unwrap(
        await api('/xflow/proposals/' + pid, {
          method: 'DELETE',
        }),
      );
      notify('草稿已删除');
      if (String(currentProposalId) === String(pid)) {
        currentProposalId = null;
        if (window.XFlowLinkage && window.XFlowLinkage.saveDraft) {
          window.XFlowLinkage.saveDraft(SALES_KEY, {});
        }
        syncDeleteDraftButton();
      }
      await refreshWorkbenchAfterDraftChange();
      if (opts.onDeleted) opts.onDeleted(pid);
      if (opts.goBack !== false) {
        if (window.XFlowDetail && window.XFlowDetail.hideDetailPanel) window.XFlowDetail.hideDetailPanel();
        if (typeof back === 'function') back();
        else if (typeof go === 'function') go('B14');
      }
      return true;
    } catch (e) {
      console.warn('deleteProposalDraft', e);
      var msg = String((e && e.message) || e || '删除失败');
      if (/only creator/i.test(msg)) msg = '只有创建人可以删除';
      else if (/only draft/i.test(msg)) msg = '仅草稿状态可删除';
      notify(msg, true);
      return false;
    }
  }

  function scrollToFirstMissingField(miss) {
    if (!miss || !miss.length) return;
    var container = document.getElementById('xf-form-fields');
    if (!container) return;
    var labels = container.querySelectorAll('.xf-fld-label, .fld-lbl, label');
    for (var i = 0; i < labels.length; i++) {
      var txt = (labels[i].textContent || '').replace(/\*/g, '').trim();
      if (miss.some(function (m) { return txt.indexOf(m) >= 0 || m.indexOf(txt) >= 0; })) {
        var fld = labels[i].closest('.xf-fld, .fld, .xf-field-wrap') || labels[i].parentElement;
        if (fld && fld.scrollIntoView) fld.scrollIntoView({ behavior: 'smooth', block: 'center' });
        break;
      }
    }
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }

  function renderTemplateCard(t) {
    const div = document.createElement('div');
    div.className = 'init-card biz xflow-dynamic';
    div.dataset.xflowKey = t.templateKey;
    var tag = t.tagLabel || '新建';
    var desc = t.subtitle || t.description || '业务元数据 · 财务 · 方案叙事 · 提交审批';
    var apiLine = t.endpoint || 'POST /xflow/templates/sales-proposal/submit';
    if (t.submitRoute && apiLine.indexOf('PROPOSAL_3STEP') < 0) {
      apiLine = apiLine + ' · ' + t.submitRoute;
    } else if (!t.endpoint) {
      apiLine = apiLine + ' · PROPOSAL_3STEP';
    }
    div.innerHTML =
      '<div class="ig-tag">' +
      tag +
      '</div>' +
      '<div class="ig-ic"><i class="ti ti-clipboard-text"></i></div>' +
      '<div class="ig-t">' +
      (t.title || '销售提案') +
      '</div>' +
      '<div class="ig-d">' +
      desc +
      '</div>' +
      '<div class="ig-api">' +
      apiLine +
      '</div>';
    div.addEventListener('click', function (ev) {
      ev.stopPropagation();
      openSalesProposal();
    });
    return div;
  }

  function openSalesProposal() {
    pendingKey = SALES_KEY;
    window.pendingXFlowKey = SALES_KEY;
    currentProposalId = null;
    syncDeleteDraftButton();
    if (window.XFlowDetail && window.XFlowDetail.hideDetailPanel) {
      window.XFlowDetail.hideDetailPanel();
    }
    if (typeof go === 'function') go('XF');
    else if (window.XFlowDynamic && window.XFlowDynamic.renderCurrentForm) {
      window.XFlowDynamic.renderCurrentForm();
    }
  }

  function mapDetailToFormValues(detail) {
    var fin = detail.finance || {};
    function normList(v) {
      if (v == null || v === '') return [];
      if (Array.isArray(v)) return v;
      if (typeof v === 'object') return [v];
      return [];
    }
    var vals = {
      title: detail.title || '',
      proposalCode: detail.code || '',
      tag1: detail.tag1 ? [detail.tag1] : [],
      owner1Level: detail.taskLevel || detail.owner1Level || 'C',
      techPlatform: detail.techPlatform || '',
      launchChannel: fin.launchChannel || '',
      launchDate: fin.launchDate || detail.launchDate || '',
      txType: detail.txType || '',
      goodType: detail.goodType || '',
      proposalType: detail.proposalType || '',
      provinces: detail.coverage || fin.provinces || [],
      targetMonthlyScaleWan: fin.targetMonthlyScaleWan || '',
      targetMonthlyProfitWan: fin.targetMonthlyProfitWan || '',
      settlementCycles: normList(fin.settlementCycles),
      provinceDiscounts: normList(fin.provinceDiscounts),
      supplierPolicies: normList(fin.supplierPolicies),
      channelPolicies: normList(fin.channelPolicies),
      oilBundleRows: normList(fin.oilBundleRows),
      solutionDesc: detail.solutionText || (fin.solutionDesc && fin.solutionDesc.text) || '',
      respNational: (fin.responsibles && fin.responsibles.national) || '',
      respOps: (fin.responsibles && fin.responsibles.ops) || '',
      respProvince: (fin.responsibles && fin.responsibles.province) || '',
      respTech: (fin.responsibles && fin.responsibles.tech) || '',
      riskTech: fin.riskTech || '',
      riskBusiness: fin.riskBusiness || '',
      riskFinance: fin.riskFinance || '',
      planFiles: fin.planFiles || [],
      contractFiles: fin.contractFiles || [],
    };
    if (detail.owner1) vals.owner1 = { name: detail.owner1, displayName: detail.owner1 };
    return vals;
  }

  function clearFormBanners() {
    document.querySelectorAll('#xf-form-panel .xf-delegate-banner, #xf-form-panel .xf-draft-banner, #xf-form-panel .xf-rejected-banner').forEach(function (el) {
      el.remove();
    });
  }

  function showRejectedBanner(detail, rejectInfo) {
    var panel = document.getElementById('xf-form-panel');
    if (!panel) return;
    clearFormBanners();
    rejectInfo = rejectInfo || {};
    var banner = document.createElement('div');
    banner.className = 'xf-rejected-banner xf-delegate-banner';
    banner.innerHTML =
      '<div class="xf-delegate-title"><i class="ti ti-alert-circle"></i>审批已驳回 · 请修改后重新提交</div>' +
      '<div class="xf-delegate-body">' +
      (rejectInfo.who ? '<span>驳回人 <b>' + esc(rejectInfo.who) + '</b></span>' : '') +
      (rejectInfo.comment
        ? '<p>驳回意见：' + esc(rejectInfo.comment) + '</p>'
        : '<p>请根据审批意见修改提案内容，确认无误后再次提交。</p>') +
      '</div>';
    panel.insertBefore(banner, panel.firstChild);
    var dsCrumb = document.querySelector('.screen[data-screen="XF"] .ds-crumb');
    if (dsCrumb) dsCrumb.textContent = '销售提案 · 驳回修改' + (detail && detail.code ? ' · ' + detail.code : '');
  }

  function showDraftBanner(detail) {
    var panel = document.getElementById('xf-form-panel');
    if (!panel) return;
    clearFormBanners();
    var banner = document.createElement('div');
    banner.className = 'xf-draft-banner xf-delegate-banner';
    banner.innerHTML =
      '<div class="xf-delegate-title"><i class="ti ti-pencil"></i>草稿 · 继续填写</div>' +
      '<div class="xf-delegate-body"><p>已保存部分内容，可继续编辑后提交审批。</p></div>';
    panel.insertBefore(banner, panel.firstChild);
    var titleEl = document.getElementById('xf-form-title');
    if (titleEl) titleEl.textContent = (detail && detail.title) || '销售提案草稿';
    var dsName = document.querySelector('.screen[data-screen="XF"] .ds-name');
    if (dsName) dsName.textContent = (detail && detail.title) || '销售提案草稿';
    var dsCrumb = document.querySelector('.screen[data-screen="XF"] .ds-crumb');
    if (dsCrumb) dsCrumb.textContent = '销售提案 · 草稿' + (detail && detail.code ? ' · ' + detail.code : '');
  }

  function showDelegateBanner(detail) {
    var panel = document.getElementById('xf-form-panel');
    if (!panel) return;
    clearFormBanners();
    if (!detail || detail.status !== 'pending_initiate') return;
    var by = detail.draftedBy || {};
    var banner = document.createElement('div');
    banner.className = 'xf-delegate-banner';
    banner.innerHTML =
      '<div class="xf-delegate-title"><i class="ti ti-user-edit"></i>同事推送 · 代为填写</div>' +
      '<div class="xf-delegate-body">' +
      (by.name ? '<span>推送人 <b>' + esc(by.name) + '</b></span>' : '') +
      (detail.pushMessage ? '<p>' + esc(detail.pushMessage) + '</p>' : '<p>请核对并补充提案内容后确认发起。</p>') +
      '</div>';
    panel.insertBefore(banner, panel.firstChild);
  }

  function draftFormValuesFromDetail(detail) {
    if (detail && detail.formValues && typeof detail.formValues === 'object' && Object.keys(detail.formValues).length) {
      return detail.formValues;
    }
    return mapDetailToFormValues(detail);
  }

  function applyFormValuesToScreen(values) {
    Object.keys(formValues).forEach(function (k) {
      delete formValues[k];
    });
    Object.assign(formValues, values || {});
    var container = document.getElementById('xf-form-fields');
    var fields = (currentDetail && (currentDetail.fields || currentDetail.template?.fieldsJson)) || [];
    if (container && window.XFlowRender) {
      container.innerHTML = window.XFlowRender.renderForm(fields, formValues, currentLayout);
      window.XFlowRender.bindForm(container, fields, formValues, currentLayout, function () {}, apiWrapper);
    }
  }

  async function renderRejectedForm(proposalId, detail, rejectInfo) {
    currentProposalId = proposalId;
    window.__xfRejectedResubmit = true;
    window.__xfRejectInfo = rejectInfo || null;
    if (window.XFlowDetail && window.XFlowDetail.hideDetailPanel) {
      window.XFlowDetail.hideDetailPanel();
    }
    await renderCurrentForm({ skipDetailRedirect: true, skipLocalDraft: true });
    applyFormValuesToScreen(draftFormValuesFromDetail(detail));
    showRejectedBanner(detail, rejectInfo);
    bindSubmitButton();
    syncDeleteDraftButton();
    var submitBtn = document.getElementById('xf-submit-btn');
    if (submitBtn) {
      submitBtn.innerHTML = '<i class="ti ti-send"></i>重新提交审批';
      submitBtn.disabled = false;
    }
  }

  async function openRejectedProposalEdit(proposalId) {
    pendingKey = SALES_KEY;
    window.pendingXFlowKey = SALES_KEY;
    currentProposalId = proposalId;
    if (window.XFlowDetail && window.XFlowDetail.hideDetailPanel) {
      window.XFlowDetail.hideDetailPanel();
    }
    try {
      var detail = unwrap(await api('/xflow/proposals/' + proposalId + '/detail'));
      var trail = null;
      var rejectInfo = null;
      try {
        trail = unwrap(await api('/approvals/PROPOSAL/' + proposalId));
        var pack = await enrichTrailAssignees(trail);
        trail = pack.trail;
        rejectInfo = lastRejectFromTrail(pack.trail, pack.names);
      } catch (e2) {
        /* optional */
      }
      if (!isProposalSubmitter(detail, trail)) {
        notify('仅提交人可重新填写', true);
        window.__xfSkipFormRender = true;
        if (typeof go === 'function') go('XF');
        window.__xfSkipFormRender = false;
        await showProposalDetail(proposalId);
        return;
      }
      if (isProposalClosedStatus(detail.status)) {
        notify(String(detail.status || '').toLowerCase() === 'voided' ? '该提案已作废' : '该提案已重新提交，请在新提案中查看', true);
        resetProposalEditorState();
        window.__xfSkipFormRender = true;
        if (typeof go === 'function') go('XF');
        window.__xfSkipFormRender = false;
        await showProposalDetail(proposalId);
        return;
      }
      window.__xfSkipFormRender = true;
      if (typeof go === 'function') go('XF');
      window.__xfSkipFormRender = false;
      await renderRejectedForm(proposalId, detail, rejectInfo);
    } catch (e) {
      console.warn('openRejectedProposalEdit', e);
      notify('加载驳回提案失败', true);
    }
  }

  function lastRejectFromTrail(trail, assigneeNames) {
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
    };
  }

  async function renderDraftForm(proposalId, detail) {
    window.__xfRejectedResubmit = false;
    window.__xfRejectInfo = null;
    currentProposalId = proposalId;
    if (window.XFlowDetail && window.XFlowDetail.hideDetailPanel) {
      window.XFlowDetail.hideDetailPanel();
    }
    await renderCurrentForm({ skipDetailRedirect: true, skipLocalDraft: true });
    applyFormValuesToScreen(draftFormValuesFromDetail(detail));
    if (window.XFlowLinkage && window.XFlowLinkage.saveDraft) {
      window.XFlowLinkage.saveDraft(SALES_KEY, formValues);
    }
    showDraftBanner(detail);
    bindSubmitButton();
    syncDeleteDraftButton();
    var submitBtn = document.getElementById('xf-submit-btn');
    if (submitBtn) {
      submitBtn.innerHTML = '<i class="ti ti-send"></i>提交审批';
      submitBtn.disabled = false;
    }
  }

  async function renderDelegatedForm(proposalId, detail) {
    currentProposalId = proposalId;
    if (window.XFlowDetail && window.XFlowDetail.hideDetailPanel) {
      window.XFlowDetail.hideDetailPanel();
    }
    await renderCurrentForm({ skipDetailRedirect: true, skipLocalDraft: true });
    applyFormValuesToScreen(draftFormValuesFromDetail(detail));
    showDelegateBanner(detail);
    syncDeleteDraftButton();
    var submitBtn = document.getElementById('xf-submit-btn');
    if (submitBtn) {
      submitBtn.innerHTML = '<i class="ti ti-check"></i>保存并确认发起';
      submitBtn.onclick = async function () {
        try {
          await saveDraftToServer(SALES_KEY);
          await handleInitiateProposal(proposalId);
        } catch (e) {
          console.warn('delegate submit', e);
        }
      };
    }
    var dsCrumb = document.querySelector('.screen[data-screen="XF"] .ds-crumb');
    if (dsCrumb) dsCrumb.textContent = '销售提案 · 待确认发起';
  }

  async function openProposalDetail(proposalId, todoHint) {
    pendingKey = SALES_KEY;
    window.pendingXFlowKey = SALES_KEY;
    currentProposalId = proposalId;
    var resolvedTodo = todoHint && todoHint.id ? todoHint : null;
    try {
      const detail = unwrap(await api('/xflow/proposals/' + proposalId + '/detail'));
      var trailPack = { trail: null, names: {} };
      try {
        var trail = unwrap(await api('/approvals/PROPOSAL/' + proposalId));
        trailPack = await enrichTrailAssignees(trail);
      } catch (eTrail) {
        /* optional */
      }
      if (!resolvedTodo) {
        resolvedTodo = filterSelfApprovalTodo(
          await findMyOpenTodo('PROPOSAL', proposalId, detail, trailPack.trail),
          detail,
          trailPack.trail,
        );
      } else {
        resolvedTodo = filterSelfApprovalTodo(resolvedTodo, detail, trailPack.trail);
      }
      if (resolvedTodo) {
        window.__xfSkipFormRender = true;
        if (typeof go === 'function') go('XF');
        window.__xfSkipFormRender = false;
        await showProposalDetail(proposalId, resolvedTodo);
        return;
      }
      var trailRejected =
        trailPack.trail && String(trailPack.trail.status || '').toUpperCase() === 'REJECTED';
      if (detail && detail.status === 'draft') {
        window.__xfSkipFormRender = true;
        if (typeof go === 'function') go('XF');
        window.__xfSkipFormRender = false;
        await renderDraftForm(proposalId, detail);
        return;
      }
      if (detail && detail.status === 'pending_initiate') {
        window.__xfSkipFormRender = true;
        if (typeof go === 'function') go('XF');
        window.__xfSkipFormRender = false;
        await renderDelegatedForm(proposalId, detail);
        return;
      }
      if (detail && isProposalClosedStatus(detail.status)) {
        resetProposalEditorState();
        window.__xfSkipFormRender = true;
        if (typeof go === 'function') go('XF');
        window.__xfSkipFormRender = false;
        await showProposalDetail(proposalId, resolvedTodo);
        return;
      }
      if (detail && (detail.status === 'rejected' || trailRejected)) {
        if (isProposalSubmitter(detail, trailPack.trail)) {
          window.__xfSkipFormRender = true;
          if (typeof go === 'function') go('XF');
          window.__xfSkipFormRender = false;
          var rejectInfo = lastRejectFromTrail(trailPack.trail, trailPack.names);
          await renderRejectedForm(proposalId, detail, rejectInfo);
          return;
        }
        window.__xfSkipFormRender = true;
        if (typeof go === 'function') go('XF');
        window.__xfSkipFormRender = false;
        await showProposalDetail(proposalId, resolvedTodo);
        return;
      }
    } catch (e) {
      console.warn('openProposalDetail', e);
    }
    window.__xfSkipFormRender = true;
    if (typeof go === 'function') go('XF');
    window.__xfSkipFormRender = false;
    await showProposalDetail(proposalId);
  }

  function triggerTypeLabel(t) {
    t = String(t || '').toLowerCase();
    if (t === 'always') return '始终抄送';
    if (t === 'task_level') return '按任务等级';
    if (t === 'need_advance') return '涉及垫资';
    if (t === 'monthly_scale_gt') return '月规模超阈值';
    if (t === 'invoice_tax') return '税务成本';
    return t || '条件触发';
  }

  function renderCcRulesCardHtml(opts) {
    opts = opts || {};
    var cardId = opts.cardId || 'xf-cc-rules-card';
    var bodyId = opts.bodyId || 'xf-cc-rules-body';
    var panelId = opts.panelId || 'xf-cc-rules-panel';
    var cardClass = opts.cardClass || 'form-card xf-cc-rules-card';
    return (
      '<div class="' +
      cardClass +
      '" id="' +
      cardId +
      '">' +
      '<div class="fc-h xf-cc-rules-toggle" role="button" tabindex="0" style="cursor:pointer;user-select:none;display:flex;align-items:center;gap:6px;margin-bottom:0">' +
      '<span>抄送规则说明</span>' +
      '<span style="font-size:10px;color:var(--text-3);font-weight:400">提交后按规则自动知会相关人员</span>' +
      '<i class="ti ti-chevron-down xf-cc-rules-chevron" style="margin-left:auto;font-size:16px;color:var(--text-3);transition:transform .2s"></i>' +
      '</div>' +
      '<div id="' +
      bodyId +
      '" class="xf-cc-rules-body" hidden>' +
      '<div id="' +
      panelId +
      '" style="padding-top:10px">' +
      '<div class="xf-loading-hint">加载抄送规则…</div>' +
      '</div></div></div>'
    );
  }

  function bindCcRulesToggle(card) {
    if (!card) return;
    var toggle = card.querySelector('.xf-cc-rules-toggle');
    var body = card.querySelector('.xf-cc-rules-body');
    var chevron = card.querySelector('.xf-cc-rules-chevron');
    if (!toggle || !body) return;
    if (card._ccRulesWired) return;
    card._ccRulesWired = true;
    var setOpen = function (open) {
      body.hidden = !open;
      if (chevron) chevron.style.transform = open ? 'rotate(180deg)' : '';
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    };
    setOpen(false);
    toggle.addEventListener('click', function () {
      setOpen(body.hidden);
    });
  }

  async function loadCcRulesPanel(opts) {
    opts = opts || {};
    var cardId = opts.cardId || 'xf-cc-rules-card';
    var panelId = opts.panelId || 'xf-cc-rules-panel';
    var templateKey = opts.templateKey || SALES_KEY;
    var card = document.getElementById(cardId);
    var box = document.getElementById(panelId);
    if (!box) return;
    bindCcRulesToggle(card);
    try {
      var rules =
        unwrap(
          await api('/xflow/templates/' + encodeURIComponent(templateKey) + '/cc-rules'),
        ) || [];
      if (!rules.length) {
        box.innerHTML = '<div class="hint">暂无抄送规则配置</div>';
        if (card) card.style.display = 'none';
        return;
      }
      if (card) card.style.display = '';
      box.innerHTML = rules
        .map(function (r) {
          var who = r.title || r.userName || '—';
          var meta = [r.roleLabel, r.deptLabel].filter(Boolean).join(' · ');
          var reason = r.reasonTpl || triggerTypeLabel(r.triggerType);
          return (
            '<div class="xf-det-cc-row" style="padding:8px 0;border-bottom:1px solid var(--border-soft)">' +
            '<div class="xf-det-cc-name" style="font-weight:500">' +
            esc(who) +
            '</div>' +
            '<div class="xf-det-cc-meta" style="font-size:10px;color:var(--text-3)">' +
            esc(meta) +
            '</div>' +
            '<div class="xf-det-cc-reason" style="font-size:10px;color:var(--accent);margin-top:2px">' +
            esc(triggerTypeLabel(r.triggerType)) +
            ' · ' +
            esc(reason) +
            '</div></div>'
          );
        })
        .join('');
    } catch (e) {
      console.warn('loadCcRulesPanel', e);
      box.innerHTML = '<div class="hint">抄送规则加载失败</div>';
    }
  }

  async function loadB3Templates() {
    if (b3TemplatesLoading) return;
    b3TemplatesLoading = true;
    var bizGrid = document.querySelector('.init-pane.biz .init-grid');
    if (!bizGrid) {
      b3TemplatesLoading = false;
      return;
    }
    bizGrid.innerHTML = '';
    document.querySelectorAll('.init-pane.biz .init-card:not(.xflow-dynamic)').forEach(function (el) {
      el.style.display = 'none';
    });
    var bizTab = document.querySelector('.ic-tab.biz .ct');
    if (bizTab) bizTab.textContent = '1 类';
    try {
      const list = unwrap(await api('/xflow/templates?category=biz')) || [];
      var matches = list.filter(function (x) {
        return x.templateKey === SALES_KEY;
      });
      var t = matches[0];
      if (!t) {
        t = {
          templateKey: SALES_KEY,
          title: '销售提案',
          tagLabel: '新建',
          subtitle: '业务元数据 · 财务 · 四流 · 方案叙事 · 提交审批',
          endpoint: 'POST /xflow/templates/sales-proposal/submit',
          category: 'biz',
        };
      }
      bizGrid.appendChild(renderTemplateCard(t));
    } catch (e) {
      console.warn('loadB3Templates', e);
      bizGrid.appendChild(
        renderTemplateCard({
          templateKey: SALES_KEY,
          title: '销售提案',
          tagLabel: '新建',
          subtitle: '业务元数据 · 财务 · 四流 · 方案叙事 · 提交审批',
          endpoint: 'POST /xflow/templates/sales-proposal/submit',
        }),
      );
    } finally {
      b3TemplatesLoading = false;
    }
  }

  function renderStages(stages) {
    const box = document.getElementById('xf-stages-list');
    if (!box) return;
    currentStages = stages || [];
    window.__xfActiveStages = currentStages;
    box.innerHTML = renderStageRows(stages, currentLayout);
    bindStageHelps(box);
  }

  async function enrichTrailAssignees(trail) {
    if (!trail || !trail.steps || !trail.steps.length) return { trail: trail, names: {} };
    var ids = [];
    trail.steps.forEach(function (s) {
      if (s.assigneeId) ids.push(s.assigneeId);
    });
    if (trail.initiatorId) ids.push(trail.initiatorId);
    ids = ids.filter(function (v, i, a) {
      return a.indexOf(v) === i;
    });
    if (!ids.length) return { trail: trail, names: {} };
    try {
      var users = unwrap(await api('/org/users?ids=' + ids.join(','))) || [];
      var names = {};
      (Array.isArray(users) ? users : []).forEach(function (u) {
        var id = u.userId != null ? u.userId : u.id;
        if (id != null) names[id] = u.displayName || u.name || '用户#' + id;
      });
      return { trail: trail, names: names };
    } catch (e) {
      return { trail: trail, names: {} };
    }
  }

  function currentUserId() {
    var uid = window.__dunesSelfUserId;
    if (uid != null && Number(uid) > 0) return Number(uid);
    try {
      uid = parseInt(localStorage.getItem('dunes_user_id') || '0', 10);
      if (uid > 0) return uid;
    } catch (e) {}
    return 0;
  }

  function isSelfInitiatedProposal(detail, trail) {
    var uid = currentUserId();
    if (!uid || !detail) return false;
    // 仅拦截「发起人本人审批」，第一责任人与发起人可能不是同一人
    if (detail.createdById != null && Number(detail.createdById) === uid) return true;
    if (trail && trail.initiatorId != null && Number(trail.initiatorId) === uid) return true;
    return false;
  }

  function isProposalSubmitter(detail, trail) {
    return isSelfInitiatedProposal(detail, trail);
  }

  async function findMyOpenTodo(businessType, businessId, detail, trail) {
    try {
      var inbox = unwrap(await api('/workbench/inbox?kind=APPROVAL')) || [];
      if (!Array.isArray(inbox)) return null;
      var candidates = inbox.filter(function (t) {
        return (
          String(t.businessType || '').toUpperCase() === String(businessType || '').toUpperCase() &&
          String(t.businessId) === String(businessId) &&
          String(t.status || '').toUpperCase() === 'OPEN' &&
          String(t.kind || 'APPROVAL').toUpperCase() === 'APPROVAL'
        );
      });
      if (!candidates.length) return null;
      if (trail && Array.isArray(trail.steps)) {
        var cur = trail.steps.find(function (s) {
          return Number(s.stepNo) === Number(trail.currentStep || 0) && !s.decision;
        });
        if (cur && cur.id) {
          var byStep = candidates.find(function (t) {
            return String(t.sourceStepId || '') === String(cur.id);
          });
          if (byStep) return byStep;
        }
      }
      return candidates[0] || null;
    } catch (e) {
      return null;
    }
  }

  function filterSelfApprovalTodo(myTodo, detail, trail) {
    if (!myTodo) return null;
    if (isSelfInitiatedProposal(detail, trail)) return null;
    return myTodo;
  }

  async function completeApprovalTodo(todo, decision, comment) {
    if (!todo || !todo.id) return;
    var text = comment ? String(comment).trim() : '';
    if (!text) {
      notify('请填写审批意见', true);
      return;
    }
    try {
      unwrap(
        await api('/todos/' + todo.id + '/complete', {
          method: 'POST',
          body: JSON.stringify({
            decision: decision,
            comment: text,
          }),
        }),
      );
      notify(decision === 'APPROVED' ? '审批已通过' : '已驳回');
      if (window.WorkbenchLive) {
        if (window.WorkbenchLive.refreshMyBadgeFromServer) {
          await window.WorkbenchLive.refreshMyBadgeFromServer();
        }
        if (window.WorkbenchLive.loadB1ApprovalTodos) {
          await window.WorkbenchLive.loadB1ApprovalTodos();
        }
      }
      if (typeof back === 'function') back();
      else if (typeof go === 'function') go('B1');
    } catch (e) {
      console.warn('completeApprovalTodo', e);
      notify(String((e && e.message) || e || '审批操作失败'), true);
    }
  }

  async function showProposalDetail(proposalId, todoHint) {
    if (!window.XFlowDetail) return;
    try {
      const cfgRes = unwrap(await api('/xflow/templates/' + encodeURIComponent(SALES_KEY) + '/detail-config'));
      detailConfig = (cfgRes && cfgRes.detailConfig) || cfgRes || {};
      const tplRes = unwrap(await api('/xflow/templates/' + encodeURIComponent(SALES_KEY)));
      var fields = tplRes.fields || (tplRes.template && tplRes.template.fieldsJson) || [];
      if (window.XFlowRender && window.XFlowRender.enrichFieldsFromDicts) {
        fields = await window.XFlowRender.enrichFieldsFromDicts(fields, function (p) {
          return api(p).then(unwrap);
        });
      }
      const detail = unwrap(await api('/xflow/proposals/' + proposalId + '/detail'));
      if (detail && detail.status === 'draft') {
        await renderDraftForm(proposalId, detail);
        return;
      }
      if (detail && detail.status === 'pending_initiate') {
        await renderDelegatedForm(proposalId, detail);
        return;
      }
      const stages = (cfgRes && cfgRes.stages) || (tplRes && tplRes.stages) || [];
      var trailPack = { trail: null, names: {} };
      try {
        var trail = unwrap(await api('/approvals/PROPOSAL/' + proposalId));
        trailPack = await enrichTrailAssignees(trail);
      } catch (e) {
        console.warn('approval trail', e);
      }
      var inboxTodo =
        todoHint && todoHint.id
          ? todoHint
          : await findMyOpenTodo('PROPOSAL', proposalId, detail, trailPack.trail);
      var myTodo = filterSelfApprovalTodo(inboxTodo, detail, trailPack.trail);
      var hooks = detailPanelHooks();
      hooks.fields = fields;
      hooks.myTodo = myTodo;
      hooks.trail = trailPack.trail;
      hooks.assigneeNames = trailPack.names;
      hooks.onApprove = function (todo, comment) {
        completeApprovalTodo(todo, 'APPROVED', comment);
      };
      hooks.onReject = function (todo, comment) {
        completeApprovalTodo(todo, 'REJECTED', comment);
      };
      hooks.onReedit = function (pid, det, extras) {
        if (isProposalClosedStatus(det && det.status)) {
          notify('该提案已作废，不可重新填写', true);
          return;
        }
        if (!hooks.canReedit) {
          notify('仅提交人可重新填写', true);
          return;
        }
        var info = window.XFlowDetail && window.XFlowDetail.lastRejectStep
          ? window.XFlowDetail.lastRejectStep(extras.trail, extras.assigneeNames)
          : lastRejectFromTrail(extras.trail, extras.assigneeNames);
        renderRejectedForm(pid, det, info);
      };
      hooks.canReedit =
        isProposalSubmitter(detail, trailPack.trail) &&
        String(detail.status || '').toLowerCase() === 'rejected' &&
        !isProposalClosedStatus(detail.status);
      if (detail.formValues) {
        detail.formValues = Object.assign({}, detail.formValues);
        ['settlementCycles', 'provinceDiscounts', 'supplierPolicies', 'channelPolicies', 'oilBundleRows'].forEach(
          function (k) {
            if (detail.formValues[k] != null) detail.formValues[k] = normalizeListFieldValue(detail.formValues[k]);
          },
        );
      }
      hooks.onVoid = function (pid) {
        voidRejectedProposal(pid);
      };
      if (
        String(detail.status || '').toLowerCase() === 'rejected' &&
        isProposalSubmitter(detail, trailPack.trail) &&
        window.WorkbenchLive &&
        window.WorkbenchLive.markRejectionSeenByBusinessId
      ) {
        window.WorkbenchLive.markRejectionSeenByBusinessId(proposalId);
      }
      window.XFlowDetail.showDetailPanel(proposalId, detail, detailConfig, stages, hooks);
    } catch (e) {
      console.warn('showProposalDetail', e);
      if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('加载详情失败', true);
    }
  }

  function detailPanelHooks() {
    return {
      onPush: handlePushProposal,
      onInitiate: handleInitiateProposal,
      onDelete: function (pid) {
        deleteProposalDraft(pid);
      },
    };
  }

  async function handlePushProposal(proposalId) {
    var owner = formValues.owner1;
    var ownerId = owner && typeof owner === 'object' ? owner.userId : null;
    if (!ownerId) {
      var q = null;
      if (window.DunesDialog && DunesDialog.prompt) {
        q = await DunesDialog.prompt('请输入业务负责人用户 ID');
      } else {
        q = prompt('请输入业务负责人用户 ID');
      }
      ownerId = q ? parseInt(q, 10) : 0;
    }
    if (!ownerId) {
      notify('需要指定业务负责人', true);
      return;
    }
    var msg = '请确认后发起';
    if (window.DunesDialog && DunesDialog.prompt) {
      var m = await DunesDialog.prompt('推送留言（可选）', msg);
      if (m != null) msg = m || msg;
    } else {
      msg = prompt('推送留言（可选）', msg) || msg;
    }
    try {
      const detail = unwrap(
        await api('/xflow/proposals/' + proposalId + '/push', {
          method: 'POST',
          body: JSON.stringify({ initiatorUserId: ownerId, message: msg }),
        }),
      );
      if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('已推送给业务负责人');
      window.XFlowDetail.showDetailPanel(proposalId, detail, detailConfig, (detailConfig && detailConfig.stages) || [], detailPanelHooks());
      loadCcRulesPanel({
        cardId: 'xf-detail-cc-rules-card',
        panelId: 'xf-detail-cc-rules-panel',
        templateKey: (detail && detail.templateKey) || SALES_KEY,
      });
    } catch (e) {
      console.warn('push', e);
      if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('推送失败', true);
    }
  }

  function ensurePushSheet() {
    var sheet = document.getElementById('xf-push-sheet');
    if (sheet) return sheet;
    sheet = document.createElement('div');
    sheet.id = 'xf-push-sheet';
    sheet.className = 'xf-push-sheet hidden';
    sheet.innerHTML =
      '<div class="xf-push-mask" data-xf-push-close="1"></div>' +
      '<div class="xf-push-panel">' +
      '<div class="xf-push-bar"></div>' +
      '<button type="button" class="xf-push-x" data-xf-push-close="1"><i class="ti ti-x"></i></button>' +
      '<div class="xf-push-h"><i class="ti ti-send"></i>推送给同事</div>' +
      '<div class="xf-push-sub">先保存为草稿，再推送给同事确认发起；不会直接进入审批链。</div>' +
      '<label class="xf-push-lbl">接收同事（运营白名单）</label>' +
      '<input class="fld-in xf-push-search" placeholder="在白名单内搜索姓名 / 部门" autocomplete="off"/>' +
      '<div class="xf-push-results"></div>' +
      '<label class="xf-push-lbl">附言</label>' +
      '<textarea class="fld-in xf-push-msg" rows="3">请确认后发起</textarea>' +
      '<button type="button" class="xf-push-submit"><i class="ti ti-send"></i><span>确认推送</span></button>' +
      '</div>';
    if (window.DunesAppUI && DunesAppUI.mountOverlay) {
      DunesAppUI.mountOverlay(sheet);
    } else {
      document.body.appendChild(sheet);
    }
    sheet.addEventListener('click', function (ev) {
      if (ev.target.closest('[data-xf-push-close]')) {
        sheet.classList.add('hidden');
      }
    });
    return sheet;
  }

  function renderPushUsers(sheet, list, selectedId) {
    var box = sheet.querySelector('.xf-push-results');
    if (!box) return;
    if (!list || !list.length) {
      box.innerHTML = '<div class="xf-user-empty">白名单内暂无人员，请在管理台配置运营推送白名单</div>';
      return;
    }
    box.innerHTML = list
      .slice(0, 8)
      .map(function (u) {
        var uid = u.id || u.userId;
        var on = String(uid) === String(selectedId) ? ' on' : '';
        return (
          '<button type="button" class="xf-push-user' +
          on +
          '" data-uid="' +
          esc(uid) +
          '">' +
          '<b>' +
          esc(u.displayName || u.name || '') +
          '</b><small>' +
          esc(u.departmentName || u.dept || '') +
          (u.title ? ' · ' + esc(u.title) : '') +
          '</small></button>'
        );
      })
      .join('');
  }

  function showPushSheet(proposalId) {
    var sheet = ensurePushSheet();
    if (window.DunesAppUI && DunesAppUI.overlayRoot && sheet.parentElement !== DunesAppUI.overlayRoot()) {
      DunesAppUI.overlayRoot().appendChild(sheet);
    }
    var search = sheet.querySelector('.xf-push-search');
    var submit = sheet.querySelector('.xf-push-submit');
    var msg = sheet.querySelector('.xf-push-msg');
    var users = [];
    var selectedId = 0;
    sheet.classList.remove('hidden');
    renderPushUsers(sheet, [], 0);
    function syncSubmitState() {
      if (submit) submit.disabled = !selectedId;
    }
    syncSubmitState();

    loadPushWhitelist().then(function (whitelist) {
      sheet._xfWhitelistUsers = whitelist.map(function (r) {
        return {
          userId: r.userId,
          id: r.userId,
          displayName: r.displayName,
          departmentName: r.department || r.departmentName || '',
          title: r.title || '',
        };
      });
      users = sheet._xfWhitelistUsers.slice();
      renderPushUsers(sheet, users, 0);
      if (!users.length && window.DunesAPI && DunesAPI.toast) {
        DunesAPI.toast('推送白名单为空，请先在管理台配置', true);
      }
    });

    if (search && !search._xfPushBound) {
      search._xfPushBound = true;
      search.addEventListener('input', function () {
        var q = search.value.trim().toLowerCase();
        var all = sheet._xfWhitelistUsers || [];
        if (!q) {
          users = all.slice();
        } else {
          users = all.filter(function (u) {
            var label = (u.displayName || '') + (u.departmentName || '') + (u.title || '');
            return label.toLowerCase().indexOf(q) >= 0;
          });
        }
        selectedId = 0;
        renderPushUsers(sheet, users, selectedId);
        syncSubmitState();
      });
    }

    sheet.onclick = function (ev) {
      if (ev.target.closest('[data-xf-push-close]')) {
        sheet.classList.add('hidden');
        return;
      }
      var userBtn = ev.target.closest('.xf-push-user');
      if (userBtn) {
        selectedId = parseInt(userBtn.getAttribute('data-uid'), 10) || 0;
        renderPushUsers(sheet, users, selectedId);
        syncSubmitState();
      }
    };

    submit.onclick = async function () {
      if (!selectedId) {
        notify('请从白名单中选择接收同事', true);
        return;
      }
      var allowed = (sheet._xfWhitelistUsers || []).some(function (u) {
        return Number(u.userId || u.id) === Number(selectedId);
      });
      if (!allowed) {
        await tip('所选同事不在运营推送白名单中，请重新选择');
        return;
      }
      try {
        const detail = unwrap(
          await api('/xflow/proposals/' + proposalId + '/push', {
            method: 'POST',
            body: JSON.stringify({ initiatorUserId: selectedId, message: msg ? msg.value : '请确认后发起' }),
          }),
        );
        sheet.classList.add('hidden');
        if (window.DunesAPI && DunesAPI.toast) {
          DunesAPI.toast('已推送给同事，对方可代为填写并确认发起');
        }
        currentProposalId = proposalId;
        if (detail && detail.status === 'pending_initiate') {
          await renderDelegatedForm(proposalId, detail);
        } else if (window.XFlowDetail) {
          window.XFlowDetail.showDetailPanel(proposalId, detail, detailConfig || {}, (detailConfig && detailConfig.stages) || [], detailPanelHooks());
          loadCcRulesPanel({
            cardId: 'xf-detail-cc-rules-card',
            panelId: 'xf-detail-cc-rules-panel',
            templateKey: (detail && detail.templateKey) || SALES_KEY,
          });
        }
      } catch (e) {
        console.warn('push colleague', e);
        notify('推送失败：' + (e.message || '请确认接收人在推送白名单中'), true);
      }
    };
  }

  async function pushDraftToColleague(key) {
    var res = await saveDraftToServer(key || SALES_KEY);
    var pid = res && (res.proposalId || res.businessId || res.id || currentProposalId);
    if (!pid) {
      if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('草稿保存失败，无法推送', true);
      return;
    }
    currentProposalId = pid;
    showPushSheet(pid);
  }

  function clearCurrentForm(key) {
    var run = function () {
      Object.keys(formValues).forEach(function (k) {
        delete formValues[k];
      });
      currentProposalId = null;
      try {
        var draftKey =
          window.XFlowLinkage && XFlowLinkage.draftKey ? XFlowLinkage.draftKey(key || SALES_KEY) : 'xf_draft_' + (key || SALES_KEY);
        localStorage.removeItem(draftKey);
      } catch (e) {
        /* ignore */
      }
      notify('已清空表单');
      renderCurrentForm();
    };
    if (window.DunesAppUI && DunesAppUI.confirm) {
      DunesAppUI.confirm('确认一键清空当前销售提案表单？清空后本地草稿也会删除。').then(function (ok) {
        if (ok) run();
      });
      return;
    }
    if (!confirm('确认一键清空当前销售提案表单？清空后本地草稿也会删除。')) return;
    run();
  }

  async function handleInitiateProposal(proposalId) {
    try {
      const detail = unwrap(
        await api('/xflow/proposals/' + proposalId + '/initiate', {
          method: 'POST',
          body: '{}',
        }),
      );
      if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('已确认发起');
      window.XFlowDetail.showDetailPanel(proposalId, detail, detailConfig, (detailConfig && detailConfig.stages) || [], detailPanelHooks());
      loadCcRulesPanel({
        cardId: 'xf-detail-cc-rules-card',
        panelId: 'xf-detail-cc-rules-panel',
        templateKey: (detail && detail.templateKey) || SALES_KEY,
      });
    } catch (e) {
      console.warn('initiate', e);
      if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('发起失败', true);
    }
  }

  async function saveDraftToServer(key) {
    const fields = (currentDetail && (currentDetail.fields || currentDetail.template?.fieldsJson)) || [];
    const container = document.getElementById('xf-form-fields');
    if (container && window.XFlowRender) {
      window.XFlowRender.collectValues(container, fields, formValues);
    }
    var body = sanitizeFormBody(formValues, fields, {
      forDraft: true,
      proposalId: currentProposalId || undefined,
    });
    const res = unwrap(
      await api('/xflow/templates/' + encodeURIComponent(key) + '/draft', {
        method: 'POST',
        body: JSON.stringify(body),
      }),
    );
    currentProposalId = res.proposalId || currentProposalId;
    syncDeleteDraftButton();
    if (window.XFlowLinkage && window.XFlowLinkage.saveDraft) {
      window.XFlowLinkage.saveDraft(key, formValues);
    }
    if (window.WorkbenchLive && window.WorkbenchLive.refreshMyProposals) {
      window.WorkbenchLive.refreshMyProposals();
    }
    return res;
  }

  async function renderCurrentForm(opts) {
    opts = opts || {};
    const key = pendingKey || window.pendingXFlowKey || SALES_KEY;
    pendingKey = key;
    window.pendingXFlowKey = key;
    const container = document.getElementById('xf-form-fields');
    const stagesBox = document.getElementById('xf-stages-list');
    if (container) container.innerHTML = '<div class="xf-loading-hint">正在加载表单模板…</div>';
    if (stagesBox) stagesBox.innerHTML = '<div class="xf-loading-hint">加载中…</div>';
    if (window.XFlowDetail && window.XFlowDetail.hideDetailPanel) {
      window.XFlowDetail.hideDetailPanel();
    }
    if (!window.XFlowRender) {
      console.warn('XFlowRender not loaded');
      if (container) container.innerHTML = '<div class="xf-error-hint">表单渲染器未加载，请重启 App</div>';
      return;
    }
    try {
      if (window.XFlowRender.clearDictCache) window.XFlowRender.clearDictCache();
      const detail = unwrap(await api('/xflow/templates/' + encodeURIComponent(key)));
      currentDetail = detail;
      formValues = {};
      const t = detail.template || detail;
      let fields = detail.fields || t.fieldsJson || [];
      if (window.XFlowRender.enrichFieldsFromDicts) {
        fields = await window.XFlowRender.enrichFieldsFromDicts(fields, function (p) {
          return api(p).then(unwrap);
        });
      }
      if (!opts.skipLocalDraft && window.XFlowLinkage && window.XFlowLinkage.loadDraft) {
        const draft = window.XFlowLinkage.loadDraft(key);
        if (draft && Object.keys(draft).length) Object.assign(formValues, draft);
      }
      const stages = detail.stages || t.stages || [];
      const rawLayout = t.layoutJson || detail.layoutJson;
      if (rawLayout && typeof rawLayout === 'object' && rawLayout !== null) {
        currentLayout = rawLayout;
      } else if (typeof rawLayout === 'string' && rawLayout !== 'null') {
        try {
          currentLayout = JSON.parse(rawLayout);
        } catch (e) {
          currentLayout = { linkage: [], progress: {} };
        }
      } else {
        currentLayout = { linkage: [], progress: {} };
      }
      var title = '新建销售提案';
      document.getElementById('xf-form-title').textContent = title;
      const dsName = document.querySelector('.screen[data-screen="XF"] .ds-name');
      if (dsName) dsName.textContent = title;
      const dsCrumb = document.querySelector('.screen[data-screen="XF"] .ds-crumb');
      if (dsCrumb) dsCrumb.textContent = '销售提案 · PROPOSAL_3STEP';
      bindSubmitButton();
      var submitBtn = document.getElementById('xf-submit-btn');
      if (submitBtn) {
        submitBtn.innerHTML = '<i class="ti ti-send"></i>提交审批';
        submitBtn.disabled = false;
      }
      if (!opts.keepBanners) clearFormBanners();
      if (container) {
        container.innerHTML = window.XFlowRender.renderForm(fields, formValues, currentLayout);
        window.XFlowRender.bindForm(container, fields, formValues, currentLayout, function () {}, apiWrapper);
      }
      renderStages(stages);
      loadCcRulesPanel();
      if (currentProposalId && !opts.skipDetailRedirect) {
        await showProposalDetail(currentProposalId);
      }
    } catch (e) {
      console.warn('renderCurrentForm', e);
      if (container) {
        container.innerHTML =
          '<div class="xf-error-hint">加载模板失败，请确认已登录且 flow-go (6087) 已启动<br><small>' +
          String(e.message || e).replace(/</g, '') +
          '</small></div>';
      }
      if (stagesBox) stagesBox.innerHTML = '';
      if (window.DunesAPI && DunesAPI.toast) DunesAPI.toast('加载模板失败', true);
    }
  }

  function apiWrapper(path, opts) {
    return api(path, opts).then(unwrap);
  }

  async function submitCurrentForm() {
    if (submittingForm) return;
    const key = pendingKey || window.pendingXFlowKey || SALES_KEY;
    const fields = (currentDetail && (currentDetail.fields || currentDetail.template?.fieldsJson)) || [];
    const container = document.getElementById('xf-form-fields');
    if (container && window.XFlowRender) {
      window.XFlowRender.collectValues(container, fields, formValues);
    }
    const miss = window.XFlowLinkage ? window.XFlowLinkage.validateFormValues(fields, formValues) : [];
    if (miss.length) {
      notify('请填写：' + miss.slice(0, 3).join('、') + (miss.length > 3 ? '…' : ''), true);
      scrollToFirstMissingField(miss);
      return;
    }
    var submitBtn = document.getElementById('xf-submit-btn');
    var btnHtml = submitBtn ? submitBtn.innerHTML : '';
    submittingForm = true;
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.innerHTML = '<i class="ti ti-loader"></i>提交中…';
    }
    notify('正在提交审批…', false);
    try {
      var submitBody = sanitizeFormBody(formValues, fields, { proposalId: currentProposalId || undefined });
      var res;
      if (window.__xfRejectedResubmit && currentProposalId) {
        var oldProposalId = currentProposalId;
        res = unwrap(
          await api('/xflow/proposals/' + currentProposalId + '/resubmit', {
            method: 'POST',
            body: JSON.stringify(submitBody),
          }),
        );
        window.__xfRejectedResubmit = false;
        window.__xfRejectInfo = null;
        try {
          localStorage.setItem('dunes_rejection_seen_PROPOSAL_' + oldProposalId, String(Date.now()));
        } catch (eSeen) {}
      } else {
        res = unwrap(
          await api('/xflow/templates/' + encodeURIComponent(key) + '/submit', {
            method: 'POST',
            body: JSON.stringify(submitBody),
          }),
        );
      }
      notify('已提交审批', false);
      var pid = res && (res.businessId || res.proposalId || res.id);
      if (pid) {
        currentProposalId = pid;
        if (window.XFlowLinkage && window.XFlowLinkage.saveDraft) {
          window.XFlowLinkage.saveDraft(key, {});
        }
        if (window.WorkbenchLive && window.WorkbenchLive.loadB14Initiated) {
          window.WorkbenchLive.loadB14Initiated().catch(function () {});
        }
        await showProposalDetail(pid);
      } else {
        notify('提交成功，但未返回提案编号', true);
      }
    } catch (e) {
      console.warn('submit', e);
      notify(translateSubmitError(e && e.message), true);
    } finally {
      submittingForm = false;
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.innerHTML = btnHtml || '<i class="ti ti-send"></i>提交审批';
      }
    }
  }

  function wireQuickEntries() {
    document.querySelectorAll('[data-xflow-sales]').forEach(function (el) {
      el.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        openSalesProposal();
      });
    });
  }

  function init() {
    if (!document.getElementById('xf-fields-css')) {
      const link = document.createElement('link');
      link.id = 'xf-fields-css';
      link.rel = 'stylesheet';
      link.href = 'xflow_fields.css';
      document.head.appendChild(link);
    }
    bindSubmitButton();
    wireQuickEntries();
    loadB3Templates();
  }

  window.XFlowDynamic = {
    SALES_KEY: SALES_KEY,
    api: apiWrapper,
    searchOrgUsers: searchOrgUsers,
    translateSubmitError: translateSubmitError,
    translateDraftError: translateDraftError,
    sanitizeFormBody: sanitizeFormBody,
    openSalesProposal: openSalesProposal,
    openProposalDetail: openProposalDetail,
    openRejectedProposalEdit: openRejectedProposalEdit,
    voidRejectedProposal: voidRejectedProposal,
    loadB3Templates: loadB3Templates,
    renderCurrentForm: renderCurrentForm,
    submitCurrentForm: submitCurrentForm,
    saveDraftToServer: saveDraftToServer,
    deleteProposalDraft: deleteProposalDraft,
    pushDraftToColleague: pushDraftToColleague,
    clearCurrentForm: clearCurrentForm,
    showProposalDetail: showProposalDetail,
    renderStageRows: renderStageRows,
    getCurrentLayout: function () {
      return currentLayout;
    },
    bindStageHelps: bindStageHelps,
    resolveStageApprovers: resolveStageApprovers,
    renderCcRulesCardHtml: renderCcRulesCardHtml,
    loadCcRulesPanel: loadCcRulesPanel,
    init: init,
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
