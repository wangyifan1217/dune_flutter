(function (global) {
  'use strict';

  var TECH_ROUTE = {
    大出行平台: '雷江华',
    保险平台: '雷江华',
    '5G新通话': '雷江华',
    医疗平台: '雷江华',
    三桶油综合能力平台: '李凡伊',
    星和动力: '缪承恭',
    蓝鲸: '缪承恭',
  };

  var PROVINCES = [
    '全国', '北京', '上海', '广东', '江苏', '浙江', '山东', '湖北', '湖南', '四川',
    '河南', '河北', '安徽', '福建', '江西', '辽宁', '吉林', '黑龙江', '陕西', '山西',
    '内蒙古', '广西', '云南', '贵州', '甘肃', '宁夏', '青海', '新疆', '西藏', '天津', '重庆', '海南',
  ];

  function parseCond(expr, values) {
    if (!expr || !String(expr).trim()) return true;
    var parts = String(expr).split('=');
    if (parts.length < 2) return true;
    var key = parts[0].trim();
    var want = parts.slice(1).join('=').trim();
    var got = values[key];
    if (Array.isArray(got)) return got.indexOf(want) >= 0 || got.join('、') === want;
    return String(got == null ? '' : got) === want;
  }

  function evalExpr(expr, values) {
    if (!expr) return '';
    try {
      var keys = Object.keys(values);
      var vals = keys.map(function (k) {
        var v = values[k];
        if (typeof v === 'string') return parseFloat(v) || 0;
        if (typeof v === 'number') return v;
        return 0;
      });
      var fn = new Function(keys.join(','), 'return (' + expr + ');');
      var n = fn.apply(null, vals);
      if (typeof n === 'number' && !isNaN(n)) return n.toFixed(2);
      return String(n == null ? '' : n);
    } catch (e) {
      return '—';
    }
  }

  function isFilled(values, key) {
    var v = values[key];
    if (v == null) return false;
    if (v && typeof v === 'object' && (v.userId || v.id || v.name)) return true;
    if (Array.isArray(v)) return v.length > 0;
    if (typeof v === 'object') return Object.keys(v).length > 0;
    return String(v).trim() !== '';
  }

  function applyOptionsFrom(sourceKey, targetKey, values, rowShape) {
    var src = values[sourceKey];
    if (!Array.isArray(src)) return;
    var shape = rowShape || { province: '$', note: '', rate: '' };
    var existing = Array.isArray(values[targetKey]) ? values[targetKey] : [];
    var byProvince = {};
    existing.forEach(function (row) {
      if (row && row.province != null && String(row.province) !== '') {
        byProvince[String(row.province)] = row;
      }
    });
    values[targetKey] = src.map(function (item) {
      var prev = byProvince[String(item)] || {};
      var row = {};
      Object.keys(shape).forEach(function (k) {
        var tpl = shape[k];
        if (tpl === '$') {
          row[k] = item;
        } else if (prev[k] != null && String(prev[k]).trim() !== '') {
          row[k] = prev[k];
        } else {
          row[k] = tpl;
        }
      });
      return row;
    });
  }

  function draftKey(templateKey) {
    return 'xf_draft_' + (templateKey || 'sales-proposal');
  }

  function saveDraft(templateKey, values) {
    try {
      localStorage.setItem(draftKey(templateKey), JSON.stringify(values));
      return true;
    } catch (e) {
      return false;
    }
  }

  function loadDraft(templateKey) {
    try {
      var raw = localStorage.getItem(draftKey(templateKey));
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  }

  function uiTip(msg) {
    if (global.DunesAppUI && global.DunesAppUI.tip) return global.DunesAppUI.tip(msg);
    if (global.DunesDialog && global.DunesDialog.alert) return global.DunesDialog.alert(msg);
    if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast(msg);
    return Promise.resolve();
  }

  function uiToast(msg, isErr) {
    if (global.DunesAppUI && global.DunesAppUI.toast) {
      global.DunesAppUI.toast(msg, isErr);
      return;
    }
    if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast(msg, isErr);
  }

  function handleAction(kind, values, fields, layout, rerender) {
    var tk = global.pendingXFlowKey || 'sales-proposal';
    if (kind === 'save-draft') {
      uiTip('正在保存草稿到服务端，保存后可随时恢复继续填写');
      if (global.XFlowDynamic && global.XFlowDynamic.saveDraftToServer) {
        global.XFlowDynamic.saveDraftToServer(tk).then(function (res) {
          uiTip('草稿已保存 · 提案 #' + (res.proposalId || '本地'));
          if (res && res.proposalId && global.XFlowDynamic.showProposalDetail) {
            global.XFlowDynamic.showProposalDetail(res.proposalId);
          }
        }).catch(function (err) {
          var info =
            global.XFlowDynamic && global.XFlowDynamic.translateDraftError
              ? global.XFlowDynamic.translateDraftError(err)
              : { network: true, message: '网络不可用，草稿已暂存到本机' };
          if (saveDraft(tk, values)) {
            if (info.network) {
              uiTip(info.message);
            } else {
              uiToast(info.message, true);
              uiTip('草稿已暂存到本机，修正后可再次保存到服务端');
            }
          } else {
            uiToast(info.message || '草稿保存失败', true);
          }
        });
        return;
      }
      if (saveDraft(tk, values)) {
        uiTip('草稿已暂存到本机，恢复草稿可继续填写');
      }
      return;
    }
    if (kind === 'push-colleague') {
      Promise.resolve(uiTip('将先保存草稿，再从运营白名单选择同事推送')).then(function () {
        if (global.XFlowDynamic && global.XFlowDynamic.pushDraftToColleague) {
          return global.XFlowDynamic.pushDraftToColleague(tk);
        }
        uiToast('推送能力未加载', true);
      }).catch(function () {
        uiToast('推送失败', true);
      });
      return;
    }
    if (kind === 'clear-form') {
      if (global.XFlowDynamic && global.XFlowDynamic.clearCurrentForm) {
        global.XFlowDynamic.clearCurrentForm(tk);
      }
      return;
    }
    if (kind === 'load-draft') {
      var d = loadDraft(tk);
      if (!d) {
        uiTip('当前模板暂无本地草稿，请先点击「暂存草稿」保存后再恢复');
        return;
      }
      Object.keys(d).forEach(function (k) {
        values[k] = d[k];
      });
      if (rerender) rerender();
      uiTip('已恢复本地草稿，请核对后继续填写');
      return;
    }
    if (kind === 'excel-import') {
      if (typeof document === 'undefined') return;
      var input = document.createElement('input');
      input.type = 'file';
      input.accept = '.json,.csv';
      input.onchange = function () {
        if (!input.files || !input.files[0]) return;
        var reader = new FileReader();
        reader.onload = function () {
          try {
            var text = String(reader.result || '');
            var data = null;
            if (input.files[0].name.endsWith('.json')) {
              data = JSON.parse(text);
            } else {
              var lines = text.split(/\r?\n/).filter(Boolean);
              if (lines.length >= 2) {
                var headers = lines[0].split(',');
                var cells = lines[1].split(',');
                data = {};
                headers.forEach(function (h, i) {
                  data[h.trim()] = (cells[i] || '').trim();
                });
              }
            }
            if (Array.isArray(data) && data[0]) data = data[0];
            if (data && typeof data === 'object') {
              Object.keys(data).forEach(function (k) {
                values[k] = data[k];
              });
              if (rerender) rerender();
              if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('已导入字段');
            }
          } catch (e) {
            if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('导入失败', true);
          }
        };
        reader.readAsText(input.files[0], 'utf-8');
      };
      input.click();
      return;
    }
    if (kind === 'ai-policy') {
      var hint =
        '基于当前规模 ' +
        (values.targetMonthlyScaleWan || '—') +
        ' 万、省份 ' +
        ((values.provinces || []).join('、') || '—') +
        '，建议核对分省折扣与结算周期档位。';
      values.aiPolicyHint = hint;
      if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('AI 建议已生成（见财务备注）');
      if (!values.financeRemark) values.financeRemark = hint;
      else if (values.financeRemark.indexOf(hint) < 0) values.financeRemark += '\n' + hint;
      if (rerender) rerender();
      return;
    }
    if (kind === 'ai-summary') {
      var summary =
        'AI 决策摘要：' +
        '提案「' +
        (values.title || '未命名') +
        '」任务等级 ' +
        (values.owner1Level || 'C') +
        '，覆盖 ' +
        ((values.provinces || []).join('、') || '未选择省份') +
        '；建议审批时重点核对业务责任人、结算周期、垫资/税务成本与方案正文一致性。';
      values.aiPolicyHint = summary;
      if (!values.financeRemark) values.financeRemark = summary;
      else if (values.financeRemark.indexOf(summary) < 0) values.financeRemark += '\n' + summary;
      if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('AI 决策摘要已生成');
      if (rerender) rerender();
      return;
    }
    if (global.DunesAPI && DunesAPI.toast) DunesAPI.toast('操作：' + kind);
  }

  function stampTax(values) {
    var scale = parseFloat(values.targetMonthlyScaleWan) || 0;
    return (scale * 0.0003).toFixed(2);
  }

  function techRoutePreview(values) {
    var tp = values.techPlatform || '';
    var name = TECH_ROUTE[tp] || '请先选择技术标签';
    if (typeof document !== 'undefined') {
      var el = document.getElementById('xf-tech-approver-preview');
      if (el) {
        el.innerHTML =
          '<div class="xf-stage-row"><div class="xf-stage-no">3</div><div><div class="xf-stage-name">' +
          name +
          '</div><div class="xf-stage-meta">技术审批 · ' +
          (tp || '—') +
          '</div></div></div>';
      }
    }
    return name;
  }

  function runHooks(layout, values) {
    (layout.linkage || []).forEach(function (rule) {
      if (rule.type === 'optionsFrom' && rule.source && rule.target) {
        applyOptionsFrom(rule.source, rule.target, values, rule.rowShape);
      }
      if (rule.type === 'hook' && rule.name === 'techRoutePreview') {
        techRoutePreview(values);
      }
      if (rule.type === 'compute' && rule.target && rule.expr) {
        values[rule.target] = evalExpr(rule.expr, values);
      }
    });
  }

  function updateProgress(layout, values) {
    var prog = layout.progress || {};
    var biz = prog.biz || [];
    var fin = prog.fin || [];
    var bizDone = biz.filter(function (k) {
      return isFilled(values, k);
    }).length;
    var finDone = fin.filter(function (k) {
      return isFilled(values, k);
    }).length;
    var total = biz.length + fin.length;
    var done = bizDone + finDone;
    var pct = total ? Math.round((done / total) * 100) : 0;
    if (typeof document === 'undefined') {
      return { pct: pct, bizDone: bizDone, bizTotal: biz.length, finDone: finDone, finTotal: fin.length };
    }
    var valEl = document.getElementById('xf-progress-val');
    var barEl = document.getElementById('xf-progress-bar');
    var bizEl = document.getElementById('xf-biz-meta');
    var finEl = document.getElementById('xf-fin-meta');
    if (valEl) valEl.textContent = String(pct);
    if (barEl) barEl.style.width = pct + '%';
    if (bizEl) bizEl.textContent = bizDone + ' / ' + biz.length;
    if (finEl) finEl.textContent = finDone + ' / ' + fin.length;
    return { pct: pct, bizDone: bizDone, bizTotal: biz.length, finDone: finDone, finTotal: fin.length };
  }

  function validateRequired(fields, values) {
    var miss = [];
    fields.forEach(function (f) {
      if (f.type === 'section' || f.type === 'action' || f.type === 'computed' || f.type === 'row') return;
      if (f.readonly) return;
      if (f.visibleWhen && String(f.visibleWhen).trim() && !parseCond(f.visibleWhen, values)) return;
      var req = !!f.required;
      if (!req && f.requiredWhen && String(f.requiredWhen).trim()) {
        req = parseCond(f.requiredWhen, values);
      }
      if (req && !isFilled(values, f.key)) miss.push(f.label || f.key);
    });
    return miss;
  }

  function userRef(values, key) {
    var v = values[key];
    if (v && typeof v === 'object') return v.userId || v.id || v.name || '';
    return v || '';
  }

  /** Map XFlow form values to P0 create payload shape (proposal_p0_intake.buildCreatePayload). */
  function buildPayload(values) {
    var tag1 = values.tag1;
    if (Array.isArray(tag1)) tag1 = tag1[0] || '';
    return {
      title: values.title || '',
      tag1: tag1 || '',
      owner1: userRef(values, 'owner1'),
      techPlatform: values.techPlatform || '',
      taskLevel: values.owner1Level || values.taskLevel || '',
      launchDate: values.launchDate || null,
      needAdvanceFund: values.needAdvanceFund === '是',
      advanceFundPlan: values.advanceFundPlan || '',
      solutionDesc: values.solutionDesc ? { text: values.solutionDesc } : null,
      financeDisplay: {
        launchDate: values.launchDate,
        launchChannel: values.launchChannel,
        provinceDiscounts: values.provinceDiscounts,
        settlementCycles: values.settlementCycles,
        targetMonthlyScaleWan: values.targetMonthlyScaleWan,
        targetMonthlyProfitWan: values.targetMonthlyProfitWan,
        profitModel: values.profitModel,
        supplierPolicies: values.supplierPolicies,
        channelPolicies: values.channelPolicies,
        oilBundleRows: values.oilBundleRows,
        supplyScaleByProvince: values.supplyScaleByProvince,
        pricingMatrix: values.pricingMatrix,
        provinceCosts: values.provinceCosts,
        invoiceFlows: values.invoiceFlows,
        capitalFlows: values.capitalFlows,
        needRollback: values.needRollback,
        responsibles: {
          national: values.respNational,
          ops: values.respOps,
          province: values.respProvince,
          tech: values.respTech,
        },
        riskTech: values.riskTech,
        riskBusiness: values.riskBusiness,
        riskFinance: values.riskFinance,
      },
    };
  }

  /** Legacy P0 payload shape helper — not used for XFlow submit validation (template fieldsJson drives required rules). */
  function validatePayload(payload) {
    var miss = [];
    if (!payload.title) miss.push('提案名称');
    if (!payload.tag1) miss.push('产品属性');
    if (!payload.owner1) miss.push('第一责任人');
    if (!payload.techPlatform) miss.push('技术标签');
    if (!payload.taskLevel) miss.push('第一责任人等级');
    var launchDate = payload.launchDate || (payload.financeDisplay && payload.financeDisplay.launchDate);
    if (!String(launchDate || '').trim()) miss.push('计划上线日期');
    if (payload.needAdvanceFund && !String(payload.advanceFundPlan || '').trim()) {
      miss.push('垫资计划');
    }
    var sol = payload.solutionDesc;
    if (!sol || !String(sol.text || sol).trim()) miss.push('方案说明文字');
    return miss;
  }

  function validateFormValues(fields, values) {
    return validateRequired(fields || [], values);
  }

  global.XFlowLinkage = {
    TECH_ROUTE: TECH_ROUTE,
    PROVINCES: PROVINCES,
    parseCond: parseCond,
    evalExpr: evalExpr,
    isFilled: isFilled,
    applyOptionsFrom: applyOptionsFrom,
    stampTax: stampTax,
    techRoutePreview: techRoutePreview,
    runHooks: runHooks,
    updateProgress: updateProgress,
    validateRequired: validateRequired,
    buildPayload: buildPayload,
    validatePayload: validatePayload,
    validateFormValues: validateFormValues,
    saveDraft: saveDraft,
    loadDraft: loadDraft,
    handleAction: handleAction,
    draftKey: draftKey,
  };
})(typeof window !== 'undefined' ? window : global);
