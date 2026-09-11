import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'payment_invoice_catalog.dart';

pw.Font? _printFont;

Future<pw.Font> loadPaymentInvoicePrintFont() async {
  final cached = _printFont;
  if (cached != null) return cached;
  final data = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
  return _printFont = pw.Font.ttf(data);
}

Future<Uint8List> buildPaymentInvoicePdf({
  required PaymentInvoiceRow row,
  required PaymentInvoiceKind kind,
}) async {
  final font = await loadPaymentInvoicePrintFont();
  final theme = pw.ThemeData.withFont(base: font, bold: font);
  final fields = <(String, String)>[
    ('审批名称', row.title.isEmpty ? '—' : row.title),
    ('审批编号', row.displayId),
    ('发起人', row.createdByName.isEmpty ? '—' : row.createdByName),
    ('发起日期', _dateTimeLabel(row.createdAt)),
    ('审批状态', paymentInvoiceStatusLabel(row.status)),
    ('申请事由', row.purpose.isEmpty ? '—' : row.purpose),
    if (kind == PaymentInvoiceKind.payment) ...[
      ('收款账户', row.payeeAccount.isEmpty ? '—' : row.payeeAccount),
      ('付款类型', row.payAccountType.isEmpty ? '—' : row.payAccountType),
      ('是否完结', row.paymentCompleted ? '已完结' : '未完结'),
    ] else ...[
      ('客户/推广商', row.counterparty.isEmpty ? '—' : row.counterparty),
      ('申请金额', formatPaymentInvoiceMoney(row.appliedAmount)),
      ('已开金额', formatPaymentInvoiceMoney(row.issuedAmount)),
      ('未开金额', formatPaymentInvoiceMoney(row.unissuedAmount)),
      ('开票状态', invoiceIssueStatusLabel(row.issueStatus)),
    ],
  ];

  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
      build: (context) => [
        pw.Text(
          kind == PaymentInvoiceKind.invoice ? '发票审批单' : '付款审批单',
          style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          row.title.isEmpty ? '审批单' : row.title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
          columnWidths: const {
            0: pw.FixedColumnWidth(92),
            1: pw.FlexColumnWidth(),
          },
          children: [
            for (final field in fields)
              pw.TableRow(
                children: [
                  pw.Container(
                    color: PdfColors.grey200,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: pw.Text(
                      field.$1,
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: pw.Text(
                      field.$2,
                      style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

Future<void> printPaymentInvoiceRow({
  required PaymentInvoiceRow row,
  required PaymentInvoiceKind kind,
}) async {
  final name = row.title.trim().isEmpty ? '审批单' : row.title.trim();
  await Printing.layoutPdf(
    name: name,
    onLayout: (_) => buildPaymentInvoicePdf(row: row, kind: kind),
  );
}

String _dateTimeLabel(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
