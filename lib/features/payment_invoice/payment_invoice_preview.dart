import 'payment_invoice_catalog.dart';

/// 先看效果用。看完改回 false，工作台会走真实接口和权限开关。
const kPaymentInvoiceStaticPreview = false;

List<PaymentInvoiceRow> paymentInvoicePreviewRows() {
  return [
    paymentInvoiceRowFromListJson({
      'businessId': 2079879674728558593,
      'code': '2079879674728558593',
      'businessType': 'FINANCE_ADMIN_PROCUREMENT',
      'templateKey': 'finance-admin-procurement',
      'title': '叶子扬行政采购审批',
      'status': 'APPROVED',
      'createdByName': '叶子扬',
      'createdAt': '2026-07-20T18:33:00',
      'formData': {
        'expensePurpose':
            '沅星智联（江苏）注销代理服务费\n根据持股比例，费用由股东分别承担，源畅承担1100*49%=539元；\n付款方：上海卓悦优泰\n发票、注销完成回执，见附件',
        'payeeAccount':
            '收款账户：苏州灵辰财税咨询有限公司\n上海浦东发展银行\n8901007880110',
        'payAccountType': '对公',
        'payStatus': '待支付',
        'completed': false,
      },
    }),
    paymentInvoiceRowFromListJson({
      'businessId': 1999371572867100674,
      'code': '1999371572867100674',
      'businessType': 'FINANCE_ADMIN_PROCUREMENT',
      'templateKey': 'finance-admin-procurement',
      'title': '洪梅行政采购审批',
      'status': 'APPROVED',
      'createdByName': '洪梅',
      'createdAt': '2025-12-10T15:57:14',
      'formData': {
        'expensePurpose':
            '苏州元兴智联股东变更（工商、税务、银行）费用合计1500元。\n付款单位:苏州元兴智联',
        'payeeAccount':
            '收款账户:苏州灵辰财税咨询有限公司\n开户行: 中国民生银行',
        'payAccountType': '对公',
        'payStatus': '已支付',
        'completed': false,
      },
    }),
    paymentInvoiceRowFromListJson({
      'businessId': 1981284008486617090,
      'code': '1981284008486617090',
      'businessType': 'FINANCE_ADMIN_PROCUREMENT',
      'templateKey': 'finance-admin-procurement',
      'title': '叶子扬行政采购审批',
      'status': 'APPROVED',
      'createdByName': '叶子扬',
      'createdAt': '2025-10-22T09:57:56',
      'formData': {
        'expensePurpose': '森禄科技工商税务银行全流程办理\n服务商: 苏州灵辰财税\n合计4500元',
        'payeeAccount': '6979999\n苏州灵辰财税咨询\n中国民生银行苏州分行',
        'payAccountType': '对公',
        'payStatus': '已支付',
        'completed': true,
      },
    }),
    paymentInvoiceRowFromListJson({
      'businessId': 188200110022,
      'code': '188200110022334455',
      'businessType': 'FINANCE_PROMOTION_PAYMENT',
      'templateKey': 'finance-promotion-payment',
      'title': '推广费付款申请单',
      'status': 'APPROVED',
      'createdByName': '王敏',
      'createdAt': '2026-08-12T11:20:08',
      'formData': {
        'expensePurpose': '渠道投放-信息流推广费，对应8月结算',
        'payeeAccount': '杭州推客网络科技有限公司\n招商银行 5719 **** 8821',
        'payAccountType': '对公',
        'promoterName': '杭州推客',
        'completed': false,
      },
    }),
    ...[
      for (final item in [
        (188201, '2026-06-03T09:10:00', '陈青', '业务采购申请单', '服务器托管年费 36000元', '对公'),
        (188202, '2026-05-18T14:22:00', '洪梅', '行政采购审批', '办公软件续费，费用由行政承担', '对公'),
        (188203, '2026-04-09T11:08:00', '叶子扬', '预付款申请', '供应商备货预付款 8000元', '对公'),
        (188204, '2026-03-21T16:40:00', '王敏', '推广费付款申请单', '信息流补量，对应3月结算', '对公'),
        (188205, '2026-02-14T10:05:00', '陈青', '合同付款', '框架合同第二期款项', '对公'),
        (188206, '2026-01-08T08:30:00', '赵六', '业务采购申请单', '测试手机采购 3 台', '对私'),
        (188207, '2025-12-28T19:12:00', '洪梅', '行政采购审批', '年会场地布置及物料', '对公'),
        (188208, '2025-11-11T13:45:00', '叶子扬', '预付款申请', '印刷制作预付 2000元', '对公'),
      ])
        paymentInvoiceRowFromListJson({
          'businessId': item.$1,
          'code': '${item.$1}',
          'businessType': 'FINANCE_ADMIN_PROCUREMENT',
          'templateKey': 'finance-admin-procurement',
          'title': item.$4,
          'status': 'APPROVED',
          'createdByName': item.$3,
          'createdAt': item.$2,
          'formData': {
            'expensePurpose': item.$5,
            'payeeAccount': '苏州灵辰财税咨询有限公司',
            'payAccountType': item.$6,
            'completed': false,
          },
        }),
    ],
    paymentInvoiceRowFromListJson({
      'businessId': 90018,
      'code': 'INV-202609-018',
      'businessType': 'INVOICE',
      'title': '发票申请',
      'status': 'APPROVED',
      'createdByName': '赵六',
      'createdAt': '2026-09-03T09:12:00',
      'formData': {
        'expensePurpose': '信息服务费 / 平安分批开票',
        'customerName': '中国平安',
        'appliedAmount': 200000,
        'issuedAmount': 80000,
      },
    }),
    paymentInvoiceRowFromListJson({
      'businessId': 90007,
      'code': 'INV-202608-007',
      'businessType': 'INVOICE',
      'title': '发票申请',
      'status': 'APPROVED',
      'createdByName': '陈青',
      'createdAt': '2026-08-21T16:40:00',
      'formData': {
        'expensePurpose': '软件实施费',
        'customerName': '平安银行',
        'appliedAmount': 56000,
        'issuedAmount': 0,
      },
    }),
    paymentInvoiceRowFromListJson({
      'businessId': 90003,
      'code': 'INV-202607-003',
      'businessType': 'INVOICE',
      'title': '发票申请',
      'status': 'APPROVED',
      'createdByName': '赵六',
      'createdAt': '2026-07-09T10:05:00',
      'formData': {
        'expensePurpose': '年度框架开票',
        'customerName': '平安产险',
        'appliedAmount': 120000,
        'issuedAmount': 120000,
        'issueStatus': '已完结',
      },
    }),
  ];
}
