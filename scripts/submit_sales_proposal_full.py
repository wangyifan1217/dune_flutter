#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import sys
import urllib.error
import urllib.request

GATEWAY = "http://124.221.216.24:6090/api/v1"
FLOW = "http://124.221.216.24:6087/api/v1"
PHONE = "15268642022"


def post(base: str, path: str, body: dict, token: str | None = None) -> dict:
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{base}{path}",
        data=data,
        method="POST",
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{base}{path} => {err}") from e


def get(base: str, path: str, token: str) -> dict:
    req = urllib.request.Request(
        f"{base}{path}",
        method="GET",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> None:
    code = sys.argv[1] if len(sys.argv) > 1 else ""
    if not code:
        print("Usage: submit_sales_proposal_full.py <sms_code>")
        sys.exit(1)

    print("=== Login ===")
    login = post(GATEWAY, "/auth/sms/token", {"phone": PHONE, "code": code, "channel": "app"})
    if not login.get("success"):
        raise RuntimeError(f"login failed: {login}")
    token = login["data"]["token"]
    print("OK")

    form = {
        "title": "平安产险湖北电子券渠道合作提案",
        "launchChannel": "平安产险",
        "launchDate": "2026-08-01",
        "txType": "销售",
        "goodType": "虚拟商品",
        "proposalType": "新增",
        "tag1": ["COUPON"],
        "provinces": ["湖北省", "湖南省"],
        "owner1": {"userId": 2, "name": "王奕凡", "displayName": "王奕凡"},
        "owner1Level": "B",
        "taskLevel": "B",
        "owner2": {"userId": 1, "name": "朱子姝", "displayName": "朱子姝"},
        "owner2Level": "A",
        "respNational": {"userId": 2, "name": "王奕凡"},
        "respOps": {"userId": 1, "name": "朱子姝"},
        "respProvince": {"userId": 2, "name": "王奕凡"},
        "respTech": {"userId": 5, "name": "缪承恭"},
        "techPlatform": "蓝鲸",
        "targetMonthlyScaleWan": "80",
        "targetMonthlyProfitWan": "8",
        "needAdvanceFund": "否",
        "hasInvoiceTaxCost": "无",
        "taxBurdenSide": "无",
        "needRollback": "否",
        "profitModel": "服务费",
        "settlementCycles": [{"cycle": "补贴", "term": "T+7", "weight": "100"}],
        "provinceDiscounts": [
            {"province": "湖北省", "rate": "0.95", "note": "首年合作优惠档位"},
            {"province": "湖南省", "rate": "0.96", "note": "试点省份"},
        ],
        "discountPolicyNote": "按月度规模阶梯执行：50万以下0.96，50-100万0.95，100万以上另行审批。",
        "supplierPolicies": [
            {
                "supplier": "中石化湖北",
                "baseTier": "0.98",
                "currentRate": "0.95",
                "marketing": "季度返利1%",
                "nonOil": "无",
                "tieredOrgFee": [
                    {"tierType": "below", "threshold": "50", "rate": "0.96"},
                    {"tierType": "met", "threshold": "50", "rate": "0.95"},
                ],
            }
        ],
        "channelPolicies": [
            {"channel": "平安产险APP", "universalRate": "1.2", "marketingRate": "0.8"}
        ],
        "oilBundleRows": [
            {
                "product": "92#汽油券",
                "cost": "200",
                "salePrice": "210",
                "customerPrice": "205",
                "rebate": "2%",
            }
        ],
        "supplyScaleByProvince": [
            {"province": "湖北省", "stock": "5000", "increment": "800"},
            {"province": "湖南省", "stock": "2000", "increment": "300"},
        ],
        "pricingMatrix": [
            {"supplier": "中石化湖北", "scale": "80万/月", "discount": "0.95", "premium": "0"}
        ],
        "provinceCosts": [
            {"province": "湖北", "projectCost": "2", "marketing": "1", "tech": "0.5"}
        ],
        "invoiceFlows": [
            {"from": "我方", "to": "平安产险", "amount": "80万/月", "note": "服务费发票6%"}
        ],
        "capitalFlows": [
            {"from": "平安产险", "to": "我方", "amount": "T+7结算", "note": "无垫资"}
        ],
        "solutionDesc": (
            "合作背景：平安产险拟在湖北、湖南两省开展电子券加油权益合作，通过蓝鲸平台对接发券与核销。\n"
            "合作模式：B2B2C电子券销售，我方提供供应链与技术服务，渠道方负责获客与结算。\n"
            "预期收益：承诺月规模80万，月毛利8万，结算周期T+7，无垫资。\n"
            "实施计划：2026年8月上线试点，9月评估扩省。"
        ),
        "techCapability": "蓝鲸平台已具备电子券发券、核销、对账能力；支持分省折扣与四流链路留痕。",
        "riskTech": "接口限流与熔断已配置；核销异常自动告警；日对账差异<0.1%。",
        "riskBusiness": "渠道资质已核验；合作框架协议待法务终审；分省折扣在授权范围内。",
        "riskFinance": "无垫资；T+7回款；印花税已测算；发票流与资金流已对齐。",
        "financeRemark": "本提案为新增合作，请各部门按审批链确认后推进上线。",
        "projectName": "平安产险电子券合作项目",
    }

    print("=== Submit ===")
    submit = post(FLOW, "/xflow/templates/sales-proposal/submit", form, token)
    if not submit.get("success"):
        raise RuntimeError(f"submit failed: {submit}")
    data = submit.get("data") or {}
    pid = data.get("businessId") or data.get("proposalId") or data.get("id")
    print(f"proposalId={pid} status={data.get('status')} mode={data.get('mode')}")

    detail = get(FLOW, f"/xflow/proposals/{pid}/detail", token)
    d = detail.get("data") or {}
    print(f"title={d.get('title')}")
    print(f"code={d.get('code')}")
    print("DONE")


if __name__ == "__main__":
    main()
