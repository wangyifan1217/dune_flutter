import type { DiffHunk } from "../types/codex";

/** 从工具输出里尽量抽出 diff / 文件变更摘要 */
export function extractDiffsFromText(text: string): DiffHunk[] {
  const hunks: DiffHunk[] = [];

  const fence = /```(?:diff|patch)?\n([\s\S]*?)```/gi;
  let match: RegExpExecArray | null;
  while ((match = fence.exec(text)) !== null) {
    const content = match[1].trim();
    if (!content.includes("+++") && !content.includes("---") && !content.startsWith("diff ")) {
      continue;
    }
    const pathMatch = content.match(/(?:---|\+\+\+|diff --git).*?[\\/]?([^\s\\/]+)/);
    hunks.push({
      id: crypto.randomUUID(),
      path: pathMatch?.[1] ?? "变更",
      summary: "检测到代码 diff",
      content,
    });
  }

  const writeHint = /(?:Wrote|写入|Updated|修改)[^\n]*?([A-Za-z0-9_\-./\\]+\.[A-Za-z0-9]+)/gi;
  while ((match = writeHint.exec(text)) !== null) {
    hunks.push({
      id: crypto.randomUUID(),
      path: match[1],
      summary: "文件已更新",
      content: text.slice(Math.max(0, match.index - 40), match.index + 200),
    });
  }

  return hunks;
}
