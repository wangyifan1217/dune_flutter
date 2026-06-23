/**
 * P0 移动端「新建销售提案」· DOM 读取与审批 API 对接
 */
(function (global) {
  'use strict';

  const TECH_ROUTE = {
    大出行平台: '雷江华',
    保险平台: '雷江华',
    '5G新通话': '雷江华',
    医疗平台: '雷江华',
    三桶油综合能力平台: '李凡伊',
    星和动力: '缪承恭',
    蓝鲸: '缪承恭',
  };

  const DRAFT_KEY = 'np_p0_draft_v1';
  const BEACON_KEY = 'np_beacon_project';

  function mapGoodType(v) {
    if (v === '油品') return '油品';
    if (v === '虚拟商品' || v === '虚拟') return '虚拟';
    if (v === '实物商品' || v === '实物') return '虚拟';
    if (v === '大宗' || v === '大宗/批发') return '油品';
    return v || '油品';
  }

  function mapProposalType(v) {
    if (v === '变更' || v === '延续' || v === '其他') return v;
    return '新增';
  }

  /** 新版 HTML 用 data-p0-group；旧版用 data-np-pill-group */
  const GROUP_ALIASES = {
    good: ['goods', 'goods2', 'good'],
    type: ['ptype', 'type'],
    'owner1-lvl': ['lvl1', 'owner1-lvl'],
    'owner2-lvl': ['lvl2', 'owner2-lvl'],
    'invoice-cost': ['taxcost', 'invoice-cost'],
    'tax-burden': ['taxburden', 'tax-burden'],
  };

  const EXTRA_PROVINCES =
    '安徽,陕西,山西,甘肃,青海,宁夏,新疆,西藏,云南,贵州,海南,吉林,黑龙江'.split(',');

  function q(root, sel) {
    return root.querySelector(sel);
  }

  function qa(root, sel) {
    return Array.from(root.querySelectorAll(sel));
  }

  function usesP0Schema(root) {
    return !!(root.querySelector('[data-p0-group]') || root.querySelector('.p0-pill'));
  }

  function findGroup(root, group) {
    const names = [group].concat(GROUP_ALIASES[group] || []);
    for (let i = 0; i < names.length; i++) {
      const g =
        root.querySelector('[data-p0-group="' + names[i] + '"]') ||
        root.querySelector('[data-np-pill-group="' + names[i] + '"]');
      if (g) return g;
    }
    return null;
  }

  function isMultiGroup(g) {
    return g.getAttribute('data-p0-multi') === '1' || g.getAttribute('data-multi') === 'true';
  }

  function pillValue(el) {
    if (!el) return '';
    const attr = el.getAttribute('data-p0-val') || el.getAttribute('data-v');
    if (attr) return attr;
    const clone = el.cloneNode(true);
    const dot = clone.querySelector('.d');
    if (dot) dot.remove();
    let t = (clone.textContent || '').trim();
    if (t.indexOf('·') >= 0) t = t.split('·')[0].trim();
    if (t === '无承担') return '无';
    if (t === '无承担') return '无';
    if (t === '双方共担') return '双方共担';
    return t;
  }

  function readPill(root, group) {
    const aliases = GROUP_ALIASES[group] || [group];
    for (let i = 0; i < aliases.length; i++) {
      const g = findGroup(root, aliases[i]);
      if (!g) continue;
      const on = g.querySelector(
        '.p0-pill.on, .p0-prov.on, .p0-lvl.on, .pill.on, .province-pill.on, .lp.on',
      );
      if (on) return pillValue(on);
    }
    return '';
  }

  function readMultiPill(root, group) {
    const g = findGroup(root, group);
    if (!g) return [];
    return qa(g, '.p0-pill.on, .p0-prov.on, .pill.on, .province-pill.on')
      .map(pillValue)
      .filter(function (v) {
        return v && v !== '+ 更多';
      });
  }

  function readGoodType(root) {
    const g2 = readPill(root, 'goods2');
    if (g2) return g2;
    const g1 = readPill(root, 'goods');
    if (g1) return g1;
    return readPill(root, 'good') || '油品';
  }

  function readTaskLevel(root, which) {
    const key = which === 2 ? 'owner2-lvl' : 'owner1-lvl';
    const g = findGroup(root, key);
    if (!g) return which === 1 ? 'C' : '';
    const on = g.querySelector('.p0-lvl.on, .lp.on');
    if (!on) return which === 1 ? 'C' : '';
    if (on.classList.contains('S')) return 'S';
    if (on.classList.contains('A')) return 'A';
    if (on.classList.contains('B')) return 'B';
    if (on.classList.contains('C')) return 'C';
    return (on.textContent || '').trim();
  }

  function normalizeTechPlatform(v) {
    if (!v) return '';
    return String(v).replace(/5G\s*新通话/g, '5G新通话').trim();
  }

  function techSelect(root) {
    return root.querySelector('#p0-tech-platform') || root.querySelector('#np-tech-platform');
  }

  function solutionTextarea(root) {
    return root.querySelector('#p0-solution-text') || root.querySelector('#np-solution-text');
  }

  function readDynCycles(root) {
    const list = root.querySelector('#p0-cycle-list') || root.querySelector('[data-np-dyn="cycles"]');
    if (!list) return [];
    const rows = list.querySelectorAll('.p0-cycle-row, .dyn-row');
    return Array.from(rows).map(function (row) {
      const cells = qa(row, 'select, input');
      return {
        cycle: cells[0] ? cells[0].value.trim() : '',
        term: cells[1] ? cells[1].value.trim() : '',
        weight: cells[2] ? cells[2].value.trim() : '',
      };
    }).filter(function (r) {
      return r.cycle || r.term || r.weight;
    });
  }

  function primarySettlementCycle(cycles) {
    if (!cycles.length) return 'T+0';
    if (cycles.length > 1) return '多档';
    const term = (cycles[0].term || '').toUpperCase();
    if (/^T\+\d+$/.test(term)) return term;
    if (term === '其他') return '其他';
    return '多档';
  }

  function readProvinceDiscounts(root) {
    const box = root.querySelector('#p0-prov-disc') || root.querySelector('[data-np-dyn="province-discount"]');
    if (!box) return [];
    return qa(box, '.dyn-row[data-prov], .p0-prov-disc-row').map(function (row) {
      const ins = qa(row, 'input');
      return {
        province: row.getAttribute('data-prov') || (ins[0] ? ins[0].value.trim() : ''),
        note: ins[0] && row.getAttribute('data-prov') ? ins[0].value.trim() : ins[1] ? ins[1].value.trim() : '',
        rate: ins[1] && row.getAttribute('data-prov') ? ins[1].value.trim() : ins[2] ? ins[2].value.trim() : '',
      };
    }).filter(function (r) {
      return r.province;
    });
  }

  function readBundleRows(root) {
    const list = root.querySelector('#p0-bundle-matrix') || root.querySelector('[data-np-dyn="bundle"]');
    if (!list) return [];
    const rows = list.querySelectorAll('.p0-matrix-r, .dyn-row');
    return Array.from(rows).map(function (row) {
      const ins = qa(row, 'input.inp, input');
      return {
        product: ins[0] ? ins[0].value.trim() : '',
        cost: ins[1] ? ins[1].value.trim() : '',
        salePrice: ins[2] ? ins[2].value.trim() : '',
        customerPrice: ins[3] ? ins[3].value.trim() : '',
        rebate: ins[4] ? ins[4].value.trim() : '',
      };
    }).filter(function (r) {
      return r.product || r.cost || r.salePrice || r.customerPrice || r.rebate;
    });
  }

  function readSupplyRows(root) {
    const list = root.querySelector('#p0-supply-list') || root.querySelector('[data-np-dyn="supply"]');
    if (!list) return [];
    return qa(list, '.p0-supply-row, .dyn-row').map(function (row) {
      const sel = row.querySelector('select');
      const ins = qa(row, 'input');
      return {
        province: sel ? sel.value : row.getAttribute('data-prov') || '',
        stock: ins[0] ? ins[0].value.trim() : '',
        increment: ins[1] ? ins[1].value.trim() : '',
      };
    }).filter(function (r) {
      return r.province || r.stock || r.increment;
    });
  }

  function readMatrixRows(root) {
    const list = root.querySelector('[data-np-dyn="matrix"]');
    if (!list) return [];
    return qa(list, '.dyn-row').map(function (row) {
      const ins = qa(row, 'input');
      return {
        supplier: ins[0] ? ins[0].value.trim() : '',
        scale: ins[1] ? ins[1].value.trim() : '',
        discount: ins[2] ? ins[2].value.trim() : '',
        premium: ins[3] ? ins[3].value.trim() : '',
      };
    }).filter(function (r) {
      return r.supplier || r.scale || r.discount || r.premium;
    });
  }

  function readProvinceCostRows(root) {
    const list = root.querySelector('[data-np-dyn="province-cost"]');
    if (!list) return [];
    return qa(list, '.dyn-row').map(function (row) {
      const sel = row.querySelector('select');
      const ins = qa(row, 'input');
      return {
        province: sel ? sel.value : '',
        projectCost: ins[0] ? ins[0].value.trim() : '',
        marketing: ins[1] ? ins[1].value.trim() : '',
        tax: ins[2] ? ins[2].value.trim() : '',
        salesTaxRate: '',
        supplySideTaxRate: ins[2] ? ins[2].value.trim() : '',
      };
    }).filter(function (r) {
      return r.province || r.projectCost || r.marketing || r.tax;
    });
  }

  function readFlowRows(root, key) {
    const idMap = {
      'invoice-flow': 'p0-flow-invoice',
      'capital-flow': 'p0-flow-capital',
      'contract-flow': 'p0-flow-contract',
      'business-flow': 'p0-flow-business',
    };
    const list =
      root.querySelector('#' + (idMap[key] || '')) || root.querySelector('[data-np-dyn="' + key + '"]');
    if (!list) return [];
    return qa(list, '[data-p0-flow-row], .dyn-row, .p0-flow-row').map(function (row) {
      const sel = row.querySelector('select');
      const inp = row.querySelector('input');
      const steps = qa(row, '.p0-flow-step')
        .map(function (b) {
          const t = (b.textContent || '').trim();
          return t && t !== '选择主体' ? t : '';
        })
        .filter(Boolean);
      const chain = inp
        ? inp.value.trim()
        : steps.length
          ? steps.join(' → ')
          : '';
      const tag = row.querySelector('.tag');
      return {
        side: sel ? sel.value : tag ? tag.textContent.trim() : '',
        chain: chain,
      };
    }).filter(function (r) {
      return r.chain || r.side;
    });
  }

  function readTechCapability(root) {
    const kv = root.querySelector('.tech-kv');
    if (!kv) return null;
    const keys = ['产品能力', '收银台', '使用工具', '信息流', '输出形态', '数商渠道', '渠道接口', 'DICT 说明', '风控规则'];
    const out = {};
    qa(kv, '.tkr').forEach(function (row, i) {
      const k = keys[i] || ('field' + i);
      const el = row.querySelector('input, textarea');
      if (el && el.value.trim()) out[k] = el.value.trim();
    });
    return Object.keys(out).length ? out : null;
  }

  function readSolutionDesc(root) {
    const ta = solutionTextarea(root);
    if (!ta || !ta.value.trim()) return null;
    const scaleInputs = qa(root, 'input.mono[placeholder="¥"][data-np-field="solution"]');
    const scaleP0 = root.querySelector('#p0-f-target-scale') || root.querySelector('input[placeholder="如 2700"]');
    const profitP0 = root.querySelector('#p0-f-target-profit') || root.querySelector('input[placeholder="如 36.7"]');
    return {
      text: ta.value.trim(),
      monthlyScaleWan: scaleInputs[0]
        ? scaleInputs[0].value.trim()
        : scaleP0
          ? scaleP0.value.trim()
          : '',
      monthlyProfitWan: scaleInputs[1]
        ? scaleInputs[1].value.trim()
        : profitP0
          ? profitP0.value.trim()
          : '',
    };
  }

  function valByPlaceholder(root, ph) {
    const el = root.querySelector('.fld-in[placeholder="' + ph + '"]');
    return el ? el.value.trim() : '';
  }

  function readBeaconContext() {
    try {
      const raw = sessionStorage.getItem(BEACON_KEY) || localStorage.getItem(BEACON_KEY);
      if (raw) return JSON.parse(raw);
    } catch (_) {}
    return { projectId: '', projectName: '待产品生成后回填' };
  }

  function readOwnerFields(root) {
    const o1 = root.querySelector('#p0-f-owner1');
    const o2 = root.querySelector('#p0-f-owner2');
    if (o1 || o2) {
      return { owner1: o1 ? o1.value.trim() : '', owner2: o2 ? o2.value.trim() : '' };
    }
    let owner1 = '';
    let owner2 = '';
    qa(root, '.fld').forEach(function (fld) {
      const lbl = fld.querySelector('.fld-lbl');
      const inp = fld.querySelector('.fld-in');
      if (!lbl || !inp || inp.readOnly) return;
      const text = lbl.textContent || '';
      if (text.indexOf('第一责任人') >= 0 && text.indexOf('第二') < 0) owner1 = inp.value.trim();
      if (text.indexOf('第二责任人') >= 0) owner2 = inp.value.trim();
    });
    return { owner1: owner1, owner2: owner2 };
  }

  function readBusinessFromP0(root) {
    const beacon = readBeaconContext();
    const owners = readOwnerFields(root);
    const respGrid = root.querySelector('.responsible-grid');
    const respInputs = respGrid
      ? qa(respGrid, '.fld-in')
      : qa(root, '.form-card .fld-in[list="p0-people-all"]');
    const launchDateEl =
      root.querySelector('input[type="date"][data-p0-key="biz"]') ||
      root.querySelector('input[type="date"][data-np-field="biz"]');
    const cycles = readDynCycles(root);
    const advance = readPill(root, 'advance');
    const needAdvance = advance === '是';
    const planEl =
      root.querySelector('#p0-f-advance-plan') ||
      root.querySelector('#p0-advance-detail textarea') ||
      root.querySelector('.np-advance-plan textarea');
    const guideUsed = qa(root, '.guide-chip.used, .p0-guide-chip.used')
      .map(function (c) {
        return (c.getAttribute('data-p0-guide') || c.getAttribute('data-np-guide') || '').replace(
          /^【|】$/g,
          '',
        );
      })
      .filter(Boolean)
      .join(',');

    return {
      proposalName: (root.querySelector('#p0-f-name') || {}).value?.trim() || valByPlaceholder(root, '请填写提案名称'),
      proposalCode:
        (root.querySelector('#p0-f-code') || {}).value?.trim() ||
        valByPlaceholder(root, '请填写编号') ||
        valByPlaceholder(root, '可手工填写'),
      submitter:
        (root.querySelector('#p0-f-submitter') || {}).value?.trim() ||
        valByPlaceholder(root, '登录人自动带出'),
      projectId: beacon.projectId || '',
      projectName: beacon.projectName || '待产品生成后回填',
      tag1: readMultiPill(root, 'tag1').join('、'),
      txType: readPill(root, 'tx') || '销售',
      goodType: readGoodType(root),
      proposalType: readPill(root, 'type') || readPill(root, 'ptype') || '新增',
      taskLevel: readTaskLevel(root, 1),
      owner2Level: readTaskLevel(root, 2),
      techPlatform: normalizeTechPlatform((techSelect(root) || {}).value || ''),
      owner1: owners.owner1,
      owner2: owners.owner2,
      provinces: readMultiPill(root, 'provinces'),
      launchChannel: valByPlaceholder(root, '例：平安产险') || valByPlaceholder(root, '如：平安产险'),
      launchDate: launchDateEl ? launchDateEl.value : '',
      products: [],
      solutionDesc: readSolutionDesc(root),
      techCapability: readTechCapability(root),
      responsibles: (function () {
        const gx = root.querySelector('#p0-f-owner-guoxian');
        const ops = root.querySelector('#p0-f-owner-ops');
        const prov = root.querySelector('#p0-f-owner-province');
        const tech = root.querySelector('#p0-f-owner-tech');
        if (gx || ops || prov || tech) {
          return {
            national: gx ? gx.value.trim() : '',
            ops: ops ? ops.value.trim() : '',
            province: prov ? prov.value.trim() : '',
            tech: tech ? tech.value.trim() : '',
          };
        }
        const grid = root.querySelector('.responsible-grid');
        if (grid) {
          const ins = qa(grid, '.fld-in');
          return {
            national: ins[0] ? ins[0].value.trim() : '',
            ops: ins[1] ? ins[1].value.trim() : '',
            province: ins[2] ? ins[2].value.trim() : '',
            tech: ins[3] ? ins[3].value.trim() : '',
          };
        }
        const roleInputs = qa(root, '.fld-in[list="p0-people-all"]');
        if (roleInputs.length >= 4) {
          return {
            national: roleInputs[0].value.trim(),
            ops: roleInputs[1].value.trim(),
            province: roleInputs[2].value.trim(),
            tech: roleInputs[3].value.trim(),
          };
        }
        return {
          national: respInputs[0] ? respInputs[0].value.trim() : '',
          ops: respInputs[1] ? respInputs[1].value.trim() : '',
          province: respInputs[2] ? respInputs[2].value.trim() : '',
          tech: respInputs[3] ? respInputs[3].value.trim() : '',
        };
      })(),
      finance: {
        cycles: cycles,
        settlementCycle: primarySettlementCycle(cycles),
        needAdvanceFund: needAdvance,
        advanceFundPlan: needAdvance && planEl ? planEl.value.trim() : null,
        hasInvoiceTaxCost: readPill(root, 'invoice-cost') || '否',
        taxBurdenSide: readPill(root, 'tax-burden') || '无',
        needRollback: readPill(root, 'rollback') || '否',
        provinceDiscounts: readProvinceDiscounts(root),
        discountPolicyNote: (function () {
          const ta =
            root.querySelector('#p0-f-discount-policy-note') ||
            root.querySelector('textarea[placeholder*="档位"]');
          return ta ? ta.value.trim() : '';
        })(),
        oilBundleRows: readBundleRows(root),
        supplyScaleByProvince: readSupplyRows(root),
        pricingMatrix: readMatrixRows(root),
        provinceCosts: readProvinceCostRows(root),
        invoiceFlows: readFlowRows(root, 'invoice-flow'),
        capitalFlows: readFlowRows(root, 'capital-flow'),
        contractFlows: [],
        businessFlows: [],
        supplierPolicies: (function () {
          const ta = qa(root, 'textarea[data-np-field="biz-mode"]')[0];
          return ta && ta.value.trim() ? ta.value.trim() : '';
        })(),
        channelPolicies: (function () {
          const ta = qa(root, 'textarea[data-np-field="biz-mode"]')[1];
          return ta && ta.value.trim() ? ta.value.trim() : '';
        })(),
        profitModel: readPill(root, 'profit') || '利差',
        financeRemark: (function () {
          const ta = root.querySelector('textarea[placeholder="财务补充说明"]');
          return ta ? ta.value.trim() : '';
        })(),
        riskTech: (function () {
          const ta = qa(root, 'textarea[data-np-field="risk"]')[0];
          return ta ? ta.value.trim() : '';
        })(),
        riskBusiness: (function () {
          const ta = qa(root, 'textarea[data-np-field="risk"]')[1];
          return ta ? ta.value.trim() : '';
        })(),
        riskFinance: (function () {
          const ta = qa(root, 'textarea[data-np-field="risk"]')[2];
          return ta ? ta.value.trim() : '';
        })(),
        guideUsed: guideUsed || null,
        targetMonthlyScaleWan: (function () {
          const el = root.querySelector('#p0-f-target-scale');
          if (el && el.value.trim()) return el.value.trim();
          const ins = qa(root, 'input.mono[placeholder="¥"][data-np-field="solution"]');
          if (ins[0]) return ins[0].value.trim();
          const p0 = root.querySelector('input[placeholder="如 2700"]');
          return p0 ? p0.value.trim() : '';
        })(),
        targetMonthlyProfitWan: (function () {
          const el = root.querySelector('#p0-f-target-profit');
          if (el && el.value.trim()) return el.value.trim();
          const ins = qa(root, 'input.mono[placeholder="¥"][data-np-field="solution"]');
          if (ins[1]) return ins[1].value.trim();
          const p0 = root.querySelector('input[placeholder="如 36.7"]');
          return p0 ? p0.value.trim() : '';
        })(),
      },
    };
  }

  function buildCreatePayload(root) {
    const biz = readBusinessFromP0(root);
    const fin = biz.finance;
    const riskParts = [
      fin.riskTech && '【技术风控】\n' + fin.riskTech,
      fin.riskBusiness && '【商务风控】\n' + fin.riskBusiness,
      fin.riskFinance && '【财务风控】\n' + fin.riskFinance,
    ].filter(Boolean);

    return {
      title: biz.proposalName,
      projectId: biz.projectId || '',
      projectName: biz.projectName || '待产品生成后回填',
      tag1: biz.tag1,
      txType: biz.txType,
      goodType: mapGoodType(biz.goodType),
      proposalType: mapProposalType(biz.proposalType),
      taskLevel: biz.taskLevel,
      owner2Level: biz.owner2 && biz.owner2Level ? biz.owner2Level : null,
      techPlatform: biz.techPlatform,
      owner1: biz.owner1,
      owner2: biz.owner2 || null,
      provinces: biz.provinces || [],
      products: [],
      solutionDesc: biz.solutionDesc,
      techCapability: biz.techCapability,
      settlementCycle: fin.settlementCycle || 'T+0',
      settlementCycleCustomDays: null,
      invoiceTaxRate: '6%',
      needAdvanceFund: !!fin.needAdvanceFund,
      advanceFundPlan: fin.advanceFundPlan,
      guideUsed: fin.guideUsed,
      launchDate: biz.launchDate || null,
      targetMonthlyScaleWan: fin.targetMonthlyScaleWan || null,
      targetMonthlyProfitWan: fin.targetMonthlyProfitWan || null,
      financeDisplay: {
        proposalCode: biz.proposalCode,
        submitter: biz.submitter,
        launchChannel: valByPlaceholder(root, '如：平安产险'),
        launchDate: biz.launchDate,
        hasInvoiceTaxCost: fin.hasInvoiceTaxCost,
        taxBurdenSide: fin.taxBurdenSide,
        needRollback: fin.needRollback,
        provinceDiscounts: fin.provinceDiscounts,
        discountPolicyNote: fin.discountPolicyNote,
        oilBundleRows: fin.oilBundleRows,
        supplyScaleByProvince: fin.supplyScaleByProvince,
        pricingMatrix: fin.pricingMatrix,
        provinceCosts: fin.provinceCosts,
        invoiceFlows: fin.invoiceFlows,
        capitalFlows: fin.capitalFlows,
        contractFlows: fin.contractFlows,
        businessFlows: fin.businessFlows,
        supplierPolicies: fin.supplierPolicies,
        channelPolicies: fin.channelPolicies,
        profitModel: fin.profitModel,
        financeRemark: fin.financeRemark,
        settlementCycles: fin.cycles,
        responsibles: biz.responsibles,
        riskTech: fin.riskTech,
        riskBusiness: fin.riskBusiness,
        riskFinance: fin.riskFinance,
        riskStandard: riskParts.join('\n\n'),
        targetMonthlyScaleWan: fin.targetMonthlyScaleWan,
        targetMonthlyProfitWan: fin.targetMonthlyProfitWan,
      },
    };
  }

  function validatePayload(payload) {
    const miss = [];
    if (!payload.title) miss.push('提案名称');
    if (!payload.tag1) miss.push('产品属性');
    if (!payload.owner1) miss.push('第一责任人');
    if (!payload.techPlatform) miss.push('技术标签');
    if (!payload.taskLevel) miss.push('第一责任人等级');
    const launchDate = payload.launchDate || payload.financeDisplay?.launchDate;
    if (!String(launchDate || '').trim()) miss.push('计划上线日期');
    if (payload.needAdvanceFund && !String(payload.advanceFundPlan || '').trim()) {
      miss.push('垫资计划');
    }
    const sol = payload.solutionDesc;
    if (!sol || !String(sol.text || sol).trim()) miss.push('方案说明文字');
    return miss;
  }

  function toast(root, msg, isErr) {
    const t = root.querySelector('#p0-toast') || root.querySelector('#np-toast');
    const m = root.querySelector('#p0-toast-msg') || root.querySelector('#np-toast-msg');
    if (t) {
      if (m) m.textContent = msg;
      else t.lastChild && (t.lastChild.textContent = msg);
      t.classList.add('show');
      clearTimeout(t._timer);
      t._timer = setTimeout(function () {
        t.classList.remove('show');
      }, isErr ? 2800 : 1800);
      return;
    }
    if (global.DunesAPI && global.DunesAPI.toast) global.DunesAPI.toast(msg, isErr);
  }

  function loginRedirect() {
    const next = encodeURIComponent('index(1).html');
    if (global.ProposalAuthSession && global.ProposalAuthSession.redirectIfAnonymous) {
      global.ProposalAuthSession.redirectIfAnonymous('proposal_login.html?next=' + next);
      return;
    }
    window.location.href = 'proposal_login.html?next=' + next;
  }

  function currentUser() {
    if (global.ProposalAPI && global.ProposalAPI.isLoggedIn()) {
      return global.ProposalAPI.getUser();
    }
    return null;
  }

  function fillUserPill(root) {
    const user = currentUser();
    const pill = root.querySelector('.np-user-pill');
    if (!pill) return;
    const av = pill.querySelector('.av');
    const nm = pill.querySelector('.nm');
    if (!user) {
      if (av) av.textContent = '?';
      if (nm) nm.textContent = '登录后自动带出提报人';
      return;
    }
    if (av) av.textContent = user.name.slice(-1);
    if (nm) nm.textContent = user.name + (user.dept ? ' · ' + user.dept : '');
    const submitter = root.querySelector('#p0-f-submitter') || root.querySelector('.fld-in[placeholder="登录人自动带出"]');
    if (submitter && !submitter.value.trim()) submitter.value = user.name;
    const chainStart = root.querySelector('#np-chain .ac-row');
    if (chainStart) {
      chainStart.querySelector('.ac-nm').textContent = user.name + ' · 发起人';
      chainStart.querySelector('.ac-role').textContent = user.dept || '部门待识别';
      chainStart.querySelector('.ac-av').textContent = user.name.slice(-1);
      chainStart.classList.remove('pending');
    }
  }

  function fillBeaconHint(root) {
    const beacon = readBeaconContext();
    const hint = root.querySelector('.bind-hint .bh-d');
    if (hint && beacon.projectName && beacon.projectName !== '待产品生成后回填') {
      hint.textContent =
        (beacon.projectName || '灯塔项目') +
        ' · 填好后提交将直接进入审批链。结算协议后置到资管平台处理。';
    }
  }

  function updateTechApproverLocal(root, platform) {
    const row = root.querySelector('#np-tech-approver');
    if (!row) return;
    const name = TECH_ROUTE[platform];
    if (platform && name) {
      row.classList.remove('pending');
      row.querySelector('.ac-av').textContent = name.slice(-1);
      row.querySelector('.ac-nm').textContent = name;
      row.querySelector('.ac-role').textContent = '技术审批 · ' + platform;
    } else {
      row.classList.add('pending');
      row.querySelector('.ac-av').innerHTML =
        '<i class="ti ti-cpu" style="font-size:11px"></i>';
      row.querySelector('.ac-nm').textContent = '技术审批';
      row.querySelector('.ac-role').textContent = '请先在上方选择技术标签';
    }
  }

  async function refreshApprovalChain(root) {
    const user = currentUser();
    const platform = (root.querySelector('#np-tech-platform') || {}).value || '';
    updateTechApproverLocal(root, platform);
    if (!user || !platform || !global.ProposalAPI) return;
    try {
      const data = await global.ProposalAPI.previewChain({
        initiator: user.name,
        initiatorDept: user.dept || '',
        techPlatform: platform,
      });
      renderChainFromApi(root, data.chain || []);
    } catch (_) {}
  }

  function renderChainFromApi(root, chain) {
    const box = root.querySelector('#np-chain');
    if (!box || !chain.length) return;
    const styles = [
      'background:var(--accent-soft);color:var(--accent);border:1px solid var(--accent-line)',
      'background:var(--blue-soft);color:var(--blue);border:1px solid var(--blue-line)',
      'background:var(--green-soft);color:var(--green);border:1px solid var(--green-line)',
      'background:var(--amber-soft);color:var(--amber);border:1px solid var(--amber-line)',
    ];
    box.innerHTML = chain
      .map(function (node, i) {
        const pending = node.skipped ? ' pending' : '';
        const st = i === 0 ? '起' : String(i);
        const av = (node.name || '?').slice(-1);
        const style = styles[Math.min(i, styles.length - 1)];
        const skipNote = node.skipped ? ' · 自动跳过' : '';
        return (
          '<div class="ac-row' +
          pending +
          '">' +
          '<span class="ac-av" style="' +
          style +
          '">' +
          av +
          '</span>' +
          '<div class="ac-bd"><div class="ac-nm">' +
          (node.name || '—') +
          '</div><div class="ac-role">' +
          (node.label || '') +
          skipNote +
          '</div></div>' +
          '<span class="ac-st">' +
          st +
          '</span></div>'
        );
      })
      .join('');
  }

  function countFilled(root, scope) {
    var total = 0;
    var filled = 0;
    qa(root, '[data-np-field="' + scope + '"]').forEach(function (el) {
      total++;
      if ((el.value || '').trim()) filled++;
    });
    return { total: total, filled: filled };
  }

  function countPill(root, group) {
    return root.querySelector(
      '[data-np-pill-group="' + group + '"] .pill.on, [data-np-pill-group="' + group + '"] .province-pill.on, [data-np-pill-group="' + group + '"] .lp.on',
    )
      ? 1
      : 0;
  }

  function countMulti(root, group) {
    return qa(
      root,
      '[data-np-pill-group="' + group + '"] .pill.on, [data-np-pill-group="' + group + '"] .province-pill.on',
    ).length;
  }

  function updateProgress(root) {
    var bizF = countFilled(root, 'biz');
    var finF = countFilled(root, 'fin');
    var solF = countFilled(root, 'solution');
    var techF = countFilled(root, 'tech');
    var riskF = countFilled(root, 'risk');
    var bmF = countFilled(root, 'biz-mode');
    var total = bizF.total + finF.total + solF.total + techF.total + riskF.total + bmF.total;
    var filled = bizF.filled + finF.filled + solF.filled + techF.filled + riskF.filled + bmF.filled;
    var pillTotal = 6;
    var pillFilled =
      (countMulti(root, 'tag1') > 0 ? 1 : 0) +
      countPill(root, 'tx') +
      countPill(root, 'good') +
      countPill(root, 'type') +
      countPill(root, 'owner1-lvl') +
      countPill(root, 'profit');
    total += pillTotal;
    filled += pillFilled;
    var provs = countMulti(root, 'provinces');
    if (provs > 0) filled += 1;
    total += 1;
    var pct = total ? Math.round((filled / total) * 100) : 0;
    var v = root.querySelector('#np-progress-val');
    if (v) v.textContent = String(pct);
    var bar = root.querySelector('#np-progress-bar');
    if (bar) bar.style.width = pct + '%';
    var bm = root.querySelector('#np-biz-meta');
    if (bm) bm.textContent = bizF.filled + pillFilled + ' / ' + (bizF.total + pillTotal);
    var fm = root.querySelector('#np-fin-meta');
    if (fm) {
      var finTotal = finF.total + solF.total + techF.total + riskF.total + bmF.total + 1;
      var finFilled = finF.filled + solF.filled + techF.filled + riskF.filled + bmF.filled + (provs > 0 ? 1 : 0);
      fm.textContent = finFilled + ' / ' + finTotal;
    }
    var scaleEl =
      root.querySelector('#p0-f-target-scale') ||
      qa(root, 'input.mono[placeholder="¥"][data-np-field="solution"]')[0];
    if (scaleEl) {
      var n = parseFloat(scaleEl.value) || 0;
      var stamp = root.querySelector('#np-stamp-val') || root.querySelector('#p0-stamp');
      if (stamp) stamp.textContent = n ? '¥ ' + Math.round(n * 10000 * 0.0003).toLocaleString() : '¥ —';
    }
  }

  function syncProvinceDiscount(root) {
    var picked = qa(root, '[data-np-pill-group="provinces"] .province-pill.on').map(function (p) {
      return p.getAttribute('data-v');
    });
    var box = root.querySelector('[data-np-dyn="province-discount"]');
    if (!box) return;
    if (!picked.length) {
      box.innerHTML =
        '<div style="padding:11px;border:1px dashed var(--border);background:var(--bg-soft);border-radius:8px;text-align:center;color:var(--text-3);font-size:10.5px">先选择上方覆盖省份后，此处自动生成各省折扣行</div>';
      return;
    }
    var existing = {};
    qa(box, '.dyn-row[data-prov]').forEach(function (r) {
      var p = r.getAttribute('data-prov');
      var ins = qa(r, 'input');
      existing[p] = { note: ins[0] ? ins[0].value : '', rate: ins[1] ? ins[1].value : '' };
    });
    var html = '';
    picked.forEach(function (p) {
      var v = existing[p] || { note: '', rate: '' };
      html +=
        '<div class="dyn-row" data-prov="' +
        p +
        '">' +
        '<div class="dr-cell" style="flex:0 0 64px"><div class="dr-lbl">省份</div><div style="padding:5px 8px;font-size:11px;font-weight:500;color:var(--text)">' +
        p +
        '</div></div>' +
        '<div class="dr-cell" style="flex:1.4"><div class="dr-lbl">档位说明</div><input class="dr-in" placeholder="如：普通档百四" value="' +
        v.note +
        '"></div>' +
        '<div class="dr-cell" style="flex:0 0 76px"><div class="dr-lbl">折扣</div><input class="dr-in mono" placeholder="0.4%" value="' +
        v.rate +
        '"></div></div>';
    });
    box.innerHTML = html;
  }

  function renderAiSummary(root) {
    var body = root.querySelector('#np-ai-summary-body');
    if (!body) return;
    var name = valByPlaceholder(root, '请填写提案名称');
    var scaleInputs = qa(root, 'input.mono[placeholder="¥"][data-np-field="solution"]');
    var scale = scaleInputs[0] ? parseFloat(scaleInputs[0].value) : 0;
    var profit = scaleInputs[1] ? parseFloat(scaleInputs[1].value) : 0;
    var provs = countMulti(root, 'provinces');
    var advance = readPill(root, 'advance');
    var taxBurden = readPill(root, 'tax-burden');
    if (!name && !scale && !profit && !provs) {
      body.innerHTML =
        '<div class="ais-empty"><i class="ti ti-sparkles"></i>提案内容尚未填写，无法生成摘要。请先补全关键字段后再点击「生成」</div>';
      return;
    }
    if (global.ProposalAPI && global.ProposalAPI.isLoggedIn()) {
      var payload = buildCreatePayload(root);
      global.ProposalAPI.previewAISummary(payload)
        .then(function (data) {
          renderAiSummaryBody(body, data, scale, profit, provs, advance, taxBurden);
        })
        .catch(function () {
          renderAiSummaryLocal(body, scale, profit, provs, advance, taxBurden);
        });
      return;
    }
    renderAiSummaryLocal(body, scale, profit, provs, advance, taxBurden);
  }

  function renderAiSummaryLocal(body, scale, profit, provs, advance, taxBurden) {
    var unit = scale && profit ? (profit * 10000 / ((scale * 10000) / 100)).toFixed(2) : '—';
    body.innerHTML =
      '<div class="ais-grid">' +
      '<div class="ais-cell"><div class="cl"><i class="ti ti-coin"></i>盈利模型</div><div class="cv">' +
      (profit ? '¥' + profit : '¥—') +
      '<span class="u">万/月</span></div><div class="cm">单笔毛利 ' +
      (unit !== '—' ? '¥' + unit : '—') +
      '</div></div>' +
      '<div class="ais-cell"><div class="cl"><i class="ti ti-chart-bar"></i>规模预估</div><div class="cv">' +
      (scale ? '¥' + scale : '¥—') +
      '<span class="u">万/月</span></div><div class="cm">覆盖 ' +
      provs +
      ' 省</div></div>' +
      '<div class="ais-cell"><div class="cl"><i class="ti ti-heartbeat"></i>财务健康</div><div class="cv" style="font-size:11px">' +
      (advance === '否' ? '不需垫资' : advance ? '需垫资' : '—') +
      '</div><div class="cm">税务承担 · ' +
      (taxBurden || '待填') +
      '</div></div>' +
      '<div class="ais-cell"><div class="cl"><i class="ti ti-alert-triangle" style="color:var(--amber)"></i>风险信号</div><div class="cv" style="color:var(--amber);font-size:11px">' +
      (provs > 0 ? '待评估' : '信息不足') +
      '</div><div class="cm">' +
      (provs > 0 ? '请补全分省折扣' : '请先选择省份') +
      '</div></div></div>' +
      '<div style="padding:8px 10px;background:#fff;border:1px solid var(--accent-line);border-radius:8px;font-size:11px;line-height:1.55;color:var(--text-2)"><span style="display:inline-flex;align-items:center;gap:3px;font-family:var(--mono);font-size:9px;color:var(--accent-deep);background:var(--accent-soft);padding:2px 6px;border-radius:4px;font-weight:600;margin-right:5px"><i class="ti ti-quote" style="font-size:9px"></i>结论</span>已根据当前已填字段生成摘要。建议补全分省折扣、四流链路与方案叙事后再次生成，以提升决策依据完整度。</div>';
  }

  function renderAiSummaryBody(body, data, scale, profit, provs, advance, taxBurden) {
    if (data && data.html) {
      body.innerHTML = data.html;
      return;
    }
    renderAiSummaryLocal(body, scale, profit, provs, advance, taxBurden);
  }

  function saveDraftLocal(root) {
    try {
      localStorage.setItem(DRAFT_KEY, JSON.stringify({ savedAt: Date.now(), html: root.querySelector('#np-root').innerHTML }));
    } catch (_) {}
  }

  async function submitProposal(root) {
    if (!global.ProposalAPI || !global.ProposalAPI.isLoggedIn()) {
      loginRedirect();
      return;
    }
    var payload = buildCreatePayload(root);
    var miss = validatePayload(payload);
    if (miss.length) {
      toast(root, '请补全：' + miss.join('、'), true);
      return;
    }
    try {
      var created = await global.ProposalAPI.createProposal(payload);
      var id = created.id || created.proposalId;
      await global.ProposalAPI.submitProposal(id, '');
      toast(root, '已提交审批 · 同步抄送 许正阳、郑咏熹');
      if (typeof global.pendingProposalId !== 'undefined') global.pendingProposalId = id;
      setTimeout(function () {
        if (typeof go === 'function') go('P1');
      }, 1200);
    } catch (err) {
      toast(root, (err && err.message) || '提交失败', true);
    }
  }

  async function pushToColleague(root) {
    if (!global.ProposalAPI || !global.ProposalAPI.isLoggedIn()) {
      loginRedirect();
      return;
    }
    var recipient = (root.querySelector('#np-push-sheet .fld-in[placeholder*="搜索"]') || {}).value || '';
    var note = (root.querySelector('#np-push-sheet textarea') || {}).value || '';
    if (!recipient.trim()) {
      toast(root, '请填写接收同事', true);
      return;
    }
    var payload = buildCreatePayload(root);
    try {
      var created = await global.ProposalAPI.createProposal(payload);
      var id = created.id || created.proposalId;
      await global.ProposalAPI.pushToInitiator(id, {
        initiator_name: recipient.trim(),
        message: note.trim(),
      });
      root.querySelector('#np-push-sheet').classList.remove('show');
      toast(root, '已推送，对方可在审批中心查看');
    } catch (err) {
      toast(root, (err && err.message) || '推送失败', true);
    }
  }

  function bindUi(root) {
    root.addEventListener('click', function (e) {
      var pill = e.target.closest('.pill, .province-pill, .lp');
      if (pill) {
        var group = pill.closest('[data-np-pill-group]');
        if (group) {
          var multi = group.getAttribute('data-multi') === 'true';
          if (multi) pill.classList.toggle('on');
          else {
            qa(group, '.pill, .province-pill, .lp').forEach(function (p) {
              p.classList.remove('on');
            });
            pill.classList.add('on');
          }
          var cond = group.getAttribute('data-np-conditional-show');
          if (cond) {
            var parts = cond.split('|');
            var target = root.querySelector(parts[0]);
            if (target) {
              var onP = group.querySelector('.pill.on');
              target.classList.toggle('show', !!(onP && onP.getAttribute('data-v') === parts[1]));
            }
          }
          if (group.getAttribute('data-np-pill-group') === 'provinces') syncProvinceDiscount(root);
          updateProgress(root);
          e.stopPropagation();
        }
      }
    });

    qa(root, '[data-np-toggle="tab"] .np-tab').forEach(function (b) {
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        qa(root, '[data-np-toggle="tab"] .np-tab').forEach(function (x) {
          x.classList.remove('on');
        });
        b.classList.add('on');
      });
    });
    qa(root, '[data-np-toggle="mode"] .sg').forEach(function (s) {
      s.addEventListener('click', function (e) {
        e.stopPropagation();
        qa(root, '[data-np-toggle="mode"] .sg').forEach(function (x) {
          x.classList.remove('on');
        });
        s.classList.add('on');
      });
    });

    root.addEventListener('click', function (e) {
      var addBtn = e.target.closest('[data-np-dyn-add]');
      if (addBtn) {
        e.stopPropagation();
        var key = addBtn.getAttribute('data-np-dyn-add');
        var list = root.querySelector('[data-np-dyn="' + key + '"]');
        if (!list) return;
        var existed = list.querySelector('.dyn-row');
        if (!existed) {
          toast(root, '请先填写上方相关字段');
          return;
        }
        var clone = existed.cloneNode(true);
        qa(clone, 'input,select,textarea').forEach(function (el) {
          if (el.tagName === 'SELECT') el.selectedIndex = 0;
          else el.value = '';
        });
        list.appendChild(clone);
        updateProgress(root);
      }
      var rmBtn = e.target.closest('[data-np-dyn-remove]');
      if (rmBtn) {
        e.stopPropagation();
        var row = rmBtn.closest('.dyn-row');
        var list = rmBtn.closest('.dyn-list');
        if (row && list && list.querySelectorAll('.dyn-row').length > 1) {
          row.remove();
          updateProgress(root);
        } else if (row) {
          toast(root, '至少保留一行，可清空内容');
          qa(row, 'input,select,textarea').forEach(function (el) {
            if (el.tagName === 'SELECT') el.selectedIndex = 0;
            else el.value = '';
          });
        }
      }
    });

    qa(root, '[data-np-guide]').forEach(function (c) {
      c.addEventListener('click', function (e) {
        e.stopPropagation();
        c.classList.add('used');
        var ta = root.querySelector('#np-solution-text');
        if (!ta) return;
        var tag = '【' + c.getAttribute('data-np-guide') + '】';
        var pos = ta.selectionStart || ta.value.length;
        var before = ta.value.substring(0, pos);
        var after = ta.value.substring(pos);
        var prefix = before.length && !before.endsWith('\n') ? '\n\n' : '';
        ta.value = before + prefix + tag + after;
        ta.focus();
        updateProgress(root);
      });
    });

    root.addEventListener('click', function (e) {
      var actBtn = e.target.closest('[data-np-act]');
      if (!actBtn) return;
      var act = actBtn.getAttribute('data-np-act');
      e.stopPropagation();
      if (act === 'excel') {
        if (typeof go === 'function') go('P0I');
        else toast(root, '请使用 JSON 导入屏 P0I');
        return;
      }
      if (act === 'save') {
        saveDraftLocal(root);
        toast(root, '草稿已暂存');
        return;
      }
      if (act === 'push') {
        var s = root.querySelector('#np-push-sheet');
        if (s) s.classList.add('show');
        return;
      }
      if (act === 'push-close') {
        var sheet = root.querySelector('#np-push-sheet');
        if (sheet) sheet.classList.remove('show');
        return;
      }
      if (act === 'push-confirm') {
        pushToColleague(root);
        return;
      }
      if (act === 'ai-policy') {
        var out = root.querySelector('#np-ai-policy-out');
        var noteTa =
          root.querySelector('#p0-f-discount-policy-note') ||
          root.querySelector('textarea[placeholder*="档位"]');
        if (!out) return;
        if (!noteTa || !noteTa.value.trim()) {
          if (out.tagName === 'TEXTAREA') {
            out.value = '';
            out.placeholder = '请先在「折扣政策备注」填写各省档位说明';
          } else {
            out.className = 'ai-policy-out empty';
            out.textContent = '请先在「折扣政策备注」填写各省档位说明';
          }
          return;
        }
        var setOut = function (text) {
          if (out.tagName === 'TEXTAREA') {
            out.value = text;
            out.classList.remove('empty');
          } else {
            out.className = 'ai-policy-out';
            out.innerHTML = '<b>AI 建议</b>：' + text;
          }
        };
        if (global.ProposalAPI && global.ProposalAPI.isLoggedIn()) {
          global.ProposalAPI.suggestDiscountPolicy(buildCreatePayload(root))
            .then(function (data) {
              setOut(data.suggestion || data.text || '已生成');
            })
            .catch(function () {
              setOut(
                '依据已填写的档位备注，对照覆盖省份矩阵核对差异；如某省档位明显偏离整体均值，建议复核政策文件是否覆盖该省。',
              );
            });
        } else {
          setOut(
            '依据已填写的档位备注，对照覆盖省份矩阵核对差异；如某省档位明显偏离整体均值，建议复核政策文件是否覆盖该省。',
          );
        }
        return;
      }
      if (act === 'ai-narrative') {
        var ta = root.querySelector('#np-solution-text');
        if (!ta || !ta.value.trim()) {
          toast(root, '请先输入部分方案文字');
          return;
        }
        if (global.ProposalAPI && global.ProposalAPI.isLoggedIn()) {
          global.ProposalAPI.enhanceText({ text: ta.value, mode: 'polish' })
            .then(function (data) {
              if (data && data.text) ta.value = data.text;
              toast(root, 'AI 已优化文字');
            })
            .catch(function () {
              toast(root, 'AI 已优化文字（演示）');
            });
        } else toast(root, 'AI 已优化文字（演示）');
        return;
      }
      if (act === 'ai-summary') {
        renderAiSummary(root);
        return;
      }
      if (act === 'submit') {
        submitProposal(root);
        return;
      }
      if (act === 'upload-solution' || act === 'upload-contract') {
        var box = root.querySelector(act === 'upload-solution' ? '#np-solution-files' : '#np-contract-files');
        if (box) {
          var d = document.createElement('div');
          d.className = 'file-item';
          var icon = act === 'upload-solution' ? 'ti-file' : 'ti-file-certificate';
          d.innerHTML =
            '<i class="ti ' +
            icon +
            '"></i><span class="fl-nm">点击选择文件后此处显示</span><button class="fl-x" type="button" data-np-rm-file><i class="ti ti-x"></i></button>';
          box.appendChild(d);
        }
        return;
      }
    });

    root.addEventListener('click', function (e) {
      var rm = e.target.closest('[data-np-rm-file]');
      if (!rm) return;
      e.stopPropagation();
      var item = rm.closest('.file-item');
      if (item) item.remove();
    });

    var techSel = root.querySelector('#np-tech-platform');
    if (techSel) {
      techSel.addEventListener('change', function () {
        refreshApprovalChain(root);
        updateProgress(root);
      });
    }

    root.addEventListener('input', function () {
      updateProgress(root);
    });
    root.addEventListener('change', function () {
      updateProgress(root);
    });
  }

  function init(root) {
    if (!root || root.dataset.npBound) return;
    root.dataset.npBound = '1';
    bindUi(root);
    fillUserPill(root);
    fillBeaconHint(root);
    refreshApprovalChain(root);
    updateProgress(root);
  }

  function onScreenShow() {
    var root = document.querySelector('.screen[data-screen="P0"]');
    if (root) {
      fillUserPill(root);
      refreshApprovalChain(root);
    }
  }

  global.ProposalP0Intake = {
    init: init,
    onScreenShow: onScreenShow,
    buildCreatePayload: buildCreatePayload,
    readBusinessFromP0: readBusinessFromP0,
    setBeaconProject: function (projectId, projectName) {
      var ctx = { projectId: projectId || '', projectName: projectName || '' };
      try {
        sessionStorage.setItem(BEACON_KEY, JSON.stringify(ctx));
      } catch (_) {}
    },
  };
})(typeof window !== 'undefined' ? window : global);
